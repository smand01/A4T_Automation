using './main.bicep'

param environment = 'dev'
param kvName = 'a4t-keyvault'
param location = 'westus'

param storageName = 'athenatest'

param searchServiceName = 'a4t-search-service'

param serviceBusName = 'a4t-service-bus'

param appInsightsName = 'a4t-appinsights'

// param openAIName = 'athena-openai-a4t'
// param openAISubdomain = 'athena-openai-a4t'

param appServiceName = 'a4t-web-app'
