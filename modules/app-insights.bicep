@description('Azure region for Application Insights')
param location string

@description('Name of the Application Insights instance')
param appInsightsName string

@description('Name of the Log Analytics Workspace (auto-generated if not provided)')
param logAnalyticsWorkspaceName string = 'log-${appInsightsName}'

@description('Application type')
@allowed([
  'web'
  'other'
])
param applicationType string = 'web'

@description('Tags to apply to resources')
param tags object = {}

@description('Key Vault name to store secrets in')
param keyVaultName string

@description('Store secrets in Key Vault')
param storeSecretsInKeyVault bool = true

resource workspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 90
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: applicationType
  properties: {
    Application_Type: applicationType
    WorkspaceResourceId: workspace.id
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}


resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = if (storeSecretsInKeyVault) {
  name: keyVaultName
}


resource instrumentationKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (storeSecretsInKeyVault) {
  parent: keyVault
  name: 'ApplicationInsightsInstrumentationKey'
  properties: {
    value: appInsights.properties.InstrumentationKey
  }
}

resource connectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (storeSecretsInKeyVault) {
  parent: keyVault
  name: 'ApplicationInsightsConnectionString'
  properties: {
    value: appInsights.properties.ConnectionString
  }
}

@description('Application Insights resource ID')
output appInsightsId string = appInsights.id

@description('Application Insights name')
output appInsightsName string = appInsights.name

@description('Log Analytics Workspace resource ID')
output workspaceId string = workspace.id

@description('Log Analytics Workspace name')
output workspaceName string = workspace.name

@description('Key Vault secret name for instrumentation key')
output instrumentationKeySecretName string = 'ApplicationInsightsInstrumentationKey'

@description('Key Vault secret name for connection string')
output connectionStringSecretName string = 'ApplicationInsightsConnectionString'
