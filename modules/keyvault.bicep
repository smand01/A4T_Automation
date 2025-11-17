@description('Azure region for the Key Vault')
param location string

@description('Name of the Key Vault (3-24 characters)')
@minLength(3)
@maxLength(24)
param keyVaultName string

param environment string

@description('Key Vault SKU')
@allowed([
  'standard'
  'premium'
])
param sku string = 'standard'

@description('Tags to apply to the Key Vault')
param tags object = {
  AthenaEnviornment: environment
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: sku
    }
    tenantId: subscription().tenantId
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    enabledForDeployment: false
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: false
    enableRbacAuthorization: true
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

@description('Key Vault resource ID')
output keyVaultId string = keyVault.id

@description('Key Vault name')
output keyVaultName string = keyVault.name

@description('Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri
