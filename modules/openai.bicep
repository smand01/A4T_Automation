// modules/openai.bicep

@description('Azure region for OpenAI')
param location string

@description('Name of the OpenAI account')
param openAIName string

@description('Custom subdomain name for OpenAI endpoint')
param customSubDomainName string

@description('OpenAI SKU')
@allowed([
  'S0'
])
param sku string = 'S0'

@description('Tags to apply to OpenAI')
param tags object = {}

@description('Key Vault name to store secrets in')
param keyVaultName string

@description('Store secrets in Key Vault')
param storeSecretsInKeyVault bool = true

@description('Deploy GPT-4.1 model')
param deployGPT41 bool = false

@description('Deploy GPT-4o model')
param deployGPT4o bool = false

@description('Deploy GPT-4o-mini model')
param deployGPT4oMini bool = false

@description('Deploy text-embedding-ada-002 model')
param deployTextEmbedding bool = true

resource openAI 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: openAIName
  location: location
  tags: tags
  sku: {
    name: sku
  }
  kind: 'OpenAI'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customSubDomainName: customSubDomainName
    publicNetworkAccess: 'Enabled'
  }
}

resource gpt41Deployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = if (deployGPT41) {
  parent: openAI
  name: 'gpt-4.1'
  sku: {
    name: 'GlobalStandard'
    capacity: 50
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4.1'
      version: '2025-04-14'
    }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
    currentCapacity: 50
    raiPolicyName: 'Microsoft.DefaultV2'
  }
}

resource gpt4oDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = if (deployGPT4o) {
  parent: openAI
  name: 'gpt-4o'
  sku: {
    name: 'GlobalStandard'
    capacity: 50
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4o'
      version: '2024-05-13'
    }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
    currentCapacity: 50
    raiPolicyName: 'Microsoft.DefaultV2'
  }
}

resource gpt4oMiniDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = if (deployGPT4oMini) {
  parent: openAI
  name: 'gpt-4o-mini-model'
  sku: {
    name: 'GlobalStandard'
    capacity: 202
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4o-mini'
      version: '2024-07-18'
    }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
    currentCapacity: 202
    raiPolicyName: 'Microsoft.DefaultV2'
  }
}

resource textEmbeddingDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = if (deployTextEmbedding) {
  parent: openAI
  name: 'text-embedding-ada-002'
  sku: {
    name: 'Standard'
    capacity: 120
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'text-embedding-ada-002'
      version: '2'
    }
    versionUpgradeOption: 'NoAutoUpgrade'
    currentCapacity: 120
    raiPolicyName: 'Microsoft.DefaultV2'
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = if (storeSecretsInKeyVault) {
  name: keyVaultName
}

resource apiKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (storeSecretsInKeyVault) {
  parent: keyVault
  name: 'AzureOpenAIApiKey'
  properties: {
    value: openAI.listKeys().key1
  }
}

resource endpointSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (storeSecretsInKeyVault) {
  parent: keyVault
  name: 'AzureOpenAIEndpoint'
  properties: {
    value: openAI.properties.endpoint
  }
}

@description('OpenAI resource ID')
output openAIId string = openAI.id

@description('OpenAI account name')
output openAIName string = openAI.name

@description('OpenAI endpoint (non-sensitive)')
output openAIEndpoint string = openAI.properties.endpoint

@description('Key Vault secret name for API key')
output apiKeySecretName string = 'AzureOpenAIApiKey'

@description('Key Vault secret name for endpoint')
output endpointSecretName string = 'AzureOpenAIEndpoint'

@description('GPT-4.1 deployment name')
output gpt41DeploymentName string = deployGPT41 ? 'gpt-4.1' : ''

@description('GPT-4o deployment name')
output gpt4oDeploymentName string = deployGPT4o ? 'gpt-4o' : ''

@description('GPT-4o-mini deployment name')
output gpt4oMiniDeploymentName string = deployGPT4oMini ? 'gpt-4o-mini-model' : ''

@description('Text embedding deployment name')
output textEmbeddingDeploymentName string = deployTextEmbedding ? 'text-embedding-ada-002' : ''
