// modules/app-service.bicep

@description('Azure region for App Service')
param location string

@description('Name of the App Service')
param appServiceName string

@description('Name of the App Service Plan')
param appServicePlanName string

@description('App Service Plan SKU')
@allowed([
  'B1'
  'B2'
  'B3'
  'S1'
  'S2'
  'S3'
  'P1v2'
  'P2v2'
  'P3v2'
  'P1v3'
  'P2v3'
  'P3v3'
])
param appServicePlanSku string = 'S1'

@description('App Service Plan capacity')
@minValue(1)
@maxValue(10)
param appServicePlanCapacity int = 1

@description('.NET Core version for Windows (e.g., v8.0)')
param netFrameworkVersion string = 'v8.0'

@description('Always On setting')
param alwaysOn bool = true

@description('HTTPS only')
param httpsOnly bool = true

@description('Minimum TLS version')
@allowed([
  '1.0'
  '1.1'
  '1.2'
  '1.3'
])
param minTlsVersion string = '1.2'

@description('FTPS state')
@allowed([
  'AllAllowed'
  'FtpsOnly'
  'Disabled'
])
param ftpsState string = 'Disabled'

@description('Tags to apply to App Service')
param tags object = {}

@description('Key Vault name to store secrets in')
param keyVaultName string

@description('Store App Service URL in Key Vault')
param storeSecretsInKeyVault bool = true

@description('App Settings (can include Key Vault references)')
param appSettings object = {}

resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: appServicePlanSku
    capacity: appServicePlanCapacity
  }
  kind: ''
  properties: {
    reserved: false
  }
}

resource appService 'Microsoft.Web/sites@2023-01-01' = {
  name: appServiceName
  location: location
  tags: tags
  kind: 'app'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: httpsOnly
    siteConfig: {
      netFrameworkVersion: netFrameworkVersion
      alwaysOn: alwaysOn
      minTlsVersion: minTlsVersion
      ftpsState: ftpsState
      http20Enabled: true
      appSettings: [for setting in items(appSettings): {
        name: setting.key
        value: setting.value
      }]
    }
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = if (storeSecretsInKeyVault) {
  name: keyVaultName
}

resource appServiceUrlSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (storeSecretsInKeyVault) {
  parent: keyVault
  name: 'AppServiceUrl'
  properties: {
    value: 'https://${appService.properties.defaultHostName}'
  }
}

resource appServiceNameSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (storeSecretsInKeyVault) {
  parent: keyVault
  name: 'AppServiceName'
  properties: {
    value: appService.name
  }
}

@description('App Service resource ID')
output appServiceId string = appService.id

@description('App Service name')
output appServiceName string = appService.name

@description('App Service default hostname')
output defaultHostName string = appService.properties.defaultHostName

@description('App Service URL')
output appServiceUrl string = 'https://${appService.properties.defaultHostName}'

@description('App Service managed identity principal ID')
output principalId string = appService.identity.principalId

@description('App Service Plan resource ID')
output appServicePlanId string = appServicePlan.id

@description('App Service Plan name')
output appServicePlanName string = appServicePlan.name

@description('Key Vault secret name for App Service URL')
output appServiceUrlSecretName string = 'AppServiceUrl'

@description('Key Vault secret name for App Service name')
output appServiceNameSecretName string = 'AppServiceName'
