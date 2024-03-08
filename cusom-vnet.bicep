param networkSecurityGroups_template_nsg_name string = 'template-nsg'

@description('Location for all resources.')
param location string = resourceGroup().location
param virtualNetworks_template_vnet_name string = 'template-vnet'
param vnetAdressSpace string = '100.64.0.0/24'
param privateSubnetName string = 'private-subnet'
param privateSubnetCIDR string = '100.64.0.64/26'
param publicSubnetName string = 'public-subnet'
param publicSubnetCIDR string = '100.64.0.0/26'
param privateLinkSubnetName string = 'PE'
param privateLinkCIDR string = '100.64.0.224/27'

resource networkSecurityGroups_template_nsg_name_resource 'Microsoft.Network/networkSecurityGroups@2023-06-01' = {
  name: networkSecurityGroups_template_nsg_name
  location: location
  properties: {
    securityRules: [
      {
        name: 'Microsoft.Databricks-workspaces_UseOnly_databricks-worker-to-worker-inbound'
        properties: {
          description: 'Required for worker nodes communication within a cluster.'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'Microsoft.Databricks-workspaces_UseOnly_databricks-worker-to-databricks-webapp'
        properties: {
          description: 'Required for workers communication with Databricks Webapp.'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'AzureDatabricks'
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
        }
      }
      {
        name: 'Microsoft.Databricks-workspaces_UseOnly_databricks-worker-to-sql'
        properties: {
          description: 'Required for workers communication with Azure SQL services.'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3306'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'Sql'
          access: 'Allow'
          priority: 101
          direction: 'Outbound'
        }
      }
      {
        name: 'Microsoft.Databricks-workspaces_UseOnly_databricks-worker-to-storage'
        properties: {
          description: 'Required for workers communication with Azure Storage services.'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'Storage'
          access: 'Allow'
          priority: 102
          direction: 'Outbound'
        }
      }
      {
        name: 'Microsoft.Databricks-workspaces_UseOnly_databricks-worker-to-worker-outbound'
        properties: {
          description: 'Required for worker nodes communication within a cluster.'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 103
          direction: 'Outbound'
        }
      }
      {
        name: 'Microsoft.Databricks-workspaces_UseOnly_databricks-worker-to-eventhub'
        properties: {
          description: 'Required for worker communication with Azure Eventhub services.'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '9093'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'EventHub'
          access: 'Allow'
          priority: 104
          direction: 'Outbound'
        }
      }
    ]
  }
}

resource virtualNetworks_template_vnet_name_resource 'Microsoft.Network/virtualNetworks@2023-06-01' = {
  name: virtualNetworks_template_vnet_name
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [vnetAdressSpace]
    }
    encryption: {
      enabled: false
      enforcement: 'AllowUnencrypted'
    }
    subnets: [
      {
        name: privateLinkSubnetName
        id: virtualNetworks_template_vnet_name_privateLinkSubnet.id
        properties: {
          addressPrefixes: [privateLinkCIDR]
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
        type: 'Microsoft.Network/virtualNetworks/subnets'
      }
      {
        name: publicSubnetName
        id: virtualNetworks_template_vnet_name_publicSubnet.id
        properties: {
          addressPrefix: publicSubnetCIDR
          networkSecurityGroup: {
            id: networkSecurityGroups_template_nsg_name_resource.id
          }
          serviceEndpoints: []
          delegations: [
            {
              name: 'Microsoft.Databricks.workspaces'
              id: '${virtualNetworks_template_vnet_name_publicSubnet.id}/delegations/Microsoft.Databricks.workspaces'
              properties: {
                serviceName: 'Microsoft.Databricks/workspaces'
              }
              type: 'Microsoft.Network/virtualNetworks/subnets/delegations'
            }
          ]
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
        type: 'Microsoft.Network/virtualNetworks/subnets'
      }
      {
        name: privateSubnetName
        id: virtualNetworks_template_vnet_name_privateSubnet.id
        properties: {
          addressPrefix: privateSubnetCIDR
          networkSecurityGroup: {
            id: networkSecurityGroups_template_nsg_name_resource.id
          }
          serviceEndpoints: []
          delegations: [
            {
              name: 'Microsoft.Databricks.workspaces'
              id: '${virtualNetworks_template_vnet_name_privateSubnet.id}/delegations/Microsoft.Databricks.workspaces'
              properties: {
                serviceName: 'Microsoft.Databricks/workspaces'
              }
              type: 'Microsoft.Network/virtualNetworks/subnets/delegations'
            }
          ]
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
        type: 'Microsoft.Network/virtualNetworks/subnets'
      }
    ]
    virtualNetworkPeerings: []
    enableDdosProtection: false
  }
}

resource virtualNetworks_template_vnet_name_privateLinkSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-06-01' = {
  name: '${virtualNetworks_template_vnet_name}/${privateLinkSubnetName}'
  properties: {
    addressPrefixes: [privateLinkCIDR]
    delegations: []
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
  dependsOn: [virtualNetworks_template_vnet_name_resource]
}

resource virtualNetworks_template_vnet_name_privateSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-06-01' = {
  name: '${virtualNetworks_template_vnet_name}/${privateSubnetName}'
  properties: {
    addressPrefix: privateSubnetCIDR
    networkSecurityGroup: {
      id: networkSecurityGroups_template_nsg_name_resource.id
    }
    serviceEndpoints: []
    delegations: [
      {
        name: 'Microsoft.Databricks.workspaces'
        id: '${virtualNetworks_template_vnet_name_privateSubnet.id}/delegations/Microsoft.Databricks.workspaces'
        properties: {
          serviceName: 'Microsoft.Databricks/workspaces'
        }
        type: 'Microsoft.Network/virtualNetworks/subnets/delegations'
      }
    ]
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
  dependsOn: [virtualNetworks_template_vnet_name_resource]
}

resource virtualNetworks_template_vnet_name_publicSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-06-01' = {
  name: '${virtualNetworks_template_vnet_name}/${publicSubnetName}'
  properties: {
    addressPrefix: publicSubnetCIDR
    networkSecurityGroup: {
      id: networkSecurityGroups_template_nsg_name_resource.id
    }
    serviceEndpoints: []
    delegations: [
      {
        name: 'Microsoft.Databricks.workspaces'
        id: '${virtualNetworks_template_vnet_name_publicSubnet.id}/delegations/Microsoft.Databricks.workspaces'
        properties: {
          serviceName: 'Microsoft.Databricks/workspaces'
        }
        type: 'Microsoft.Network/virtualNetworks/subnets/delegations'
      }
    ]
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
  dependsOn: [virtualNetworks_template_vnet_name_resource]
}
