require('dotenv').config();
const { DefaultAzureCredential } = require('@azure/identity');
const { TableServiceClient, TableClient } = require('@azure/data-tables');
const { StorageManagementClient } = require('@azure/arm-storage');
const fs = require('fs').promises;

async function getUniqueTableNames(schemaFilePath) {
    console.log('Reading AthenaSchema.json...');
    const schemaData = await fs.readFile(schemaFilePath, 'utf-8');
    const schema = JSON.parse(schemaData);
    
    const tableNamesSet = new Set();
    schema.forEach(item => {
        if (item.TableName) {
            tableNamesSet.add(item.TableName);
        }
    });
    
    const tables = Array.from(tableNamesSet);
    console.log(`Found ${tables.length} unique tables in schema`);
    return tables;
}

async function ensureStorageAccountExists(credential, subscriptionId, resourceGroupName, storageAccountName, location = 'eastus') {
    const storageClient = new StorageManagementClient(credential, subscriptionId);
    
    try {
        const account = await storageClient.storageAccounts.getProperties(resourceGroupName, storageAccountName);
        console.log(`Storage account '${storageAccountName}' already exists`);
        return account;
    } catch (error) {
        if (error.statusCode === 404 || error.code === 'ResourceNotFound') {
            console.log(`Storage account '${storageAccountName}' not found. Creating...`);
            
            const createParams = {
                location: location,
                sku: {
                    name: 'Standard_LRS'
                },
                kind: 'StorageV2',
                properties: {
                    allowBlobPublicAccess: false,
                    minimumTlsVersion: 'TLS1_2'
                }
            };
            
            const createOperation = await storageClient.storageAccounts.beginCreateAndWait(
                resourceGroupName,
                storageAccountName,
                createParams
            );
            
            console.log(`Storage account '${storageAccountName}' created successfully`);
            return createOperation;
        } else {
            throw error;
        }
    }
}

async function copyTableData(sourceEndpoint, destEndpoint, credential, tableName) {
    const startTime = Date.now();
    console.log(`\nCopying table: ${tableName} - Started at ${new Date().toLocaleTimeString()}`);
    
    const sourceTable = new TableClient(sourceEndpoint, tableName, credential);
    const destTable = new TableClient(destEndpoint, tableName, credential);
    
    try {
        const entities = sourceTable.listEntities({ top: 1 });
        const iterator = entities[Symbol.asyncIterator]();
        await iterator.next();
    } catch (error) {
        if (error.message && error.message.includes('TableNotFound')) {
            throw new Error(`Table '${tableName}' does not exist in source storage account`);
        } else if (error.message && error.message.includes('AuthorizationPermissionMismatch')) {
            throw new Error(`Insufficient permissions to access table '${tableName}' in source storage account`);
        } else {
            throw error;
        }
    }
    
    const destTableServiceClient = new TableServiceClient(destEndpoint, credential);
    
    try {
        await destTableServiceClient.createTable(tableName);
        console.log(`  Table '${tableName}' created in destination`);
    } catch (error) {
        if (error.statusCode === 409) {
            console.log(`  Table '${tableName}' already exists in destination`);
        } else {
            throw error;
        }
    }
    
    let entityCount = 0;
    const entities = sourceTable.listEntities();
    const batchSize = 100;
    let batch = [];
    
    console.log(`  Reading entities from source...`);
    
    for await (const entity of entities) {
        batch.push(entity);
        
        if (batch.length >= batchSize) {
            await processBatch(destTable, batch);
            entityCount += batch.length;
            process.stdout.write(`\r  Copied ${entityCount} entities...`);
            batch = [];
        }
    }
    
    if (batch.length > 0) {
        await processBatch(destTable, batch);
        entityCount += batch.length;
    }
    
    const endTime = Date.now();
    const duration = (endTime - startTime) / 1000;
    console.log(`\n  ✓ Completed: ${entityCount} entities copied for table '${tableName}' in ${duration.toFixed(2)}s`);
    return { entityCount, duration };
}

async function processBatch(destTable, batch) {
    await Promise.allSettled(
        batch.map(async (entity) => {
            try {
                await destTable.upsertEntity(entity, 'Replace');
            } catch (error) {
                console.error(`\n  Error copying entity:`, error.message);
            }
        })
    );
}

async function main() {
    try {
        console.log('=== Azure Table Storage Migration Tool ===\n');
        
        const tables = await getUniqueTableNames('./AthenaSchema.json');
        console.log(`Tables to migrate: ${tables.join(', ')}\n`);
        
        const sourceSubscriptionId = process.env.SOURCE_SUBSCRIPTION_ID;
        const sourceResourceGroupName = process.env.SOURCE_RESOURCE_GROUP;
        const sourceStorageAccount = process.env.SOURCE_STORAGE_ACCOUNT;
        
        const destSubscriptionId = process.env.DEST_SUBSCRIPTION_ID;
        const destResourceGroupName = process.env.DEST_RESOURCE_GROUP;
        const destStorageAccount = process.env.DEST_STORAGE_ACCOUNT;
        const location = process.env.DEST_LOCATION || 'eastus';
        
        const maxConcurrency = parseInt(process.env.MAX_CONCURRENCY || '5', 10);
        
        if (!sourceSubscriptionId || !sourceResourceGroupName || !sourceStorageAccount ||
            !destSubscriptionId || !destResourceGroupName || !destStorageAccount) {
            throw new Error('Missing required environment variables');
        }
        
        console.log('\n=== Configuration Summary ===');
        console.log('Source:');
        console.log(`  Subscription ID: ${sourceSubscriptionId}`);
        console.log(`  Resource Group: ${sourceResourceGroupName}`);
        console.log(`  Storage Account: ${sourceStorageAccount}`);
        console.log('\nDestination:');
        console.log(`  Subscription ID: ${destSubscriptionId}`);
        console.log(`  Resource Group: ${destResourceGroupName}`);
        console.log(`  Storage Account: ${destStorageAccount}`);
        console.log(`  Location: ${location}`);
        console.log(`\nTables to migrate: ${tables.length}`);
        console.log(`Max concurrent migrations: ${maxConcurrency}`);
        
        const credential = new DefaultAzureCredential();
        
        await ensureStorageAccountExists(
            credential,
            destSubscriptionId,
            destResourceGroupName,
            destStorageAccount,
            location
        );
        
        console.log('\nPreparing endpoints...');
        const sourceEndpoint = `https://${sourceStorageAccount}.table.core.windows.net`;
        const destEndpoint = `https://${destStorageAccount}.table.core.windows.net`;
        
        console.log('\n=== Starting Table Migration ===');
        const migrationStartTime = Date.now();
        console.log(`Migration started at: ${new Date().toLocaleString()}`);
        
        let totalEntities = 0;
        let totalDuration = 0;
        let successCount = 0;
        let failCount = 0;
        const successfulTables = [];
        const failedTables = [];
        
        const processBatch = async (batch) => {
            return Promise.allSettled(
                batch.map(async (tableName) => {
                    const tableStartTime = Date.now();
                    try {
                        const result = await copyTableData(
                            sourceEndpoint,
                            destEndpoint,
                            credential,
                            tableName
                        );
                        return {
                            status: 'success',
                            tableName,
                            entityCount: result.entityCount,
                            duration: result.duration
                        };
                    } catch (error) {
                        const tableEndTime = Date.now();
                        const tableDuration = (tableEndTime - tableStartTime) / 1000;
                        return {
                            status: 'failed',
                            tableName,
                            duration: tableDuration,
                            error: error.message
                        };
                    }
                })
            );
        };
        
        for (let i = 0; i < tables.length; i += maxConcurrency) {
            const batch = tables.slice(i, i + maxConcurrency);
            console.log(`\nProcessing batch ${Math.floor(i / maxConcurrency) + 1} of ${Math.ceil(tables.length / maxConcurrency)} (${batch.length} tables)...`);
            
            const results = await processBatch(batch);
            
            results.forEach((result) => {
                if (result.status === 'fulfilled' && result.value.status === 'success') {
                    const { tableName, entityCount, duration } = result.value;
                    totalEntities += entityCount;
                    totalDuration += duration;
                    successCount++;
                    successfulTables.push({
                        name: tableName,
                        entities: entityCount,
                        duration: duration
                    });
                } else {
                    const error = result.status === 'rejected' ? result.reason : result.value;
                    const tableName = error.tableName || 'unknown';
                    const errorMsg = error.error || error.message || 'Unknown error';
                    const tableDuration = error.duration || 0;
                    
                    console.error(`\n Failed to copy table '${tableName}' after ${tableDuration.toFixed(2)}s:`);
                    if (errorMsg.includes('TableNotFound')) {
                        console.error(`  Reason: Table does not exist in source`);
                    } else if (errorMsg.includes('AuthorizationPermissionMismatch')) {
                        console.error(`  Reason: Insufficient permissions to access this table`);
                    } else {
                        console.error(`  Reason: ${errorMsg}`);
                    }
                    failCount++;
                    failedTables.push({
                        name: tableName,
                        duration: tableDuration,
                        reason: errorMsg
                    });
                }
            });
        }
        
        const migrationEndTime = Date.now();
        const totalMigrationDuration = (migrationEndTime - migrationStartTime) / 1000;
        
        console.log('\n=== Migration Summary ===');
        console.log(`Migration completed at: ${new Date().toLocaleString()}`);
        console.log(`Total migration time: ${Math.floor(totalMigrationDuration / 60)}m ${(totalMigrationDuration % 60).toFixed(2)}s`);
        console.log(`Total tables processed: ${tables.length}`);
        console.log(`Successful: ${successCount}`);
        console.log(`Failed: ${failCount}`);
        console.log(`Total entities copied: ${totalEntities}`);
        
        if (successfulTables.length > 0) {
            console.log('\n=== Successful Tables ===');
            successfulTables.forEach(table => {
                console.log(`  ${table.name}: ${table.entities} entities in ${table.duration.toFixed(2)}s`);
            });
        }
        
        if (failedTables.length > 0) {
            console.log('\n=== Failed Tables ===');
            failedTables.forEach(table => {
                console.log(`  ${table.name}: Failed after ${table.duration.toFixed(2)}s`);
            });
        }
        
        if (totalEntities > 0) {
            const avgEntitiesPerSecond = (totalEntities / totalDuration).toFixed(2);
            console.log(`\nAverage throughput: ${avgEntitiesPerSecond} entities/second`);
        }
        
        const migrationResults = {
            migrationInfo: {
                startTime: new Date(migrationStartTime).toISOString(),
                endTime: new Date(migrationEndTime).toISOString(),
                totalDurationSeconds: totalMigrationDuration,
                sourceStorageAccount: sourceStorageAccount,
                destStorageAccount: destStorageAccount,
                totalTablesProcessed: tables.length,
                successfulCount: successCount,
                failedCount: failCount,
                totalEntitiesCopied: totalEntities,
                averageThroughput: totalEntities > 0 ? (totalEntities / totalDuration).toFixed(2) : 0
            },
            successfulTables: successfulTables,
            failedTables: failedTables,
            allTables: tables
        };
        
        const resultFileName = `migration-results-${new Date().toISOString().replace(/[:.]/g, '-')}.json`;
        await fs.writeFile(resultFileName, JSON.stringify(migrationResults, null, 2));
        console.log(`\nResults saved to: ${resultFileName}`);
        
        console.log('\nMigration completed!');
        
    } catch (error) {
        console.error('Migration failed:', error.message);
        console.error(error);
        process.exit(1);
    }
}

main();
