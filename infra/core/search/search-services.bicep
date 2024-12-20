metadata description = 'Creates an Azure AI Search instance.'
param name string
param location string = resourceGroup().location
param tags object = {}

param sku object = {
  name: 'standard'
}

param authOptions object = {}
param disableLocalAuth bool = false
param encryptionWithCmk object = {
  enforcement: 'Unspecified'
}
@allowed([
  'default'
  'highDensity'
])
param hostingMode string = 'default'
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'
param bypass string = 'AzureServices'
param ipRules array = []
param partitionCount int = 1
param replicaCount int = 1
@allowed([
  'disabled'
  'free'
  'standard'
])
param semanticSearch string = 'disabled'

param sharedPrivateLinkStorageAccounts array = []

var searchIdentityProvider = (sku.name == 'free') ? null : {
  type: 'SystemAssigned'
}

resource search 'Microsoft.Search/searchServices@2024-06-01-preview' = {
  name: name
  location: location
  tags: tags
  // The free tier does not support managed identity
  identity: searchIdentityProvider
  properties: {
    authOptions: disableLocalAuth ? null : authOptions
    disableLocalAuth: disableLocalAuth
    encryptionWithCmk: encryptionWithCmk
    hostingMode: hostingMode
    partitionCount: partitionCount
    publicNetworkAccess: toLower(publicNetworkAccess)
    networkRuleSet: {
      ipRules: ipRules
      bypass: bypass
    }
    replicaCount: replicaCount
    semanticSearch: semanticSearch
  }
  sku: sku

  resource sharedPrivateLinkResource 'sharedPrivateLinkResources@2023-11-01' = [for (resourceId, i) in sharedPrivateLinkStorageAccounts: {
    name: 'search-shared-private-link-${i}'
    properties: {
      groupId: 'blob'
      status: 'Approved'
      provisioningState: 'Succeeded'
      requestMessage: 'automatically created by the system'
      privateLinkResourceId: resourceId
    }
  }]
}

output id string = search.id
output endpoint string = 'https://${name}.search.windows.net/'
output name string = search.name
output principalId string = !empty(searchIdentityProvider) ? search.identity.principalId : ''
