@description('Azure region for the Service Bus')
param location string

@description('Name of the Service Bus Namespace')
param serviceBusName string

@description('Service Bus SKU')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param sku string = 'Standard'

@description('Tags to apply to the Service Bus')
param tags object = {}

@description('Key Vault name to store secrets in')
param keyVaultName string

@description('Store secrets in Key Vault')
param storeSecretsInKeyVault bool = true

resource serviceBus 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: serviceBusName
  location: location
  tags: tags
  sku: {
    name: sku
    tier: sku
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
}


resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = if (storeSecretsInKeyVault) {
  name: keyVaultName
}

resource connectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (storeSecretsInKeyVault) {
  parent: keyVault
  name: 'ServiceBusConnectionString'
  properties: {
    value: listKeys('${serviceBus.id}/authorizationRules/RootManageSharedAccessKey', '2022-10-01-preview').primaryConnectionString
  }
}

resource serviceBusNameSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (storeSecretsInKeyVault) {
  parent: keyVault
  name: 'ServiceBusNamespace'
  properties: {
    value: serviceBus.name
  }
}

@description('Service Bus resource ID')
output serviceBusId string = serviceBus.id

@description('Service Bus Namespace name')
output serviceBusName string = serviceBus.name

@description('Service Bus endpoint')
output serviceBusEndpoint string = 'https://${serviceBus.name}.servicebus.windows.net'

@description('Key Vault secret name for connection string')
output connectionStringSecretName string = 'ServiceBusConnectionString'
