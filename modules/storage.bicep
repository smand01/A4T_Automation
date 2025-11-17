@description('Azure region for the Storage Account')
param location string

@description('Name of the Storage Account (3-24 characters, lowercase, no hyphens)')
@minLength(3)
@maxLength(24)
param storageAccountName string

param environment string

@description('Storage Account SKU')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Standard_ZRS'
  'Premium_LRS'
  'Premium_ZRS'
])
param sku string = 'Standard_LRS'

@description('Tags to apply to the Storage Account')
param tags object = {
  AthenaEnviornment: environment
}

@description('Key Vault name to store secrets in')
param keyVaultName string

@description('Store secrets in Key Vault (set to false if Key Vault not ready yet)')
param storeSecretsInKeyVault bool = true

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: sku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: true
    allowSharedKeyAccess: true
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = if (storeSecretsInKeyVault) {
  name: keyVaultName
}

resource connectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (storeSecretsInKeyVault) {
  parent: keyVault
  name: 'StorageAccountConnectionString'
  properties: {
    value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${az.environment().suffixes.storage}'
  }
}

resource primaryKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (storeSecretsInKeyVault) {
  parent: keyVault
  name: 'StorageAccountKey'
  properties: {
    value: storageAccount.listKeys().keys[0].value
  }
}

resource storageNameSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (storeSecretsInKeyVault) {
  parent: keyVault
  name: 'StorageAccountName'
  properties: {
    value: storageAccount.name
  }
}

@description('Storage Account resource ID')
output storageAccountId string = storageAccount.id

@description('Storage Account name')
output storageAccountName string = storageAccount.name

@description('Blob endpoint')
output blobEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('Table endpoint')
output tableEndpoint string = storageAccount.properties.primaryEndpoints.table

@description('Key Vault secret name for connection string')
output connectionStringSecretName string = 'StorageAccountConnectionString'

@description('Key Vault secret name for primary key')
output primaryKeySecretName string = 'StorageAccountKey'
