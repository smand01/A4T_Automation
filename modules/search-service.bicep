@description('Azure region for the Search Service')
param location string

@description('Name of the Search Service (2-60 characters)')
@minLength(2)
@maxLength(60)
param searchServiceName string

@description('Search Service SKU')
@allowed([
  'free'
  'basic'
  'standard'
  'standard2'
  'standard3'
  'storage_optimized_l1'
  'storage_optimized_l2'
])
param sku string = 'standard'

@description('Number of replicas (1-12)')
@minValue(1)
@maxValue(12)
param replicaCount int = 1

@description('Number of partitions (1, 2, 3, 4, 6, or 12)')
@allowed([
  1
  2
  3
  4
  6
  12
])
param partitionCount int = 1

@description('Hosting mode')
@allowed([
  'default'
  'highDensity'
])
param hostingMode string = 'default'

@description('Tags to apply to the Search Service')
param tags object = {}

@description('Key Vault name to store secrets in')
param keyVaultName string

@description('Store secrets in Key Vault')
param storeSecretsInKeyVault bool = true

resource searchService 'Microsoft.Search/searchServices@2023-11-01' = {
  name: searchServiceName
  location: location
  tags: tags
  sku: {
    name: sku
  }
  properties: {
    replicaCount: replicaCount
    partitionCount: partitionCount
    hostingMode: hostingMode
    publicNetworkAccess: 'enabled'
    networkRuleSet: {
      ipRules: []
    }
    disableLocalAuth: false
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = if (storeSecretsInKeyVault) {
  name: keyVaultName
}


resource adminKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (storeSecretsInKeyVault) {
  parent: keyVault
  name: 'SearchServiceAdminKey'
  properties: {
    value: searchService.listAdminKeys().primaryKey
  }
}

resource queryKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (storeSecretsInKeyVault) {
  parent: keyVault
  name: 'SearchServiceQueryKey'
  properties: {
    value: searchService.listQueryKeys().value[0].key
  }
}

resource searchNameSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (storeSecretsInKeyVault) {
  parent: keyVault
  name: 'SearchServiceName'
  properties: {
    value: searchService.name
  }
}

resource searchEndpointSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (storeSecretsInKeyVault) {
  parent: keyVault
  name: 'SearchServiceEndpoint'
  properties: {
    value: 'https://${searchService.name}.search.windows.net'
  }
}

@description('Search Service resource ID')
output searchServiceId string = searchService.id

@description('Search Service name')
output searchServiceName string = searchService.name

@description('Search Service endpoint')
output searchServiceEndpoint string = 'https://${searchService.name}.search.windows.net'

@description('Key Vault secret name for admin key')
output adminKeySecretName string = 'SearchServiceAdminKey'

@description('Key Vault secret name for query key')
output queryKeySecretName string = 'SearchServiceQueryKey'
