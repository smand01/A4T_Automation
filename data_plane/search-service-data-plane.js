const {
  SearchIndexClient,
  SearchIndexerClient,
  AzureKeyCredential,
} = require('@azure/search-documents');
const { DefaultAzureCredential } = require('@azure/identity');
const { SecretClient } = require('@azure/keyvault-secrets');

require('dotenv').config('../.env');

const SOURCE_CONFIG = {
  endpoint: 'https://athena-beta-search-service.search.windows.net',
  serviceName: 'athena-beta-search-service',
};

const TARGET_CONFIG = {
  endpoint: 'https://a4t-search-service.search.windows.net',
  serviceName: 'a4t-search-service',
};

const KEYVAULT_CONFIG = {
  vaultUrl: 'https://a4t-keyvault.vault.azure.net/',
  targetSearchKeySecret: 'SearchServiceAdminKey',
  storageConnectionStringSecret: 'StorageAccountConnectionString',
};

const credential = new DefaultAzureCredential();

const keyVaultClient = new SecretClient(KEYVAULT_CONFIG.vaultUrl, credential);

let sourceSearchKey = null;
let targetSearchKey = null;
let storageConnectionString = null;
let sourceIndexClient = null;
let targetIndexClient = null;
let sourceIndexerClient = null;
let targetIndexerClient = null;

async function initializeSearchClients() {
  if (
    sourceIndexClient &&
    targetIndexClient &&
    sourceIndexerClient &&
    targetIndexerClient
  ) {
    return;
  }

  try {
    sourceSearchKey = process.env.SOURCE_SEARCH_SERVICE_KEY;
    if (!sourceSearchKey) {
      throw new Error(
        'SOURCE_SEARCH_SERVICE_KEY environment variable is not set'
      );
    }
    console.log('✓ Retrieved source search key from environment variable');

    console.log(
      `Retrieving '${KEYVAULT_CONFIG.targetSearchKeySecret}' from Key Vault...`
    );
    const targetKeySecret = await keyVaultClient.getSecret(
      KEYVAULT_CONFIG.targetSearchKeySecret
    );
    targetSearchKey = targetKeySecret.value;
    console.log('✓ Retrieved target search admin key from Key Vault');

    console.log(
      `Retrieving '${KEYVAULT_CONFIG.storageConnectionStringSecret}' from Key Vault...`
    );
    const storageSecret = await keyVaultClient.getSecret(
      KEYVAULT_CONFIG.storageConnectionStringSecret
    );
    storageConnectionString = storageSecret.value;
    console.log('✓ Retrieved storage account connection string from Key Vault');

    const sourceKeyCredential = new AzureKeyCredential(sourceSearchKey);
    const targetKeyCredential = new AzureKeyCredential(targetSearchKey);

    sourceIndexClient = new SearchIndexClient(
      SOURCE_CONFIG.endpoint,
      sourceKeyCredential
    );

    sourceIndexerClient = new SearchIndexerClient(
      SOURCE_CONFIG.endpoint,
      sourceKeyCredential
    );

    targetIndexClient = new SearchIndexClient(
      TARGET_CONFIG.endpoint,
      targetKeyCredential
    );

    targetIndexerClient = new SearchIndexerClient(
      TARGET_CONFIG.endpoint,
      targetKeyCredential
    );

    console.log('✓ Search clients initialized successfully\n');
  } catch (error) {
    console.error('Error initializing search clients:', error.message);
    throw error;
  }
}

function getStorageConnectionString() {
  if (!storageConnectionString) {
    throw new Error(
      'Storage connection string not initialized. Call initializeSearchClients first.'
    );
  }
  return storageConnectionString;
}

function cleanReadOnlyProperties(obj) {
  const cleaned = { ...obj };

  delete cleaned['@odata.etag'];
  delete cleaned['@odata.context'];

  return cleaned;
}

function deepCleanDataSourceProperties(obj) {
  if (!obj) return obj;
  
  const cleaned = { ...obj };
  
  if (cleaned.parameters && cleaned.parameters.configuration) {
    delete cleaned.parameters.configuration.queryTimeout;
  }
  
  return cleaned;
}

function updateDataSourceConnectionString(dataSource) {
  const newConnectionString = getStorageConnectionString();

  dataSource.connectionString = newConnectionString;

  console.log(
    `  Updated connection string for data source: ${dataSource.name}`
  );
}

async function migrateDataSources() {
  console.log('\n=== Migrating Data Sources ===');

  try {
    const dataSources = await sourceIndexerClient.listDataSourceConnections();

    console.log(`Found ${dataSources.length} data source(s)`);

    for (const dataSource of dataSources) {
      console.log(`Processing data source: ${dataSource.name}`);

      let cleanedDataSource = cleanReadOnlyProperties(dataSource);

      updateDataSourceConnectionString(cleanedDataSource);

      try {
        await targetIndexerClient.createOrUpdateDataSourceConnection(
          cleanedDataSource
        );
        console.log(`✓ Created data source: ${dataSource.name}`);
      } catch (error) {
        throw error;
      }
    }
  } catch (error) {
    console.error('Error migrating data sources:', error);
    throw error;
  }
}

async function migrateSkillsets() {
  console.log('\n=== Migrating Skillsets ===');

  try {
    const skillsets = await sourceIndexerClient.listSkillsets();

    console.log(`Found ${skillsets.length} skillset(s)`);

    for (const skillset of skillsets) {
      console.log(`Processing skillset: ${skillset.name}`);

      const cleanedSkillset = cleanReadOnlyProperties(skillset);

      try {
        await targetIndexerClient.createOrUpdateSkillset(cleanedSkillset);

        console.log(`✓ Created skillset: ${skillset.name}`);
      } catch (error) {
        throw error;
      }
    }
  } catch (error) {
    console.error('Error migrating skillsets:', error);
    throw error;
  }
}

async function migrateIndexes() {
  console.log('\n=== Migrating Indexes ===');

  try {
    const indexes = [];
    for await (const index of sourceIndexClient.listIndexes()) {
      indexes.push(index);
    }

    console.log(`Found ${indexes.length} index(es)`);

    for (const index of indexes) {
      console.log(`Processing index: ${index.name}`);

      const cleanedIndex = cleanReadOnlyProperties(index);

      try {
        await targetIndexClient.createOrUpdateIndex(cleanedIndex);
        console.log(`✓ Created index: ${index.name}`);
      } catch (error) {
        throw error;
      }
    }
  } catch (error) {
    console.error('Error migrating indexes:', error);
    throw error;
  }
}

async function migrateIndexers() {
  console.log('\n=== Migrating Indexers ===');

  try {
    const indexers = await sourceIndexerClient.listIndexers();

    console.log(`Found ${indexers.length} indexer(s)`);

    for (const indexer of indexers) {
      console.log(`Processing indexer: ${indexer.name}`);

      let cleanedIndexer = cleanReadOnlyProperties(indexer);

      delete cleanedIndexer.lastResult;
      delete cleanedIndexer.executionHistory;
      delete cleanedIndexer.status;

      cleanedIndexer = deepCleanDataSourceProperties(cleanedIndexer);

      try {
        await targetIndexerClient.createOrUpdateIndexer(cleanedIndexer);
        console.log(`✓ Created indexer: ${indexer.name}`);
      } catch (error) {
        throw error;
      }
    }
  } catch (error) {
    console.error('Error migrating indexers:', error);
    throw error;
  }
}

async function migrateSearchConfiguration() {
  console.log('Starting Azure Cognitive Search migration...');
  console.log(`Source: ${SOURCE_CONFIG.serviceName}`);
  console.log(`Target: ${TARGET_CONFIG.serviceName}\n`);

  try {
    await initializeSearchClients();

    await migrateDataSources();
    await migrateIndexes();
    await migrateSkillsets();
    await migrateIndexers();

    console.log('\n✓ Migration completed successfully!');
  } catch (error) {
    console.error('\n✗ Migration failed:', error);
    throw error;
  }
}

async function verifyMigration() {
  console.log('\n=== Verifying Migration ===');
  
  console.log('\nData Sources:');
  const dataSources = await targetIndexerClient.listDataSourceConnections();
  for (const ds of dataSources) {
    console.log(`  - ${ds.name}`);
  }
  
  console.log('\nSkillsets:');
  const skillsets = await targetIndexerClient.listSkillsets();
  for (const ss of skillsets) {
    console.log(`  - ${ss.name}`);
  }
  
  console.log('\nIndexes:');
  const indexes = [];
  for await (const idx of targetIndexClient.listIndexes()) {
    indexes.push(idx);
    console.log(`  - ${idx.name}`);
  }
  
  console.log('\nIndexers:');
  const indexers = await targetIndexerClient.listIndexers();
  for (const idxr of indexers) {
    console.log(`  - ${idxr.name}`);
  }
}

(async () => {
  try {
    await migrateSearchConfiguration();
    await verifyMigration();
  } catch (error) {
    console.error('Fatal error:', error);
    process.exit(1);
  }
})();
