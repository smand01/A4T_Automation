require('dotenv').config();
const { BlobServiceClient } = require('@azure/storage-blob');
const fs = require('fs').promises;

async function readAthenaTableData(csvFilePath) {
    console.log('Reading AthenaTableData.csv...');
    const csvContent = await fs.readFile(csvFilePath, 'utf-8');
    const lines = csvContent.split('\n').filter(line => line.trim());
    
    if (lines.length < 2) {
        throw new Error('CSV file is empty or has no data rows');
    }
    
    function parseCSVLine(line) {
        const result = [];
        let current = '';
        let inQuotes = false;
        
        for (let i = 0; i < line.length; i++) {
            const char = line[i];
            if (char === '"') {
                inQuotes = !inQuotes;
            } else if (char === ',' && !inQuotes) {
                result.push(current.trim());
                current = '';
            } else {
                current += char;
            }
        }
        result.push(current.trim());
        return result;
    }
    
    const headers = parseCSVLine(lines[0]);
    const entityNameIndex = headers.findIndex(h => h === 'AthenaDbEntityName');
    const containerIndex = headers.findIndex(h => h === 'Container');
    
    if (entityNameIndex === -1 || containerIndex === -1) {
        throw new Error('Required columns AthenaDbEntityName or Container not found in CSV');
    }
    
    console.log(`Found column indexes: AthenaDbEntityName=${entityNameIndex}, Container=${containerIndex}`);
    
    const blobMigrations = [];
    const seen = new Set();
    
    for (let i = 1; i < lines.length; i++) {
        const columns = parseCSVLine(lines[i]);
        const entityName = columns[entityNameIndex]?.trim();
        const container = columns[containerIndex]?.trim();
        
        if (entityName && container && container !== 'ATS' && entityName !== 'NA' && !seen.has(entityName)) {
            seen.add(entityName);
            blobMigrations.push({
                entityName,
                container
            });
        }
    }
    
    console.log(`Found ${blobMigrations.length} blobs to migrate`);
    
    return blobMigrations;
}

async function copyBlobFile(sourceBlobEndpoint, destBlobEndpoint, containerName, fileName) {
    const startTime = Date.now();
    
    const normalizedContainerName = containerName.toLowerCase();
    
    console.log(`\nCopying blob: ${fileName}`);
    console.log(`  Container: ${containerName} (normalized: ${normalizedContainerName})`);
    console.log(`  Started at: ${new Date().toLocaleTimeString()}`);
    
    const sourceBlobServiceClient = new BlobServiceClient(sourceBlobEndpoint);
    const destBlobServiceClient = new BlobServiceClient(destBlobEndpoint);
    
    const sourceContainer = sourceBlobServiceClient.getContainerClient(normalizedContainerName);
    try {
        const exists = await sourceContainer.exists();
        if (!exists) {
            throw new Error(`Container '${normalizedContainerName}' does not exist in source storage account`);
        }
        console.log(`  ✓ Source container exists`);
    } catch (error) {
        if (error.message.includes('does not exist')) {
            throw error;
        }
        throw new Error(`Container '${normalizedContainerName}' does not exist in source storage account: ${error.message}`);
    }
    
    const destContainer = destBlobServiceClient.getContainerClient(normalizedContainerName);
    
    try {
        const exists = await destContainer.exists();
        if (!exists) {
            await destContainer.create();
            console.log(`  ✓ Container '${normalizedContainerName}' created in destination`);
        } else {
            console.log(`  ✓ Container '${normalizedContainerName}' already exists in destination`);
        }
    } catch (error) {
        if (error.statusCode !== 409) {
            throw error;
        }
    }
    
    const sourceBlobClient = sourceContainer.getBlobClient(fileName);
    
    try {
        const exists = await sourceBlobClient.exists();
        if (!exists) {
            throw new Error(`Blob '${fileName}' does not exist in source container '${normalizedContainerName}'`);
        }
        console.log(`  ✓ Source blob exists`);
    } catch (error) {
        if (error.message.includes('does not exist')) {
            throw error;
        }
        throw new Error(`Error checking blob '${fileName}' in source: ${error.message}`);
    }
    
    const destBlobClient = destContainer.getBlobClient(fileName);
    
    try {
        const destExists = await destBlobClient.exists();
        if (destExists) {
            console.log(`  ⊘ Blob '${fileName}' already exists in destination - SKIPPING`);
            const properties = await destBlobClient.getProperties();
            const duration = (Date.now() - startTime) / 1000;
            return { size: properties.contentLength, duration, skipped: true };
        }
        
        console.log(`  ⟳ Copying blob...`);
        const sourceUrl = sourceBlobClient.url;
        const copyPoller = await destBlobClient.beginCopyFromURL(sourceUrl);
        await copyPoller.pollUntilDone();
        
        const properties = await destBlobClient.getProperties();
        const sizeInKB = (properties.contentLength / 1024).toFixed(2);
        
        const endTime = Date.now();
        const duration = (endTime - startTime) / 1000;
        console.log(`  ✓ Completed: ${sizeInKB} KB copied in ${duration.toFixed(2)}s`);
        
        return { size: properties.contentLength, duration, skipped: false };
    } catch (error) {
        throw new Error(`Failed to copy blob '${fileName}': ${error.message}`);
    }
}

async function main() {
    try {
        console.log('=== Azure Blob Storage Migration Tool ===\n');
        
        const blobMigrations = await readAthenaTableData('./AthenaTableData.csv');
        
        const sourceStorageAccount = process.env.SOURCE_STORAGE_ACCOUNT;
        const destStorageAccount = process.env.DEST_STORAGE_ACCOUNT;
        const sourceSas = process.env.SOURCE_SAS;
        const destSas = process.env.DEST_SAS;
        
        if (!sourceStorageAccount || !destStorageAccount || !sourceSas || !destSas) {
            throw new Error('Missing required environment variables: SOURCE_STORAGE_ACCOUNT, DEST_STORAGE_ACCOUNT, SOURCE_SAS, DEST_SAS');
        }
        
        console.log('\n=== Configuration Summary ===');
        console.log('Source:');
        console.log(`  Storage Account: ${sourceStorageAccount}`);
        console.log(`  SAS Token: ${sourceSas.substring(0, 20)}...`);
        console.log('\nDestination:');
        console.log(`  Storage Account: ${destStorageAccount}`);
        console.log(`  SAS Token: ${destSas.substring(0, 20)}...`);
        console.log(`\nTotal blobs to migrate: ${blobMigrations.length}`);
        
        console.log('\nPreparing endpoints...');
        const sourceBlobEndpoint = `https://${sourceStorageAccount}.blob.core.windows.net?${sourceSas}`;
        const destBlobEndpoint = `https://${destStorageAccount}.blob.core.windows.net?${destSas}`;
        
        console.log('\n=== Starting Blob Migration ===');
        const migrationStartTime = Date.now();
        console.log(`Migration started at: ${new Date().toLocaleString()}\n`);
        
        let totalBlobsSize = 0;
        let successCount = 0;
        let failCount = 0;
        let skippedCount = 0;
        const successfulMigrations = [];
        const failedMigrations = [];
        const skippedMigrations = [];
        
        for (let i = 0; i < blobMigrations.length; i++) {
            const migration = blobMigrations[i];
            const fileName = `${migration.entityName}.json`;
            
            console.log(`[${i + 1}/${blobMigrations.length}] Processing ${migration.entityName}...`);
            
            try {
                const result = await copyBlobFile(
                    sourceBlobEndpoint,
                    destBlobEndpoint,
                    migration.container,
                    fileName
                );
                
                if (result.skipped) {
                    skippedCount++;
                    skippedMigrations.push({
                        name: migration.entityName,
                        container: migration.container,
                        size: result.size,
                        reason: 'Already exists in destination'
                    });
                } else {
                    totalBlobsSize += result.size;
                    successCount++;
                    successfulMigrations.push({
                        name: migration.entityName,
                        container: migration.container,
                        size: result.size,
                        duration: result.duration
                    });
                }
            } catch (error) {
                console.error(`  ✗ Failed: ${error.message}\n`);
                failCount++;
                failedMigrations.push({
                    name: migration.entityName,
                    container: migration.container,
                    reason: error.message
                });
            }
        }
        
        const migrationEndTime = Date.now();
        const totalMigrationDuration = (migrationEndTime - migrationStartTime) / 1000;
        
        console.log('\n=== Migration Summary ===');
        console.log(`Migration completed at: ${new Date().toLocaleString()}`);
        console.log(`Total migration time: ${Math.floor(totalMigrationDuration / 60)}m ${(totalMigrationDuration % 60).toFixed(2)}s`);
        console.log(`Total blobs processed: ${blobMigrations.length}`);
        console.log(`Successful: ${successCount}`);
        console.log(`Skipped (already exists): ${skippedCount}`);
        console.log(`Failed: ${failCount}`);
        console.log(`Total blob size copied: ${(totalBlobsSize / 1024 / 1024).toFixed(2)} MB`);
        
        if (successfulMigrations.length > 0) {
            console.log('\n=== Successful Migrations ===');
            successfulMigrations.forEach(blob => {
                console.log(`  ${blob.name}.json [${blob.container}]: ${(blob.size / 1024).toFixed(2)} KB in ${blob.duration.toFixed(2)}s`);
            });
        }
        
        if (skippedMigrations.length > 0) {
            console.log('\n=== Skipped Migrations (Already Exist) ===');
            skippedMigrations.forEach(blob => {
                console.log(`  ${blob.name}.json [${blob.container}]: ${(blob.size / 1024).toFixed(2)} KB`);
            });
        }
        
        if (failedMigrations.length > 0) {
            console.log('\n=== Failed Migrations ===');
            failedMigrations.forEach(blob => {
                console.log(`  ${blob.name}.json [${blob.container}]: ${blob.reason}`);
            });
        }
        
        const migrationResults = {
            migrationInfo: {
                startTime: new Date(migrationStartTime).toISOString(),
                endTime: new Date(migrationEndTime).toISOString(),
                totalDurationSeconds: totalMigrationDuration,
                sourceStorageAccount: sourceStorageAccount,
                destStorageAccount: destStorageAccount,
                totalBlobsProcessed: blobMigrations.length,
                successfulCount: successCount,
                skippedCount: skippedCount,
                failedCount: failCount,
                totalBlobSizeCopied: totalBlobsSize
            },
            successfulMigrations: successfulMigrations,
            skippedMigrations: skippedMigrations,
            failedMigrations: failedMigrations
        };
        
        const resultFileName = `blob-migration-results-${new Date().toISOString().replace(/[:.]/g, '-')}.json`;
        await fs.writeFile(resultFileName, JSON.stringify(migrationResults, null, 2));
        console.log(`\nResults saved to: ${resultFileName}`);
        
        console.log('\nBlob migration completed!');
        
    } catch (error) {
        console.error('Migration failed:', error.message);
        console.error(error);
        process.exit(1);
    }
}

main();
