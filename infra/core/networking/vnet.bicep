metadata description = 'Creates a virtual network with 3 subnets (for AI, Azure Bastion, App Service).'

@description('The location for the VNet')
param location string

@description('The name of the VNet')
param name string

@description('The tags for the VNet')
param tags object = {}

param hasCustomDnsServers bool = false

param addressRange string = '10.0.0.0/16'
param subnetPrefixLength int = 24

param apimSubnetExistingRouteTableName string
param appGatewayExistingRouteTableName string

var v4Info = parseCidr(addressRange)
var octets = split(v4Info.network, '.')
var incrementOctet = subnetPrefixLength <= 8 ? 0 : (subnetPrefixLength <= 16 ? 1 : (subnetPrefixLength <= 24 ? 2 : 3))

var backendSubnetAddressPrefix = cidrSubnet(addressRange, subnetPrefixLength, int(octets[incrementOctet]))
var appSubnetAddressPrefix = cidrSubnet(addressRange, subnetPrefixLength, int(octets[incrementOctet]) + 1)
var apimSubnetAddressPrefix = cidrSubnet(addressRange, subnetPrefixLength, int(octets[incrementOctet]) + 2)
var appGatewaySubnetAddressPrefix = cidrSubnet(addressRange, subnetPrefixLength, int(octets[incrementOctet]) + 3)

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: name
}

resource apimRouteTable 'Microsoft.Network/routeTables@2024-05-01' existing = if (!empty(apimSubnetExistingRouteTableName)) {
  name: apimSubnetExistingRouteTableName
}

resource apimRouteTableInternetRoute 'Microsoft.Network/routeTables/routes@2024-05-01' = if (!empty(apimSubnetExistingRouteTableName)) {
  parent: apimRouteTable
  name: 'internetRoute'
  properties: {
    addressPrefix: '0.0.0.0/0'
    nextHopType: 'Internet'
  }
}

resource apimRouteTableManagementRoute 'Microsoft.Network/routeTables/routes@2024-05-01' = if (!empty(apimSubnetExistingRouteTableName)) {
  parent: apimRouteTable
  name: 'managementRoute'
  properties: {
    addressPrefix: 'ApiManagement'
    nextHopType: 'Internet'
  }
}

resource appGatewayRouteTable 'Microsoft.Network/routeTables@2024-05-01' existing = if (!empty(apimSubnetExistingRouteTableName)) {
  name: appGatewayExistingRouteTableName
}

resource appGatewayRouteTableInternetRoute 'Microsoft.Network/routeTables/routes@2024-05-01' = if (!empty(apimSubnetExistingRouteTableName)) {
  parent: appGatewayRouteTable
  name: 'internetRoute'
  properties: {
    addressPrefix: '0.0.0.0/0'
    nextHopType: 'Internet'
  }
}

resource backendSubnetNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'backend-subnet-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'SSH'
        properties: {
          priority: 1000
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
    ]
  }
}

resource appNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'app-nsg'
  location: location
  tags: tags
}

resource apimNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
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

resource appGatewayNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'app-gtw-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'agw-in'
        properties: {
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          description: 'App Gateway inbound'
          priority: 100
          sourceAddressPrefix: 'GatewayManager'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '65200-65535'
        }
      }
      {
        name: 'https-in'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: [
            '80'
            '443'
          ]
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
          description: 'Allow HTTPS Inbound'
        }
      }
    ]
  }
}

resource backendSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: vnet
  name: 'backend-subnet'
  properties: {
    addressPrefix: backendSubnetAddressPrefix
    networkSecurityGroup: {
      id: backendSubnetNsg.id
    }
  }
}

resource appSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: vnet
  name: 'app-subnet'
  properties: {
    addressPrefix: appSubnetAddressPrefix
    networkSecurityGroup: {
      id: appNsg.id
    }
    serviceEndpoints: [
      {
        service: 'Microsoft.Storage'
      }
    ]
    delegations: [
      {
        name: 'app-delegation'
        properties: {
          serviceName: 'Microsoft.Web/serverFarms'
        }
      }
    ]
  }

  dependsOn: [
    backendSubnet
  ]
}

resource apimSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: vnet
  name: 'apim-subnet'
  properties: {
    addressPrefix: apimSubnetAddressPrefix
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
      {
        service: 'Microsoft.CognitiveServices'
      }
    ]
  }

  dependsOn: [
    appSubnet
  ]
}

resource appGatewaySubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: vnet
  name: 'app-gtw-subnet'
  properties: {
    addressPrefix: appGatewaySubnetAddressPrefix
    routeTable: {
      id: appGatewayRouteTable.id
    }
    networkSecurityGroup: {
      id: appGatewayNsg.id
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

  dependsOn: [
    apimSubnet
  ]
}

output appSubnetId string = appSubnet.id
output backendSubnetId string = backendSubnet.id
output apimSubnetId string = apimSubnet.id
output appGtwSubnetId string = appGatewaySubnet.id
output vnetName string = vnet.name
output dnsServers string[] = hasCustomDnsServers ? vnet.properties.dhcpOptions.dnsServers : []
