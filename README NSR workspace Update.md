## Update existing workspace to Workspace Storage Firewall Rules (private DBFS)

11/1/2024 [Bruce Nelson](mailto:bruce.nelson@databricks.com)

**Step Operator**: Customer 

**Prework :**   
Existing workspaces for NoAzureServiceRules workspaces should already have private endpoints deployed for both blob and dfs on the workspace storage account (DBFS) as per the legacy DBFS no public access in eastus2-c2. 

Other workspaces in different regions / shards will need to ensure private endpoints are created per the MSFT documentation of this feature (see Follow the docs).

**Follow the docs :**   
Customer will follow the steps in the MSFT documentation : [Enable firewall support for your workspace storage account \- Azure Databricks | Microsoft Learn](https://learn.microsoft.com/en-us/azure/databricks/security/network/storage/firewall-support) using a different [ARM template](https://github.com/brucenelson6655/dbfs-fw/blob/main/private-dbfs-universal-nsr-ga.json) designed for NoAzureServiceRules.  

| Important : Before starting the upgrade process to private DBFS, ensure that all compute clusters have been stopped.  |
| :---- |

You can use the supplied ARM template to update the Azure Databricks workspace or you can also update your workspace using Terraform. See the [azurerm\_databricks\_workspace](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/databricks_workspace) Terraform provider.

**ARM template based upgrade :** 

1. In the Azure portal, search for and select Deploy a custom template.  
     
2. Click “Build your own template” in the editor.  
     
3. Download the custom ARM template from [this location](https://github.com/brucenelson6655/dbfs-fw/blob/main/private-dbfs-universal-nsr-ga.json) for updating firewall support for your workspace storage account or copy the template included in this doc and paste it in the editor.  
   

| IMPORTANT: Do not use the supplied ARM template in the Azure docs \!   |
| :---- |

   

4. Click Save.  
     
5. Review and edit fields. Use the same parameters that you used to create the workspace, such as subscription, region, workspace name, subnet names, resource ID of the existing VNet.  
   1. Make sure to copy the network, and CMK settings from your workspace config.   
   2. Ensure “**storageAccountFirewall**” is set to “**Enabled**”.  
   3. Ensure “**requiredNsgRule**s” is set to  “**NoAzureServiceRules**”

   

6. For a description for the fields, see [ARM template fields](https://learn.microsoft.com/en-us/azure/databricks/security/network/storage/firewall-support-arm-template#arm-template-fields).  
     
7. Click Review and Create, then Create.

**Terraform based upgrade :**   
 Go to the [azurerm doc page](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/databricks_workspace#default_storage_firewall_enabled) for details

1. Create code for  a databricks access connector for the workspace 

   

| resource "azurerm\_databricks\_access\_connector" "ac" {  name \= "access-connector-name\-ac"  resource\_group\_name \= resource\_group\_name  location            \= resource\_group\_location   identity {    type \= "SystemAssigned"  }   tags \= local.tags  } |
| :---- |

   

2. Add the access connector resource id and set the default\_storage\_firewall\_enabled flag to “true”

   

| resource "azurerm\_databricks\_workspace" "ws" {  name                             \= "${local.prefix}\-ws"  resource\_group\_name              \= azurerm\_resource\_group.rg.name  location                         \= azurerm\_resource\_group.rg.location  sku                              \= "premium"  access\_connector\_id              \=    databricks\_access\_connector\_id  default\_storage\_firewall\_enabled \= true  |
| :---- |

   

3. Perform your plan and apply to complete the upgrade. 

| *Note : The public network access on your workspace storage account is set Enabled from selected virtual networks and IP addresses and not to Disabled in order to support serverless compute resources without requiring private endpoints.*  |
| :---- |

---

### Custom Arm Template for NoAzureServiceRules workspaces: 
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
      "type": "string",
      "defaultValue": "NoAzureServiceRules",
      "allowedValues": [
        "AllRules",
        "NoAzureDatabricksRules",
        "NoAzureServiceRules"
      ],
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
    "ApiVersion": "2024-05-01",
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
      "properties": {}
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
        "privateLinkAssets": [
          "-"
        ],
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
      "condition": "[not(parameters('customerManagedKeysEnabled'))]"
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
        "privateLinkAssets": [
          "-"
        ],
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
      "condition": "[parameters('customerManagedKeysEnabled')]"
    }
  ]
}
```