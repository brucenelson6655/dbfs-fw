---
description: Learn about configuring your Azure storage firewalls to support serverless SQL warehouses.
---

.. aws-gcp::
    ---
    orphan: 1
    ---

.. <FeatureName> replace:: firewall support for workspace default storage
.. <WDS> replace:: workspace default storage

# Enable <FeatureName>

.. include:: /shared/preview.md

## <a id="overview"></a> Overview of <FeatureName>

This article shows how to use an ARM template to limit access to workspace default storage from only authorized resources and networks.

When <Databricks> creates a workspace, a storage account is created in a managed resource group. This workspace default storage includes workspace system data (job output, system settings, and logs), DBFS root, and in some cases a Unity Catalog workspace catalog. That Azure storage account accepts authenticated connections from all networks as a default. You can limit this access using [Azure Storage firewall](https://learn.microsoft.com/azure/storage/common/storage-network-security?tabs=azure-portal) by enabling <FeatureName>.

.. tip:: Some documentation previously referred to the entire Azure storage account as _DBFS root_. The [DBFS root](/dbfs/dbfs-root.md) is only one part of your _workspace default storage_.

To enable or disable <FeatureName>, you must deploy the [ARM template](https://learn.microsoft.com/azure/azure-resource-manager/templates/overview) that's provided in this article. This feature is controlled by the ARM template property `storageAccountFirewall`, which must be set to `Enabled`. The Azure portal does not have an option to enable or disable <FeatureName>.

After you enable <FeatureName> on a workspace, two things happen:

- <Databricks> changes the network access to the storage account from **Access from all networks** to **Access from selected networks**

- <Databricks> creates an [Access Connector](/data-governance/unity-catalog/azure-managed-identities.md) to connect to the storage. For typical use cases, let the template create a new Access Connector. The Access Connector is a trust object backed by a system OS user-assigned managed identity that allows Azure Databricks control plane to bypass your storage firewall. For more information about managed identities, see [this Microsoft article](https://learn.microsoft.com/entra/identity/managed-identities-azure-resources/overview). If you have an Access Connector that you want to use instead, provide its name when you deploy the template. You can also optionally specify a user-managed identity resource ID when you deploy the template if you use a user-managed identity.

To ensure proper access, configure one or more private endpoints to the storage account from your workspace's VNet that's used by your workspace's classic compute plane. You also must add endpoints from any additional network that needs direct access to the <WDS>, such as for Cloud Fetch for [JDBC](/integrations/jdbc/capability.md#cloud-fetch-in-jdbc) or [ODBC](/integrations/odbc/capability.md#cloud-fetch-in-odbc).

To support connections from serverless SQL warehouses to <WDS>, there are additional configuration steps that allow access from serverless SQL warehouse subnets using service endpoints from serverless SQL warehouse subnets. This support does not extend to other serverless resources such as Model Serving. See [_](#serverless).

.. note:: If you want network traffic from serverless SQL warehouses to use Private Link connections, you must join a separate preview. Contact your <Databricks> account representative.

### Security benefits

- The Azure storage account for <WDS> is inaccessible from unauthorized networks.

- All access from services outside <Databricks> to the Azure storage account for <WDS> must use approved private endpoints with Private Link. This includes access through pre-signed URLs such as those used for Cloud Fetch.

- Access to the storage account must either use service endpoints or private endpoints. Public network access is disallowed. For access from serverless SQL warehouses, service endpoints are the default but private endpoints are possible if you join a separate preview.

- The Azure storage account for <WDS> complies with Azure policies that ensure storage accounts are private.

## <a id="requirements"></a> Requirements

- The workspace must enable [VNet injection](/security/network/classic/vnet-inject.md).

- The workspace must enable [secure cluster connectivity](/security/network/classic/secure-cluster-connectivity.md). In ARM templates from <Databricks>, the parameter is sometimes called **No Public Ip** or **Disable Public Ip**.

- The workspace must use the Premium pricing tier. To update a workspace to enable <FeatureName>, <Databricks> upgrades the workspace to Premium if necessary. See the [pricing page](https://databricks.com/product/pricing/platform-addons).

- There must be a separate subnet for the private endpoints for the storage account other than the main two subnets for basic <Databricks> functionality. The subnet must be in the same VNet as the workspace (for the classic compute plane) or in a separate VNet that the workspace can access. Use the minimum size `/28` in CIDR notation.

- Model Serving is not used in this workspace. It is unsupported by this public preview.


## <a id="prep-or-create-workspace"></a> Step 1: Prepare for workspace creation or update

### Prepare a new workspace

The [VNet injection](/security/network/classic/vnet-inject.md) feature must be enabled on workspaces that use <FeatureName>. VNet injection means creating your own VNet in which to deploy <Databricks>.

For new workspaces, deploying [this article's included template](#template-workspace) does not automatically create the VNet and network security group (NSG).

Before using the included workspace template, create the following Azure resources:

- One VNet

- Three subnets for the VNet

  - Two subnets for core <Databricks> functioning. For details about subnet sizing, see [_](/security/network/classic/vnet-inject.md).

  - A separate subnet for private endpoints. This could be in your workspace VNet (for the classic compute plane) or in a separate VNet that the workspace can access. Use the minimum size `/28` in CIDR notation. This subnet is in addition to your main two required subnets that are required for basic <Databricks> functionality.

    .. important:: You need a separate subnet to host your private endpoints.

- One network security group (NSG) attached to the VNet.

Every organization's requirements are different, and you may already have a VNet you need to use provided by your organization. For initial testing, Databricks provides a template that just creates the VNet, the subnets, and network security group. See [_](#template-vnet).


### Prepare an existing workspace

For existing workspaces, confirm that the workspace is running and that it has the existing workspace features:

<!-- QUESTION FOR BRUCE: WHAT'S THE BEST WAY TO TELL CUSTOMERS TO TELL WHETHER THEY HAVE THESE ENABLED IN AN EXISTING WORKSPACE, OFFICIALLY SPEAKING? WE JUST NEED ONE WAY. -->

#. Confirm the workspace is running. If you recently created the workspace, but the deployment failed, you cannot yet enable <FeatureName>. If the workspace is not in the Running state, fix any problems with your workspace configuration and re-deploy it before proceeding with the next step.

#. Confirm the workspace uses [Secure cluster connectivity](/security/network/classic/secure-cluster-connectivity.md), which in <Databricks> templates is called **No Public Ip**. Unlike VNet injection, you can enable secure cluster connectivity on a workspace where it is currently disabled.

#. Confirm the workspace uses [VNet injection (customer-managed VNet)](/security/network/classic/vnet-inject.md): You cannot enable VNet injection on an existing workspace that uses the default VNet.

#. Confirm that your workspace VNet has has an extra subnet for private endpoints. It could also be in a separate VNet that the workspace can access. Use the minimum size `/28` in CIDR notation. This subnet is in addition to your main two required subnets that are required for basic <Databricks> functionality.

   .. important:: You need a separate subnet to host your private endpoints.

#. Confirm that you have have access to the property values for your existing workspace, such as its resource group, its workspace name, and other configuration information that you used to create the workspace. If you use customer-managed keys for managed services, be sure to have your encryption key information. If you do not have a clear record of these values, you can extract this information from workspace JSON. Navigate to the workspace instance in Azure portal (an instance of Azure Databricks service). In the overview page, click **Resource JSON** and copy the fields as needed.

#. Shut down any clusters or other compute resources.

## <a id="default-update"></a> Step 2: Deploy the required ARM template

#. Copy the ARM template from [_](#template-workspace).

#. In Azure portal, search for "Deploy a custom template" and select that item.

#. Click **Build your own template in the editor**.

#. Paste in the template in [_](#template-workspace).

#. Click **Save**.

#. Review and edit fields:
jxbell marked this conversation as resolved.

   .. list-table::
     :header-rows: 1

     * - Field
       - Description
     * - **Subscription**
       - Azure subscription to use.
     * - **Resource group**
       - Resource group to use. This typically matches the resource group of your VNet.
     * - **Workspace Name**
       - Name of the workspace. If you're doing a workspace update rather than creating a new workspace, be extremely careful to type the workspace name correctly. If it does not match an existing workspace name in this Azure tenant, Azure will create a new workspace.
     * - **Managed Resource Group Name**
       - The managed resource group for your workspace. This auto-populates in the form to a default name. Change it if your organization wants to customize the managed resource group name.
     * - **Storage Account Name**
       - The Azure storage account for <WDS> in your managed resource group. This auto-populates in the form to a default name. Change it if your organization wants to customize the managed resource group name.
     * - **Workspace VNet Network Id**
       - The resource ID for your VNet. For an existing workspace, you can get this by navigating to the workspace in the Azure portal. Click **Properties**. Under **Custom virtual network Id**, click  **View value as JSON**. Copy the resource ID in the `value` field.
     * - **Custom Private Subnet Name**
       - The private subnet for your VNet. For an existing workspace, you can get this by navigating to the workspace in the Azure portal. Click **Properties**. Under **private subnet**, click  **View value as JSON**. Copy the resource ID in the `value` field.
     * - **Custom Public Subnet Name**
       - The public subnet for your VNet. For an existing workspace, you can get this by navigating to the workspace in the Azure portal. Click **Properties**. Under **public subnet**, click  **View value as JSON**. Copy the resource ID in the `value` field.
     * - **Location**
       - The short name for the Azure region. this should match the region field at the top, but is provided as the short name, such as **eastus** not **(US) East US**. This auto-populates to match the main **Region** field.
     * - **Access Connector Name**
       - For typical deployments, don't modify this field. <Databricks> creates a new Access Connector. To use an existing Access Connector, specify its name here. To create an Access Connector, see [_](/data-governance/unity-catalog/azure-managed-identities.md#config-managed-id) and _only do step 1_.
     * - **Managed Identity Type**
       - For typical deployments, don't modify this field. Choose between **SystemAssigned**, **UserAssigned**, or **both**. For **SystemAssigned** or **both**, the Access connector uses the system-assigned managed identity for storage credentials. If you specify **UserAssigned**, the Access Connector uses it for storage credentials. To create a user-managed identity, see [this Microsoft article](https://learn.microsoft.com/entra/identity/managed-identities-azure-resources/how-manage-user-assigned-managed-identities?pivots=identity-mi-methods-azp). To create a system-assigned managed identity, see [_](/data-governance/unity-catalog/azure-managed-identities.md#create-connector). <!-- SHOULD SPECIFY THE DEFAULT VALUE, SYSTEM I ASSUME? -->
     * - **User Managed Identity Resource ID**
       - For typical deployments, don't modify this field. Only set this field if you set **Managed Identity Type** to **UserAssigned**. The resource ID of the User Assigned Managed Identity if using UserAssigned Managed Identities
     * - **Storage Account Firewall**
       - Specifies whether to enable <FeatureName>. If you set this to `false`, it is critical to carefully set the **Workspace Catalog Enabled** field correctly.
     * - **Disable Public Ip**
       - This must be set to `true`. This enables [secure cluster connectivity](/security/network/classic/secure-cluster-connectivity.md), which is required for <FeatureName>. This is sometimes called Disable Public IP or No Public IP.
     * - **Public Network Access**
       - Typically set this to **Enabled**. If you enable Private Link, see [_](/security/network/classic/private-link.md) for what settings to use.
     * - **Required Nsg Rules**
       - Typically set this to **All Rules**. If you enable Private Link, see [_](/security/network/classic/private-link.md) for what settings to use.
     * - **Customer Managed Keys Enabled**
       - Set this true if you use customer-managed keys for managed services or managed disks. See [_](/security/keys/customer-managed-keys.md). Configure the details in the other field **Customer Managed Keys Type**. Customer-managed keys for workspace storage (on Azure, this is sometimes called _customer-managed keys for DBFS root_) is not configured here.
     * - **Customer Managed Keys Type**
       - Selects the customer-managed key types for this workspace. Choose **Managed Services**, **ManagedDisks**, or **Both**. Set the appropriate fields below. See [_](/security/keys/customer-managed-keys.md). Customer-managed keys for workspace storage (on Azure, this is sometimes called _customer-managed keys for DBFS root_) is not configured here.
     * - **Managed Svc Key Vault Key Id**
       - Only if you use customer-managed keys for managed services, specify the key vault Key ID. 
     * - **Managed Disk Key Vault Key Id**
       - Only if you use customer-managed keys for managed disks, specify the key vault Key ID.
     * - **Managed Disk Auto Rotation**
       - Only if you use customer-managed keys for managed disks, specify whether to pick up new key versions automatically.

#. Click **Review and Create**, then **Create**.

   .. note:: The template sets the pricing tier to Premium because it is required to enable <FeatureName>. If you're updating an existing workspace that's on Standard tier, applying the template upgrades the workspace to Premium tier. See the [pricing page](https://databricks.com/product/pricing/platform-addons).

#. Wait until the deployment is complete.

Your workspace is temporarily unable to run notebooks or jobs until you create your private endpoints.

## <a id="create-private-endpoints-main"></a> Step 3: Create private endpoints to the storage account

Create the private endpoints to your workspace's Azure storage account for <WDS> from your VNet that you use for your <Databricks> [classic compute plane](/getting-started/overview.md). This is the VNet that you used for [VNet injection](/security/network/classic/vnet-inject.md).

Create two endpoints for each network source but with different name and different **Target sub-resource** values: `dfs` and `blob`. For each endpoint do the following steps:

#. In the Azure portal, navigate to your workspace instance with resource type Azure Databricks Service.

#. Next to the **Managed Resource Group** field, click the name of the managed resource group.

#. In the list of resources in the managed resource group, click the resource of type **Storage account** that has a name that begins with `dbstorage` followed by other letters and numbers.

#. In the left navigation, click **Networking**.

#. Click **Private endpoint connections**.

#. To create one private endpoint, click **+ Private endpoint**.

   .. important:: Some workspaces created in 2022 or earlier might prevent creating private endpoints. To resolve, contact your <Databricks> support representative.

#. In the **Resource Group** name field, set your resource group.

   .. important:: You always must explicitly change this value to be a resource group in your control. Databricks recommends that you use the resource group of your workspace. This field is set initially to the read-only managed resource group for your workspace.

#. In the **Name** field, type a unique name for this private endpoint:

   - For the first private endpoint you create for each source network, create a DFS endpoint. Databricks recommends you add the suffix `-dfs-pe`

   - For the second private endpoint you create for each source network, create a Blob endpoint. Databricks recommends you add the suffix `-blob-pe`

   The **Network Interface Name** field auto-populates with the name, which is the value of the **Name** field, followed by the suffix `-nic`.

#. Set the **Region** field to the region of your workspace.

#. At the bottom of the page, click **Next**.

#. In **Target sub-resource**, click the target resource type.

   - For the first private endpoint you create for each source network, set this to **dfs**.

   - For the second private endpoint you create for each source network, set this to **blob**.

#. In the **Virtual network** field, select your workspace VNet.

#. In the subnet field, it might auto-populate with the subnet for your private endpoints, but you may have to set it explicitly.  If you used the [template provided in this article](#template-vnet), this subnet is called `PE`.

   .. tip:: You cannot use one of the two workspace subnets that are used for basic <Databricks> workspace functionality, which are typically called `private-subnet` and `public-subnet`.

#. At the bottom of the page, click **Next**.

#. In the Private DNS integration form, this auto-populates to the right subscription and resource group that you previously selected. Change them if needed.

#. At the bottom of the page, click **Next**.

#. Add tags if desired.

#. At the bottom of the page, click **Next**.

#. Review the fields.

#. At the bottom of the page, click **Create**.

#. **If you are using default DNS (Azure DNS) and private DNS zones**, it is important to do the following steps to verify the private endpoint's private DNS zones are configured to connect to the correct VNet. If you are not using default DNS (Azure DNS) and private DNS zones, skip to the next numbered step.

   a. Go to your private endpoint in the portal.

   #. In the left navigation, click **DNS configuration**.

   #. Check that there is exactly one one network interface with the `FQDN` value of `<storage-account-name>.<dfs-or-blob>.core.windows.net`. Typically `<storage-account-name>` has the form `dbstorage<letters-and-numbers>`. For example the FQDN might look like `dbstorage7s5d6agf7sd5.dfs.core.windows.net`.

   #. Under the configuration name list, confirm there is exactly one row for a private DNS zone. If it's there, click on it. If it's not there, it's important that you add the private endpoint to your private DNS zone before proceeding to the next step.

   #. In the private DNS zone page, confirm that in the list of records in the DNS zone page contains an `A` record with the name of your storage account, which typically has the form `dbstorage<letters-and-numbers>`.

   #. In the left navigation of the private DNS zone, click **Virtual network links**.

   #. Confirm there is a row where the **Virtual network** column contains the name of your source VNet. If you are creating private endpoints from the classic compute plane, this must be the compute plane VNet. If you are create private endpoints for a Cloud Fetch client, that is the source VNet. This step is especially important for your configuration if you chose not to host your private endpoints directly in the source VNet, for example a hub and spoke model where all private endpoints for multiple workspaces are in a peered VNet.

      If your source VNet is not listed here, you must add a network link. Click **Add**. Provide a link name, select **I know the resource ID of virtual network**, and specify your VNet resource ID. Fill out the other fields and click **Create**. If you do not do this step correctly, the connection from the private endpoint fails.

#. If you just created a private endpoint with **Target sub-resource** field set to `dfs`, repeat the previous steps to create a private endpoint with **Target sub-resource** field set to `blob`. Always create two endpoints for every VNet source to connect to the storage. You don't need to wait for the first endpoint to fully deploy before you create the next endpoint.

## <a id="create-private-endpoints-cloud-fetch"></a> Step 4 (Optional): Configure private endpoints for Cloud Fetch client VNets

If you use Cloud Fetch for ODBC or JDBC, create private endpoints to the Azure storage account for <WDS> from any VNets of your Cloud Fetch clients.

For each source network for Cloud Fetch clients, create two private endpoints that use two different **Target sub-resource** values: `dfs` and `blob`. Refer to [_](#create-private-endpoints-main) for detailed steps. In those steps, for the **Virtual network** field when creating the private endpoint, be sure that you specify your source VNet for each Cloud Fetch client.

## <a id="endpoints-approvals"></a> Step 5: Confirm endpoint approvals

After you create all your private endpoints to the storage account, check if they are approved. They might auto-approve depending on various factors. However, in some cases you might need to approve them on the storage account.

#. Navigate to your workspace in the Azure portal. It is an Azure Databricks Service instance.

#. Next to the **Managed Resource Group** field, click the name of the managed resource group.

#. In the list of resources in the managed resource group, click the resource of type **Storage account** that has a name that begins with `dbstorage` followed by other letters and numbers.

#. In the left navigation, click **Networking**.

#. Click **Private endpoint connections**.

#. Check the **Connection state** to confirm they all say **Approved**. If any don't say **Approved**, select them and then click **Approve**.


## <a id="serverless"></a> Step 6 (Optional): Authorize serverless SQL warehouse connections

<!-- Databricks adds network rules to the storage account for supporting serverless SQL warehouses when you attach the NCC. Support for Private Link from serverless SQL requires a separate preview. -->

If you use serverless SQL warehouses, you must authorize serverless SQL warehouses to connect to your <WDS>. Doing so does _not_ authorize connections from other serverless compute resources such as Model Serving.

The main steps are creating a network connectivity configuration (NCC) object then attaching it to the workspace. After you do this, <Databricks> allows network access to the <WDS>> from serverless SQL warehouses and other serverless compute resources.

The steps to follow depends on your needs:

- **Access control using service endpoints from serverless SQL subnets**. If it's sufficient to limit access to storage from supported Azure networks from serverless SQL warehouses, follow instructions in [_](/security/network/serverless-network-security/serverless-firewall.md). Skip the steps that copy subnet IDs and create network rules on the storage account, as those are handled automatically for <WDS>.

- **Access control using Private Link (requires joining a separate preview)**. To make network traffic from serverless SQL warehouses use private endpoints to your workspace's <WDS>, follow instructions in [_](/security/network/serverless-network-security/serverless-private-link.md). After you do those steps, serverless SQL warehouses resource network traffic to <WDS> uses your private endpoints. You must request to join a **separate preview** to do these steps. Contact your <Databricks> account team.  <!-- Be aware that one step in the instructions require you to contact your <Databricks> account team for information to complete the steps . YES YES YES THIS IS WEIRD! THIS WAS A PM DECISION TO "HIDE" THE "YOU NEED TWO ENDPOINTS TO CONNECT TO ROOT STORAGE" DUE TO RESOURCE LIMITS -- SO YES IT'S WEIRD, WE ARE LINKING TO DOCS BUT THEN THOSE DOCS DON'T SAY THE FULL DEAL!!! -->


## <a id="validate"></a> Step 7: Validate the configuration

Validate that the Azure storage account for <WDS> is not publicly accessible in the Managed Resource Group by checking the storage account resource in the Managed Resource Group of your <Databricks> workspace.

Perform all the following tests:

#. Confirm that a notebook can generate a list of files in the DBFS root, which is one component of your <WDS>.

   a. If you do not yet have a cluster, click **Compute** and create a cluster. See [_](/compute/configure.md).

   #. Create a notebook. See [_](/notebooks/notebooks-manage.md).

   #. Paste the Python code `dbutils.fs.ls("/")` into the notebook.

   #. Click **Run All**..

   If it works correctly, this command outputs a list of files.

#. Run a job. See [_](/workflows/jobs/create-run-jobs.md)

#. In Databricks SQL, run a SQL query. See [_](/sql/user/sql-editor/index.md).

#. If you did the optional step to support serverless SQL warehouses, run a SQL query on a serverless SQL warehouse. See [_](/compute/sql-warehouse/serverless.md).

#. Upload a file to DBFS root. See [_](/ingestion/add-data/index.md)

#. If you use init scripts, test your init scripts on a cluster and confirm they work. See [_](/files/workspace-init-scripts.md).

#. If you use the Repos feature, clone a GitHub repo and test the new clone. See [_](/repos/repos-setup.md).

#. If you use MLFlow, try to save an MLFlow Model. See [_](/machine-learning/model-serving/index.md).


## Disable <FeatureName>

You can disable <FeatureName> on an existing workspace where it is enabled. Use the same process as mentioned above, but set the parameter Storage Account Firewall (`storageAccountFirewall` in the template) to `Disabled`. After you disable <FeatureName>, <Databricks> changes the network access on the Azure storage firewall to **All networks** and removes the Access Connector.

.. important:: When you disable <FeatureName>, you must set the **Workspace Catalog Enabled** field correctly based on whether your workspace uses a _Unity Catalog workspace catalog_, which if it exists is part of the <WDS>. To check if this applies to you, go to your workspace. In the left navigation, click **Catalogs**. Check if there is a catalog whose name matches your workspace name. If such a catalog exists, set **Workspace Catalog Enabled** to `true`. Otherwise, set it to `false`.


## <a id="template-workspace"></a> Required template for <FeatureName>

<!-- TEMPORARILY THIS IS STORED AT NON-OFFICIAL GITHUB REPO HERE
https://raw.githubusercontent.com/brucenelson6655/dbfs-fw/main/private-dbfs-universal.json
BUT WHEN IT TRANSITIONS TO A MORE PERMANENT PLACE, WE CAN REMOVE FROM THE DOCS AND JUST POINT TO ITS NEW HOME IN A LINK. THIS WAS COPIED Fri, Feb 23, 2024 1:06 PM -->


Copy the following ARM template to enable or disable <FeatureName>

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "workspaceName": {
      "type": "String",
      "metadata": {
        "description": "The name of the Azure Databricks workspace to update."
      }
    },
    "location": {
      "defaultValue": "[resourceGroup().location]",
      "type": "String",
      "metadata": {
        "description": "Location for all resources."
      }
    },
    "managedResourceGroupName": {
      "defaultValue": "[format('databricks-rg-{0}-{1}', parameters('workspaceName'), uniqueString(parameters('workspaceName'), resourceGroup().id))]",
      "type": "String",
      "metadata": {
        "description": "The Managed Resource GroupName of the workspace. Do not change unless using a custom managed resource group name."
      }
    },
    "storageAccountName": {
      "defaultValue": "[concat('dbstorage', uniqueString(resourceGroup().id, subscription().id))]",
      "type": "String",
      "metadata": {
        "description": "Workspace storage account name. Do not change unless using a custom storage account name."
      }
    },
    "workspaceVnetResourceId": {
      "defaultValue": "Required Resource ID of the workspace VNet",
      "type": "String",
      "metadata": {
        "description": "The Resource ID of the injected VNet for the workspace"
      }
    },
    "workspacePrivateSubnetName": {
      "defaultValue": "private-subnet",
      "type": "String",
      "metadata": {
        "description": "The private subnet name for the workspace"
      }
    },
    "workspacePublicSubnetName": {
      "defaultValue": "public-subnet",
      "type": "String",
      "metadata": {
        "description": "The public subnet name for the workspace"
      }
    },
    "accessConnectorName": {
      "defaultValue": "[format('{0}-access-connector', parameters('workspaceName'))]",
      "type": "String",
      "metadata": {
        "description": "The access connector to create for the workspace"
      }
    },
    "ManagedIdentityType": {
      "defaultValue": "SystemAssigned",
      "allowedValues": [
        "SystemAssigned",
        "UserAssigned",
        "SystemAssigned,UserAssigned"
      ],
      "type": "String",
      "metadata": {
        "description": "Access Connector Managed Identity Type"
      }
    },
    "userManagedIdentityResourceId": {
      "defaultValue": "Required For User Mananged Identity",
      "type": "String",
      "metadata": {
        "description": "The Resource Id of the User Managed Identity"
      }
    },
    "storageAccountFirewall": {
      "defaultValue": "Enabled",
      "allowedValues": [
        "Enabled",
        "Disabled"
      ],
      "type": "String",
      "metadata": {
        "description": "Enable or Disable firewall support for workspace default storage feature"
      }
    },
    "workspaceCatalogEnabled": {
      "defaultValue": false,
      "type": "Bool",
      "metadata": {
        "description": "Is UC workspace catalog enabled ?"
      }
    },
    "disablePublicIp": {
      "defaultValue": true,
      "type": "Bool",
      "metadata": {
        "description": "Specifies whether to deploy Azure Databricks workspace with secure cluster connectivity (SCC) enabled or not (No Public IP)."
      }
    },
    "publicNetworkAccess": {
      "defaultValue": "Enabled",
      "allowedValues": [
        "Enabled",
        "Disabled"
      ],
      "type": "String",
      "metadata": {
        "description": "Indicates whether public network access is allowed to the workspace with private endpoint - possible values are Enabled or Disabled."
      }
    },
    "requiredNsgRules": {
      "defaultValue": "AllRules",
      "allowedValues": [
        "AllRules",
        "NoAzureDatabricksRules"
      ],
      "type": "String",
      "metadata": {
        "description": "Indicates whether to retain or remove the AzureDatabricks outbound NSG rule - possible values are AllRules, NoAzureDatabricksRules (private link)."
      }
    },
    "storageDoubleEncryption": {
      "defaultValue": false,
      "type": "Bool",
      "metadata": {
        "description": "Is double encryption for managed storage enabled ?"
      }
    },
    "customerManagedKeysEnabled": {
      "defaultValue": false,
      "type": "Bool",
      "metadata": {
        "description": "Is CMK for managed services enabled ?"
      }
    },
    "CustomerManagedKeyType": {
      "defaultValue": "ManagedServicesCMK",
      "allowedValues": [
        "ManagedServicesCMK",
        "ManagedDisksCMK",
        "BothCMK"
      ],
      "type": "String",
      "metadata": {
        "description": "Selects the CMK types for this workspace, Managed Services and/or Disks, Workspace storage account is not enabled here"
      }
    },
    "ManagedSrvcKeyVaultUri": {
      "defaultValue": "Required for CMK for managed services only",
      "type": "String",
      "metadata": {
        "description": "The Key Vault URI"
      }
    },
    "ManagedSrvcKeyName": {
      "defaultValue": "Required for CMK for managed services only",
      "type": "String",
      "metadata": {
        "description": "The Key Name"
      }
    },
    "ManagedSrvcKeyVersion": {
      "defaultValue": "Required for CMK for managed services only",
      "type": "String",
      "metadata": {
        "description": "The Key Version"
      }
    },
    "ManagedDiskKeyVaultUri": {
      "defaultValue": "Required for CMK for managed disks only",
      "type": "String",
      "metadata": {
        "description": "The Key Vault URI"
      }
    },
    "ManagedDiskKeyName": {
      "defaultValue": "Required for CMK for managed disks only",
      "type": "String",
      "metadata": {
        "description": "The Key Name"
      }
    },
    "ManagedDiskKeyVersion": {
      "defaultValue": "Required for CMK for managed disks only",
      "type": "String",
      "metadata": {
        "description": "The Key Version"
      }
    },
    "ManagedDiskAutoRotation": {
      "type": "bool",
      "defaultValue": false,
      "allowedValues": [
        true,
        false
      ],
      "metadata": {
        "description": "Whether managed disk will pick up new key version automatically."
      }
    }
  },
  "variables": {
    "ApiVersion": "2024-02-01-preview",
    "workspaceSku": "premium",
    "systemAssignedObject": {
      "type": "[parameters('ManagedIdentityType')]"
    },
    "userAssignedObject": {
      "type": "[parameters('ManagedIdentityType')]",
      "userAssignedIdentities": {
        "[parameters('userManagedIdentityResourceId')]": {}
      }
    },
    "ConnectorSystemAssigned": {
      "id": "[resourceId('Microsoft.Databricks/accessConnectors', parameters('accessConnectorName'))]",
      "identityType": "[parameters('ManagedIdentityType')]"
    },
    "connectorUserAssigned": {
      "id": "[resourceId('Microsoft.Databricks/accessConnectors', parameters('accessConnectorName'))]",
      "identityType": "[parameters('ManagedIdentityType')]",
      "userAssignedIdentityId": "[parameters('userManagedIdentityResourceId')]"
    },
    "ManagedServicesCMK": {
      "managedServices": {
        "keySource": "Microsoft.Keyvault",
        "keyVaultProperties": {
          "keyVaultUri": "[parameters('ManagedSrvcKeyVaultUri')]",
          "keyName": "[parameters('ManagedSrvcKeyName')]",
          "keyVersion": "[parameters('ManagedSrvcKeyVersion')]"
        }
      }
    },
    "ManagedDisksCMK": {
      "managedDisk": {
        "keySource": "Microsoft.Keyvault",
        "keyVaultProperties": {
          "keyVaultUri": "[parameters('ManagedDiskKeyVaultUri')]",
          "keyName": "[parameters('ManagedDiskKeyName')]",
          "keyVersion": "[parameters('ManagedDiskKeyVersion')]"
        },
        "rotationToLatestKeyVersionEnabled": "[parameters('ManagedDiskAutoRotation')]"
      }
    },
    "BothCMK": {
      "managedServices": {
        "keySource": "Microsoft.Keyvault",
        "keyVaultProperties": {
          "keyVaultUri": "[parameters('ManagedSrvcKeyVaultUri')]",
          "keyName": "[parameters('ManagedSrvcKeyName')]",
          "keyVersion": "[parameters('ManagedSrvcKeyVersion')]"
        }
      },
      "managedDisk": {
        "keySource": "Microsoft.Keyvault",
        "keyVaultProperties": {
          "keyVaultUri": "[parameters('ManagedDiskKeyVaultUri')]",
          "keyName": "[parameters('ManagedDiskKeyName')]",
          "keyVersion": "[parameters('ManagedDiskKeyVersion')]"
        },
        "rotationToLatestKeyVersionEnabled": "[parameters('ManagedDiskAutoRotation')]"
      }
    }
  },
  "resources": [
    {
      "type": "Microsoft.Databricks/accessConnectors",
      "apiVersion": "2023-05-01",
      "name": "[parameters('accessConnectorName')]",
      "location": "[parameters('location')]",
      "identity": "[if(equals(parameters('ManagedIdentityType'),'SystemAssigned'),variables('systemAssignedObject'),variables('userAssignedObject'))]",
      "properties": {},
      "condition": "[or (and (equals(parameters('storageAccountFirewall'), 'Disabled'), parameters('workspaceCatalogEnabled')), equals(parameters('storageAccountFirewall'), 'Enabled'))]"
    },
    {
      "type": "Microsoft.Databricks/workspaces",
      "apiVersion": "[variables('ApiVersion')]",
      "name": "[parameters('workspaceName')]",
      "location": "[parameters('location')]",
      "dependsOn": [
        "[resourceId('Microsoft.Databricks/accessConnectors', parameters('accessConnectorName'))]"
      ],
      "sku": {
        "name": "[variables('workspaceSku')]"
      },
      "properties": {
        "managedResourceGroupId": "[subscriptionResourceId('Microsoft.Resources/resourceGroups', parameters('managedResourceGroupName'))]",
        "publicNetworkAccess": "[parameters('publicNetworkAccess')]",
        "requiredNsgRules": "[parameters('requiredNsgRules')]",
        "accessConnector": "[if(equals(parameters('ManagedIdentityType'),'SystemAssigned'),variables('ConnectorSystemAssigned'),variables('connectorUserAssigned'))]",
        "privateDbfsAccess": "[parameters('storageAccountFirewall')]",
        "parameters": {
          "customVirtualNetworkId": {
            "value": "[parameters('workspaceVnetResourceId')]"
          },
          "customPrivateSubnetName": {
            "value": "[parameters('workspacePrivateSubnetName')]"
          },
          "customPublicSubnetName": {
            "value": "[parameters('workspacePublicSubnetName')]"
          },
          "enableNoPublicIp": {
            "value": "[parameters('disablePublicIp')]"
          },
          "storageAccountName": {
            "value": "[parameters('storageAccountName')]"
          },
          "requireInfrastructureEncryption": {
            "value": "[parameters('storageDoubleEncryption')]"
          }
        }
      },
      "condition": "[or (and (equals(parameters('storageAccountFirewall'), 'Disabled'), parameters('workspaceCatalogEnabled'), not(parameters('customerManagedKeysEnabled'))), and (equals(parameters('storageAccountFirewall'), 'Enabled'), not(parameters('customerManagedKeysEnabled'))))]"
    },
    {
      "type": "Microsoft.Databricks/workspaces",
      "apiVersion": "[variables('ApiVersion')]",
      "name": "[parameters('workspaceName')]",
      "location": "[parameters('location')]",
      "sku": {
        "name": "[variables('workspaceSku')]"
      },
      "properties": {
        "managedResourceGroupId": "[subscriptionResourceId('Microsoft.Resources/resourceGroups', parameters('managedResourceGroupName'))]",
        "publicNetworkAccess": "[parameters('publicNetworkAccess')]",
        "requiredNsgRules": "[parameters('requiredNsgRules')]",
        "privateDbfsAccess": "Disabled",
        "parameters": {
          "customVirtualNetworkId": {
            "value": "[parameters('workspaceVnetResourceId')]"
          },
          "customPrivateSubnetName": {
            "value": "[parameters('workspacePrivateSubnetName')]"
          },
          "customPublicSubnetName": {
            "value": "[parameters('workspacePublicSubnetName')]"
          },
          "enableNoPublicIp": {
            "value": "[parameters('disablePublicIp')]"
          },
          "storageAccountName": {
            "value": "[parameters('storageAccountName')]"
          },
          "requireInfrastructureEncryption": {
            "value": "[parameters('storageDoubleEncryption')]"
          }
        }
      },
      "condition": "[and (equals(parameters('storageAccountFirewall'), 'Disabled'), not(parameters('workspaceCatalogEnabled')), not(parameters('customerManagedKeysEnabled'))) ]"
    },
    {
      "type": "Microsoft.Databricks/workspaces",
      "apiVersion": "[variables('ApiVersion')]",
      "name": "[parameters('workspaceName')]",
      "location": "[parameters('location')]",
      "dependsOn": [
        "[resourceId('Microsoft.Databricks/accessConnectors', parameters('accessConnectorName'))]"
      ],
      "sku": {
        "name": "[variables('workspaceSku')]"
      },
      "properties": {
        "managedResourceGroupId": "[subscriptionResourceId('Microsoft.Resources/resourceGroups', parameters('managedResourceGroupName'))]",
        "publicNetworkAccess": "[parameters('publicNetworkAccess')]",
        "requiredNsgRules": "[parameters('requiredNsgRules')]",
        "accessConnector": "[if(equals(parameters('ManagedIdentityType'),'SystemAssigned'),variables('ConnectorSystemAssigned'),variables('connectorUserAssigned'))]",
        "encryption": {
          "entities": "[variables(parameters('CustomerManagedKeyType'))]"
        },
        "privateDbfsAccess": "[parameters('storageAccountFirewall')]",
        "parameters": {
          "customVirtualNetworkId": {
            "value": "[parameters('workspaceVnetResourceId')]"
          },
          "customPrivateSubnetName": {
            "value": "[parameters('workspacePrivateSubnetName')]"
          },
          "customPublicSubnetName": {
            "value": "[parameters('workspacePublicSubnetName')]"
          },
          "enableNoPublicIp": {
            "value": "[parameters('disablePublicIp')]"
          },
          "storageAccountName": {
            "value": "[parameters('storageAccountName')]"
          },
          "requireInfrastructureEncryption": {
            "value": "[parameters('storageDoubleEncryption')]"
          }
        }
      },
      "condition": "[or ( and ( equals(parameters('storageAccountFirewall'), 'Disabled'), parameters('workspaceCatalogEnabled'), parameters('customerManagedKeysEnabled')), and (equals(parameters('storageAccountFirewall'), 'Enabled'), parameters('customerManagedKeysEnabled')))]"
    },
    {
      "type": "Microsoft.Databricks/workspaces",
      "apiVersion": "[variables('ApiVersion')]",
      "name": "[parameters('workspaceName')]",
      "location": "[parameters('location')]",
      "sku": {
        "name": "[variables('workspaceSku')]"
      },
      "properties": {
        "managedResourceGroupId": "[subscriptionResourceId('Microsoft.Resources/resourceGroups', parameters('managedResourceGroupName'))]",
        "publicNetworkAccess": "[parameters('publicNetworkAccess')]",
        "requiredNsgRules": "[parameters('requiredNsgRules')]",
        "privateDbfsAccess": "Disabled",
        "encryption": {
          "entities": "[variables(parameters('CustomerManagedKeyType'))]"
        },
        "parameters": {
          "customVirtualNetworkId": {
            "value": "[parameters('workspaceVnetResourceId')]"
          },
          "customPrivateSubnetName": {
            "value": "[parameters('workspacePrivateSubnetName')]"
          },
          "customPublicSubnetName": {
            "value": "[parameters('workspacePublicSubnetName')]"
          },
          "enableNoPublicIp": {
            "value": "[parameters('disablePublicIp')]"
          },
          "storageAccountName": {
            "value": "[parameters('storageAccountName')]"
          },
          "requireInfrastructureEncryption": {
            "value": "[parameters('storageDoubleEncryption')]"
          }
        }
      },
      "condition": "[and (equals(parameters('storageAccountFirewall'), 'Disabled'), not(parameters('workspaceCatalogEnabled')), parameters('customerManagedKeysEnabled'))]"
    }
  ]
}
```


## <a id="template-vnet"></a> Create a VNet suitable for initial testing

Every organization's requirements are different, and you may already have a VNet you need to use provided by your organization. For the full requirements or a customer-managed VNet, see [_](/security/network/classic/vnet-inject.md).

For initial testing, Databricks provides a template that just creates a customer-managed VNet for use with VNet injection, its subnets, its network security group. To apply the template, use Azure portal, CLI, or other approaches. The following procedure assumes use of the Azure portal.

#. In Azure portal, search for "Deploy a custom template" and select that item.

#. Click **Build your own template in the editor**.

#. Paste in the template provided below.

#. Click **Save**.

#. Review and edit any fields as desired. Set the resource group and region to match your workspace.

#. Click **Review and Create**, then **Create**.

Use this ARM template:

<!-- TEMPORARILY THIS IS PROVIDED HERE, IT NEEDS A PUBLIC HOME, NOT A PUBLIC PERSONAL REPO
FOR NOW GET THE LATEST AT:
https://github.com/brucenelson6655/dbfs-fw/blob/main/cusom-vnet.json
-->

```
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "workspaceName": {
      "type": "String",
      "metadata": {
        "description": "The name of the Azure Databricks workspace to update."
      }
    },
    "location": {
      "defaultValue": "[resourceGroup().location]",
      "type": "String",
      "metadata": {
        "description": "Location for all resources."
      }
    },
    "managedResourceGroupName": {
      "defaultValue": "[format('databricks-rg-{0}-{1}', parameters('workspaceName'), uniqueString(parameters('workspaceName'), resourceGroup().id))]",
      "type": "String",
      "metadata": {
        "description": "The Managed Resource GroupName of the workspace. Do not change unless using a custom managed resource group name."
      }
    },
    "storageAccountName": {
      "defaultValue": "[concat('dbstorage', uniqueString(resourceGroup().id, subscription().id))]",
      "type": "String",
      "metadata": {
        "description": "Workspace storage account name. Do not change unless using a custom storage account name."
      }
    },
    "workspaceVnetResourceId": {
      "defaultValue": "Required Resource ID of the workspace VNet",
      "type": "String",
      "metadata": {
        "description": "The Resource ID of the injected VNet for the workspace"
      }
    },
    "workspacePrivateSubnetName": {
      "defaultValue": "private-subnet",
      "type": "String",
      "metadata": {
        "description": "The private subnet name for the workspace"
      }
    },
    "workspacePublicSubnetName": {
      "defaultValue": "public-subnet",
      "type": "String",
      "metadata": {
        "description": "The public subnet name for the workspace"
      }
    },
    "accessConnectorName": {
      "defaultValue": "[format('{0}-access-connector', parameters('workspaceName'))]",
      "type": "String",
      "metadata": {
        "description": "The access connector to create for the workspace"
      }
    },
    "ManagedIdentityType": {
      "defaultValue": "SystemAssigned",
      "allowedValues": [
        "SystemAssigned",
        "UserAssigned",
        "SystemAssigned,UserAssigned"
      ],
      "type": "String",
      "metadata": {
        "description": "Access Connector Managed Identity Type"
      }
    },
    "userManagedIdentityResourceId": {
      "defaultValue": "Required For User Mananged Identity",
      "type": "String",
      "metadata": {
        "description": "The Resource Id of the User Managed Identity"
      }
    },
    "storageAccountFirewall": {
      "defaultValue": "Enabled",
      "allowedValues": [
        "Enabled",
        "Disabled"
      ],
      "type": "String",
      "metadata": {
        "description": "Enable or Disable firewall support for workspace default storage feature"
      }
    },
    "workspaceCatalogEnabled": {
      "defaultValue": false,
      "type": "Bool",
      "metadata": {
        "description": "Is UC workspace catalog enabled ?"
      }
    },
    "disablePublicIp": {
      "defaultValue": true,
      "type": "Bool",
      "metadata": {
        "description": "Specifies whether to deploy Azure Databricks workspace with secure cluster connectivity (SCC) enabled or not (No Public IP)."
      }
    },
    "publicNetworkAccess": {
      "defaultValue": "Enabled",
      "allowedValues": [
        "Enabled",
        "Disabled"
      ],
      "type": "String",
      "metadata": {
        "description": "Indicates whether public network access is allowed to the workspace with private endpoint - possible values are Enabled or Disabled."
      }
    },
    "requiredNsgRules": {
      "defaultValue": "AllRules",
      "allowedValues": [
        "AllRules",
        "NoAzureDatabricksRules"
      ],
      "type": "String",
      "metadata": {
        "description": "Indicates whether to retain or remove the AzureDatabricks outbound NSG rule - possible values are AllRules, NoAzureDatabricksRules (private link)."
      }
    },
    "storageDoubleEncryption": {
      "defaultValue": false,
      "type": "Bool",
      "metadata": {
        "description": "Is double encryption for managed storage enabled ?"
      }
    },
    "customerManagedKeysEnabled": {
      "defaultValue": false,
      "type": "Bool",
      "metadata": {
        "description": "Is CMK for managed services enabled ?"
      }
    },
    "CustomerManagedKeyType": {
      "defaultValue": "ManagedServicesCMK",
      "allowedValues": [
        "ManagedServicesCMK",
        "ManagedDisksCMK",
        "BothCMK"
      ],
      "type": "String",
      "metadata": {
        "description": "Selects the CMK types for this workspace, Managed Services and/or Disks, Workspace storage account is not enabled here"
      }
    },

    "ManagedSrvcKeyVaultKeyId": {
      "defaultValue": "https://kv-url/keys/keyname/version",
      "type": "String",
      "metadata": {
        "description": "The Key Vault Key ID"
      }
    },
    "ManagedDiskKeyVaultKeyId": {
      "defaultValue": "https://kv-url/keys/keyname/version",
      "type": "String",
      "metadata": {
        "description": "The Key Vault Key ID"
      }
    },
    "ManagedDiskAutoRotation": {
      "type": "bool",
      "defaultValue": false,
      "allowedValues": [
        true,
        false
      ],
      "metadata": {
        "description": "Whether managed disk will pick up new key version automatically."
      }
    }
  },
  "variables": {
    "ApiVersion": "2024-02-01-preview",
    "workspaceSku": "premium",
    "systemAssignedObject": {
      "type": "[parameters('ManagedIdentityType')]"
    },
    "userAssignedObject": {
      "type": "[parameters('ManagedIdentityType')]",
      "userAssignedIdentities": {
        "[parameters('userManagedIdentityResourceId')]": {}
      }
    },
    "ConnectorSystemAssigned": {
      "id": "[resourceId('Microsoft.Databricks/accessConnectors', parameters('accessConnectorName'))]",
      "identityType": "[parameters('ManagedIdentityType')]"
    },
    "connectorUserAssigned": {
      "id": "[resourceId('Microsoft.Databricks/accessConnectors', parameters('accessConnectorName'))]",
      "identityType": "[parameters('ManagedIdentityType')]",
      "userAssignedIdentityId": "[parameters('userManagedIdentityResourceId')]"
    },
    "managedSrvcFirst" : "[split(parameters('ManagedSrvcKeyVaultKeyId'),'/keys/')]",
    "managedSrvcSecond" : "[split(variables('managedSrvcFirst')[1],'/')]",
     "managedDiskFirst" : "[split(parameters('ManagedDiskKeyVaultKeyId'),'/keys/')]",
    "managedDiskSecond" : "[split(variables('managedDiskFirst')[1],'/')]",
    "ManagedServicesCMK": {
      "managedServices": {
        "keySource": "Microsoft.Keyvault",
        "keyVaultProperties": {
          "keyVaultUri": "[variables('managedSrvcFirst')[0]]",
          "keyName": "[variables('managedSrvcSecond')[0]]",
          "keyVersion": "[variables('managedSrvcSecond')[1]]"
        }
      }
    },
    "ManagedDisksCMK": {
      "managedDisk": {
        "keySource": "Microsoft.Keyvault",
        "keyVaultProperties": {
          "keyVaultUri": "[variables('managedDiskFirst')[0]]",
          "keyName": "[variables('managedDiskSecond')[0]]",
          "keyVersion": "[variables('managedDiskSecond')[1]]"
        },
        "rotationToLatestKeyVersionEnabled": "[parameters('ManagedDiskAutoRotation')]"
      }
    },
    "BothCMK": {
      "managedServices": {
        "keySource": "Microsoft.Keyvault",
        "keyVaultProperties": {
          "keyVaultUri": "[variables('managedSrvcFirst')[0]]",
          "keyName": "[variables('managedSrvcSecond')[0]]",
          "keyVersion": "[variables('managedSrvcSecond')[1]]"
        }
      },
      "managedDisk": {
        "keySource": "Microsoft.Keyvault",
        "keyVaultProperties": {
          "keyVaultUri": "[variables('managedDiskFirst')[0]]",
          "keyName": "[variables('managedDiskSecond')[0]]",
          "keyVersion": "[variables('managedDiskSecond')[1]]"
        },
        "rotationToLatestKeyVersionEnabled": "[parameters('ManagedDiskAutoRotation')]"
      }
    }
  },
  "resources": [
    {
      "type": "Microsoft.Databricks/accessConnectors",
      "apiVersion": "2023-05-01",
      "name": "[parameters('accessConnectorName')]",
      "location": "[parameters('location')]",
      "identity": "[if(equals(parameters('ManagedIdentityType'),'SystemAssigned'),variables('systemAssignedObject'),variables('userAssignedObject'))]",
      "properties": {},
      "condition": "[or (and (equals(parameters('storageAccountFirewall'), 'Disabled'), parameters('workspaceCatalogEnabled')), equals(parameters('storageAccountFirewall'), 'Enabled'))]"
    },
    {
      "type": "Microsoft.Databricks/workspaces",
      "apiVersion": "[variables('ApiVersion')]",
      "name": "[parameters('workspaceName')]",
      "location": "[parameters('location')]",
      "dependsOn": [
        "[resourceId('Microsoft.Databricks/accessConnectors', parameters('accessConnectorName'))]"
      ],
      "sku": {
        "name": "[variables('workspaceSku')]"
      },
      "properties": {
        "managedResourceGroupId": "[subscriptionResourceId('Microsoft.Resources/resourceGroups', parameters('managedResourceGroupName'))]",
        "publicNetworkAccess": "[parameters('publicNetworkAccess')]",
        "requiredNsgRules": "[parameters('requiredNsgRules')]",
        "accessConnector": "[if(equals(parameters('ManagedIdentityType'),'SystemAssigned'),variables('ConnectorSystemAssigned'),variables('connectorUserAssigned'))]",
        "defaultStorageFirewall": "[parameters('storageAccountFirewall')]",
        "parameters": {
          "customVirtualNetworkId": {
            "value": "[parameters('workspaceVnetResourceId')]"
          },
          "customPrivateSubnetName": {
            "value": "[parameters('workspacePrivateSubnetName')]"
          },
          "customPublicSubnetName": {
            "value": "[parameters('workspacePublicSubnetName')]"
          },
          "enableNoPublicIp": {
            "value": "[parameters('disablePublicIp')]"
          },
          "storageAccountName": {
            "value": "[parameters('storageAccountName')]"
          },
          "requireInfrastructureEncryption": {
            "value": "[parameters('storageDoubleEncryption')]"
          }
        }
      },
      "condition": "[or (and (equals(parameters('storageAccountFirewall'), 'Disabled'), parameters('workspaceCatalogEnabled'), not(parameters('customerManagedKeysEnabled'))), and (equals(parameters('storageAccountFirewall'), 'Enabled'), not(parameters('customerManagedKeysEnabled'))))]"
    },
    {
      "type": "Microsoft.Databricks/workspaces",
      "apiVersion": "[variables('ApiVersion')]",
      "name": "[parameters('workspaceName')]",
      "location": "[parameters('location')]",
      "sku": {
        "name": "[variables('workspaceSku')]"
      },
      "properties": {
        "managedResourceGroupId": "[subscriptionResourceId('Microsoft.Resources/resourceGroups', parameters('managedResourceGroupName'))]",
        "publicNetworkAccess": "[parameters('publicNetworkAccess')]",
        "requiredNsgRules": "[parameters('requiredNsgRules')]",
        "defaultStorageFirewall": "Disabled",
        "parameters": {
          "customVirtualNetworkId": {
            "value": "[parameters('workspaceVnetResourceId')]"
          },
          "customPrivateSubnetName": {
            "value": "[parameters('workspacePrivateSubnetName')]"
          },
          "customPublicSubnetName": {
            "value": "[parameters('workspacePublicSubnetName')]"
          },
          "enableNoPublicIp": {
            "value": "[parameters('disablePublicIp')]"
          },
          "storageAccountName": {
            "value": "[parameters('storageAccountName')]"
          },
          "requireInfrastructureEncryption": {
            "value": "[parameters('storageDoubleEncryption')]"
          }
        }
      },
      "condition": "[and (equals(parameters('storageAccountFirewall'), 'Disabled'), not(parameters('workspaceCatalogEnabled')), not(parameters('customerManagedKeysEnabled'))) ]"
    },
    {
      "type": "Microsoft.Databricks/workspaces",
      "apiVersion": "[variables('ApiVersion')]",
      "name": "[parameters('workspaceName')]",
      "location": "[parameters('location')]",
      "dependsOn": [
        "[resourceId('Microsoft.Databricks/accessConnectors', parameters('accessConnectorName'))]"
      ],
      "sku": {
        "name": "[variables('workspaceSku')]"
      },
      "properties": {
        "managedResourceGroupId": "[subscriptionResourceId('Microsoft.Resources/resourceGroups', parameters('managedResourceGroupName'))]",
        "publicNetworkAccess": "[parameters('publicNetworkAccess')]",
        "requiredNsgRules": "[parameters('requiredNsgRules')]",
        "accessConnector": "[if(equals(parameters('ManagedIdentityType'),'SystemAssigned'),variables('ConnectorSystemAssigned'),variables('connectorUserAssigned'))]",
        "encryption": {
          "entities": "[variables(parameters('CustomerManagedKeyType'))]"
        },
        "defaultStorageFirewall": "[parameters('storageAccountFirewall')]",
        "parameters": {
          "customVirtualNetworkId": {
            "value": "[parameters('workspaceVnetResourceId')]"
          },
          "customPrivateSubnetName": {
            "value": "[parameters('workspacePrivateSubnetName')]"
          },
          "customPublicSubnetName": {
            "value": "[parameters('workspacePublicSubnetName')]"
          },
          "enableNoPublicIp": {
            "value": "[parameters('disablePublicIp')]"
          },
          "storageAccountName": {
            "value": "[parameters('storageAccountName')]"
          },
          "requireInfrastructureEncryption": {
            "value": "[parameters('storageDoubleEncryption')]"
          }
        }
      },
      "condition": "[or ( and ( equals(parameters('storageAccountFirewall'), 'Disabled'), parameters('workspaceCatalogEnabled'), parameters('customerManagedKeysEnabled')), and (equals(parameters('storageAccountFirewall'), 'Enabled'), parameters('customerManagedKeysEnabled')))]"
    },
    {
      "type": "Microsoft.Databricks/workspaces",
      "apiVersion": "[variables('ApiVersion')]",
      "name": "[parameters('workspaceName')]",
      "location": "[parameters('location')]",
      "sku": {
        "name": "[variables('workspaceSku')]"
      },
      "properties": {
        "managedResourceGroupId": "[subscriptionResourceId('Microsoft.Resources/resourceGroups', parameters('managedResourceGroupName'))]",
        "publicNetworkAccess": "[parameters('publicNetworkAccess')]",
        "requiredNsgRules": "[parameters('requiredNsgRules')]",
        "defaultStorageFirewall": "Disabled",
        "encryption": {
          "entities": "[variables(parameters('CustomerManagedKeyType'))]"
        },
        "parameters": {
          "customVirtualNetworkId": {
            "value": "[parameters('workspaceVnetResourceId')]"
          },
          "customPrivateSubnetName": {
            "value": "[parameters('workspacePrivateSubnetName')]"
          },
          "customPublicSubnetName": {
            "value": "[parameters('workspacePublicSubnetName')]"
          },
          "enableNoPublicIp": {
            "value": "[parameters('disablePublicIp')]"
          },
          "storageAccountName": {
            "value": "[parameters('storageAccountName')]"
          },
          "requireInfrastructureEncryption": {
            "value": "[parameters('storageDoubleEncryption')]"
          }
        }
      },
      "condition": "[and (equals(parameters('storageAccountFirewall'), 'Disabled'), not(parameters('workspaceCatalogEnabled')), parameters('customerManagedKeysEnabled'))]"
    }
  ]
}
```