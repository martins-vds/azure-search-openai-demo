metadata description = 'Sets up private networking for all resources, using VNet, private endpoints, and DNS zones.'

@description('The name of the VNet to create')
param vnetName string

@description('The location to create the VNet and private endpoints')
param location string = resourceGroup().location

@description('The tags to apply to all resources')
param tags object = {}

@description('The name of an existing App Service Plan to connect to the VNet')
param appServicePlanName string

param usePrivateEndpoint bool = false

@allowed(['appservice', 'containerapps'])
param deploymentTarget string

resource appServicePlan 'Microsoft.Web/serverfarms@2022-03-01' existing = if (deploymentTarget == 'appservice') {
  name: appServicePlanName
}

resource apimRouteTable 'Microsoft.Network/routeTables@2024-01-01' = {
  name: 'apim-rt'
  location: location
  properties: {
    disableBgpRoutePropagation: false
    routes: [
      {
        name: 'internetRoute'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'Internet'
        }
      }
      {
        name: 'managementRoute'
        properties: {
          addressPrefix: 'ApiManagement'
          nextHopType: 'Internet'
        }
      }
    ]
  }
}

resource apimNsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: 'apim-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      // Rules for API Management as documented here: https://docs.microsoft.com/en-us/azure/api-management/api-management-using-with-vnet
      {
        name: 'Client_communication_to_API_Management'
        properties: {
          protocol: 'TCP'
          sourcePortRange: '*'
          priority: 110
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          direction: 'Inbound'
          destinationPortRanges: [
            '80'
            '443'
          ]
        }
      }
      {
        name: 'Management_endpoint_for_Azure_portal_and_PowerShell'
        properties: {
          destinationPortRange: '3443'
          protocol: 'TCP'
          sourcePortRange: '*'
          priority: 120
          sourceAddressPrefix: 'ApiManagement'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          direction: 'Inbound'
          destinationPortRanges: []
        }
      }
      {
        name: 'Dependency_on_Azure_Storage'
        properties: {
          destinationPortRange: '443'
          protocol: 'TCP'
          sourcePortRange: '*'
          priority: 130
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'Storage'
          access: 'Allow'
          direction: 'Outbound'
          destinationPortRanges: []
        }
      }
      {
        name: 'Microsoft_Entra_ID_Microsoft_Graph_and_Azure_Key_Vault_dependency'
        properties: {
          destinationPortRange: '443'
          protocol: 'TCP'
          sourcePortRange: '*'
          priority: 140
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'AzureActiveDirectory'
          access: 'Allow'
          direction: 'Outbound'
          destinationPortRanges: []
        }
      }
      {
        name: 'managed_connections_dependency'
        properties: {
          destinationPortRange: '443'
          protocol: 'TCP'
          sourcePortRange: '*'
          priority: 150
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'AzureConnectors'
          access: 'Allow'
          direction: 'Outbound'
          destinationPortRanges: []
        }
      }
      {
        name: 'Access_to_Azure_SQL_endpoints'
        properties: {
          destinationPortRange: '1433'
          protocol: 'TCP'
          sourcePortRange: '*'
          priority: 160
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'Sql'
          access: 'Allow'
          direction: 'Outbound'
          destinationPortRanges: []
        }
      }
      {
        name: 'Access_to_Azure_Key_Vault'
        properties: {
          destinationPortRange: '443'
          protocol: 'TCP'
          sourcePortRange: '*'
          priority: 170
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'AzureKeyVault'
          access: 'Allow'
          direction: 'Outbound'
          destinationPortRanges: []
        }
      }
      {
        name: 'Dependency_for_Log_to_Azure_Event_Hubs_policy_and_Azure_Monitor'
        properties: {
          protocol: 'TCP'
          sourcePortRange: '*'
          priority: 180
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'EventHub'
          access: 'Allow'
          direction: 'Outbound'
          destinationPortRanges: [
            '5671'
            '5672'
            '443'
          ]
        }
      }
      {
        name: 'Dependency_on_Azure_File_Share_for_GIT'
        properties: {
          destinationPortRange: '445'
          protocol: 'TCP'
          sourcePortRange: '*'
          priority: 190
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'Storage'
          access: 'Allow'
          direction: 'Outbound'
          destinationPortRanges: []
        }
      }
      {
        name: 'Publish_Diagnostics_Logs_and_Metrics_Resource_Health_and_Application_Insights'
        properties: {
          protocol: 'TCP'
          sourcePortRange: '*'
          priority: 200
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'AzureMonitor'
          access: 'Allow'
          direction: 'Outbound'
          destinationPortRanges: [
            '1886'
            '443'
          ]
        }
      }
      {
        name: 'Access_external_Azure_Cache_for_Redis_service_for_caching_policies_inbound'
        properties: {
          destinationPortRange: '6380'
          protocol: 'TCP'
          sourcePortRange: '*'
          priority: 210
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          direction: 'Inbound'
          destinationPortRanges: []
        }
      }
      {
        name: 'Access_external_Azure_Cache_for_Redis_service_for_caching_policies_outbound'
        properties: {
          destinationPortRange: '6380'
          protocol: 'TCP'
          sourcePortRange: '*'
          priority: 220
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          direction: 'Outbound'
          destinationPortRanges: []
        }
      }
      {
        name: 'Access_internal_Azure_Cache_for_Redis_service_for_caching_policies_inbound'
        properties: {
          destinationPortRange: '6381 - 6383'
          protocol: 'TCP'
          sourcePortRange: '*'
          priority: 230
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          direction: 'Inbound'
          destinationPortRanges: []
        }
      }
      {
        name: 'Access_internal_Azure_Cache_for_Redis_service_for_caching_policies_outbound'
        properties: {
          destinationPortRange: '6381 - 6383'
          protocol: 'TCP'
          sourcePortRange: '*'
          priority: 240
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          direction: 'Outbound'
          destinationPortRanges: []
        }
      }
      {
        name: 'Sync_Counters_for_Rate_Limit_policies_between_machines_Inbound'
        properties: {
          destinationPortRange: '4290'
          protocol: 'UDP'
          sourcePortRange: '*'
          priority: 250
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          direction: 'Inbound'
          destinationPortRanges: []
        }
      }
      {
        name: 'Sync_Counters_for_Rate_Limit_policies_between_machines_Outbound'
        properties: {
          destinationPortRange: '4290'
          protocol: 'UDP'
          sourcePortRange: '*'
          priority: 260
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          direction: 'Outbound'
          destinationPortRanges: []
        }
      }
      {
        name: 'Azure_Infrastructure_Load_Balancer'
        properties: {
          destinationPortRange: '6390'
          protocol: 'TCP'
          sourcePortRange: '*'
          priority: 270
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          direction: 'Inbound'
          destinationPortRanges: []
        }
      }
      {
        name: 'Azure_Traffic_Manager_routing_for_multi_region_deployment'
        properties: {
          destinationPortRange: '443'
          protocol: 'TCP'
          sourcePortRange: '*'
          priority: 280
          sourceAddressPrefix: 'AzureTrafficManager'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          direction: 'Inbound'
          destinationPortRanges: []
        }
      }
      {
        name: 'Monitoring_of_individual_machine_health'
        properties: {
          destinationPortRange: '6391'
          protocol: 'TCP'
          sourcePortRange: '*'
          priority: 290
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          direction: 'Inbound'
          destinationPortRanges: []
        }
      }
    ]
  }
}

module vnet './core/networking/vnet.bicep' = if (usePrivateEndpoint) {
  name: 'vnet'
  params: {
    name: vnetName
    location: location
    tags: tags
    subnets: [
      {
        name: 'backend-subnet'
        properties: {
          addressPrefix: '10.0.1.0/24'
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: '10.0.2.0/24'
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'app-int-subnet'
        properties: {
          addressPrefix: '10.0.3.0/24'
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
            }
          ]
          delegations: [
            {
              id: appServicePlan.id
              name: appServicePlan.name
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
      {
        name: 'apim-subnet'
        properties: {
          addressPrefix: '10.0.4.0/24'
          routeTable: {
            id: apimRouteTable.id
          }
          networkSecurityGroup: {
            id: apimNsg.id
          }
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
            }
            {
              service: 'Microsoft.Sql'
            }
            {
              service: 'Microsoft.EventHub'
            }
            {
              service: 'Microsoft.ServiceBus'
            }
            {
              service: 'Microsoft.KeyVault'
            }
            {
              service: 'Microsoft.AzureActiveDirectory'
            }
          ]
        }
      }
      {
        name: 'app-gtw-subnet'
        properties: {
          addressPrefix: '10.0.5.0/24'
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
            }
            {
              service: 'Microsoft.Sql'
            }
            {
              service: 'Microsoft.EventHub'
            }
            {
              service: 'Microsoft.ServiceBus'
            }
            {
              service: 'Microsoft.KeyVault'
            }
            {
              service: 'Microsoft.AzureActiveDirectory'
            }
          ]
        }
      }
    ]
  }
}

output appSubnetId string = usePrivateEndpoint ? vnet.outputs.vnetSubnets[2].id : ''
output backendSubnetId string = usePrivateEndpoint ? vnet.outputs.vnetSubnets[0].id : ''
output apimSubnetId string = usePrivateEndpoint ? vnet.outputs.vnetSubnets[3].id : ''
output appGtwSubnetId string = usePrivateEndpoint ? vnet.outputs.vnetSubnets[4].id : ''
output vnetName string = usePrivateEndpoint ? vnet.outputs.name : ''
