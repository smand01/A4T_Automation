targetScope = 'resourceGroup'

param environment string = 'Test'
param kvName string
param location string = 'westus'

param storageName string

param tags object = {
  Environment: environment
  ManagedBy: 'Bicep'
}

module keyVault './modules/keyvault.bicep' = {
  name: 'keyVault-deployment'
  params: {
    location: location
    keyVaultName: kvName
    sku: 'standard'
    environment: environment
    tags: tags
  }
}

output keyVaultId string = keyVault.outputs.keyVaultId
output keyVaultName string = keyVault.outputs.keyVaultName
output keyVaultUri string = keyVault.outputs.keyVaultUri

module storage './modules/storage.bicep' = {
  name: 'storage-deployment'
  params: {
    location: location
    storageAccountName: storageName
    sku: 'Standard_LRS'
    keyVaultName: keyVault.outputs.keyVaultName
    storeSecretsInKeyVault: true
    environment: environment
    tags: tags
  }
}

output storageAccountId string = storage.outputs.storageAccountId
output storageAccountName string = storage.outputs.storageAccountName
output storageBlobEndpoint string = storage.outputs.blobEndpoint
output storageTableEndpoint string = storage.outputs.tableEndpoint
output storageConnectionStringSecretName string = storage.outputs.connectionStringSecretName
output storagePrimaryKeySecretName string = storage.outputs.primaryKeySecretName

param searchServiceName string

module searchService './modules/search-service.bicep' = {
  name: 'searchService-deployment'
  params: {
    location: location
    searchServiceName: searchServiceName
    sku: 'standard'
    replicaCount: 1
    partitionCount: 1
    keyVaultName: keyVault.outputs.keyVaultName
    storeSecretsInKeyVault: true
    tags: tags
  }
}

output searchServiceId string = searchService.outputs.searchServiceId
output searchServiceName string = searchService.outputs.searchServiceName
output searchServiceEndpoint string = searchService.outputs.searchServiceEndpoint
output searchAdminKeySecretName string = searchService.outputs.adminKeySecretName
output searchQueryKeySecretName string = searchService.outputs.queryKeySecretName

param serviceBusName string

module serviceBus './modules/service-bus.bicep' = {
  name: 'serviceBus-deployment'
  params: {
    location: location
    serviceBusName: serviceBusName
    sku: 'Standard'
    keyVaultName: keyVault.outputs.keyVaultName
    storeSecretsInKeyVault: true
    tags: tags
  }
}

param appInsightsName string

module appInsights './modules/app-insights.bicep' = {
  name: 'appInsights-deployment'
  params: {
    location: location
    appInsightsName: appInsightsName
    logAnalyticsWorkspaceName: 'log-${appInsightsName}'  
    applicationType: 'web'
    keyVaultName: keyVault.outputs.keyVaultName
    storeSecretsInKeyVault: true
    tags: tags
  }
}

output appInsightsId string = appInsights.outputs.appInsightsId
output appInsightsName string = appInsights.outputs.appInsightsName
output appInsightsWorkspaceId string = appInsights.outputs.workspaceId
output appInsightsWorkspaceName string = appInsights.outputs.workspaceName
output appInsightsInstrumentationKeySecretName string = appInsights.outputs.instrumentationKeySecretName
output appInsightsConnectionStringSecretName string = appInsights.outputs.connectionStringSecretName

output serviceBusId string = serviceBus.outputs.serviceBusId
output serviceBusName string = serviceBus.outputs.serviceBusName
output serviceBusEndpoint string = serviceBus.outputs.serviceBusEndpoint
output serviceBusConnectionStringSecretName string = serviceBus.outputs.connectionStringSecretName

// param openAIName string
// param openAISubdomain string

// module openAI './modules/openai.bicep' = {
//   name: 'openAI-deployment'
//   params: {
//     location: location
//     openAIName: openAIName
//     customSubDomainName: openAISubdomain
//     sku: 'S0'
//     keyVaultName: keyVault.outputs.keyVaultName
//     storeSecretsInKeyVault: true
//     deployGPT41: false
//     deployGPT4o: false
//     deployGPT4oMini: true
//     deployTextEmbedding: true
//     tags: tags
//   }
// }

// output openAIId string = openAI.outputs.openAIId
// output openAIName string = openAI.outputs.openAIName
// output openAIEndpoint string = openAI.outputs.openAIEndpoint
// output openAIApiKeySecretName string = openAI.outputs.apiKeySecretName
// output openAIEndpointSecretName string = openAI.outputs.endpointSecretName
// output gpt41DeploymentName string = openAI.outputs.gpt41DeploymentName
// output gpt4oDeploymentName string = openAI.outputs.gpt4oDeploymentName
// output gpt4oMiniDeploymentName string = openAI.outputs.gpt4oMiniDeploymentName
// output textEmbeddingDeploymentName string = openAI.outputs.textEmbeddingDeploymentName

param appServicePlanName string = 'asp-${appServiceName}'
param appServiceName string

module appService './modules/app-service.bicep' = {
  name: 'appService-deployment'
  params: {
    location: location
    appServiceName: appServiceName
    appServicePlanName: appServicePlanName
    appServicePlanSku: 'S1'
    appServicePlanCapacity: 1
    netFrameworkVersion: 'v8.0'
    alwaysOn: true
    httpsOnly: true
    keyVaultName: keyVault.outputs.keyVaultName
    storeSecretsInKeyVault: true
    tags: tags
    appSettings: {
      ASPNETCORE_ENVIRONMENT: environment
    }
  }
}

output appServiceId string = appService.outputs.appServiceId
output appServiceName string = appService.outputs.appServiceName
output appServiceDefaultHostName string = appService.outputs.defaultHostName
output appServiceUrl string = appService.outputs.appServiceUrl
output appServicePrincipalId string = appService.outputs.principalId
output appServicePlanId string = appService.outputs.appServicePlanId
output appServicePlanName string = appService.outputs.appServicePlanName
output appServiceUrlSecretName string = appService.outputs.appServiceUrlSecretName
output appServiceNameSecretName string = appService.outputs.appServiceNameSecretName
