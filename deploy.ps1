# deploy.ps1
# Deploy Athena PWA Infrastructure and save outputs

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$Location,
    
    [Parameter(Mandatory=$false)]
    [string]$TemplateFile = "./main.bicep",
    
    [Parameter(Mandatory=$false)]
    [string]$ParameterFile = "./main.bicepparam",
    
    [Parameter(Mandatory=$false)]
    [string]$OutputFile = "./deployment-outputs.json",
    
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory=$true)]
    [string]$TenantId
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Athena PWA Infrastructure Deployment" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if ($SubscriptionId) {
    Write-Host "`n[1/5] Setting Azure subscription context..." -ForegroundColor Yellow
    Set-AzContext -SubscriptionId $SubscriptionId -Tenant $TenantId| Out-Null
    Write-Host "  Subscription set: $SubscriptionId" -ForegroundColor Green
}

Write-Host "`n[2/5] Checking resource group..." -ForegroundColor Yellow
$rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue

if (-not $rg) {
    Write-Host "  Resource group not found. Creating..." -ForegroundColor Yellow
    New-AzResourceGroup -Name $ResourceGroupName -Location $Location | Out-Null
    Write-Host "  Resource group created: $ResourceGroupName" -ForegroundColor Green
}
else {
    Write-Host "  Resource group exists: $ResourceGroupName" -ForegroundColor Green
}

Write-Host "`n[3/5] Validating Bicep template..." -ForegroundColor Yellow
if (-not (Test-Path $TemplateFile)) {
    Write-Error "Template file not found: $TemplateFile"
    exit 1
}

if (-not (Test-Path $ParameterFile)) {
    Write-Error "Parameter file not found: $ParameterFile"
    exit 1
}

Write-Host "  Template file: $TemplateFile" -ForegroundColor Green
Write-Host "  Parameter file: $ParameterFile" -ForegroundColor Green

$deploymentName = "athena-deployment-$(Get-Date -Format 'yyyyMMddHHmmss')"

Write-Host "`n[4/5] Deploying infrastructure..." -ForegroundColor Yellow
Write-Host "  Deployment name: $deploymentName" -ForegroundColor Gray

try {
    $deployment = New-AzResourceGroupDeployment `
        -Name $deploymentName `
        -ResourceGroupName $ResourceGroupName `
        -TemplateFile $TemplateFile `
        -TemplateParameterFile $ParameterFile `
        -Verbose
    
    if ($deployment.ProvisioningState -eq "Succeeded") {
        Write-Host "  Deployment completed successfully" -ForegroundColor Green
    }
    else {
        Write-Error "Deployment failed with state: $($deployment.ProvisioningState)"
        exit 1
    }
}
catch {
    Write-Error "Deployment failed: $_"
    Write-Error $_.Exception.Message
    exit 1
}

Write-Host "`n[5/5] Saving deployment outputs..." -ForegroundColor Yellow

$outputs = @{
    deploymentName = $deploymentName
    resourceGroupName = $ResourceGroupName
    location = $Location
    timestamp = Get-Date -Format 'o'
    provisioningState = $deployment.ProvisioningState
}

Write-Host "`nDeployment Outputs:" -ForegroundColor Cyan
foreach ($key in $deployment.Outputs.Keys) {
    $value = $deployment.Outputs[$key].Value
    $outputs[$key] = $value
    
    $displayValue = $value
    if ($key -like "*Secret*" -or $key -like "*Key*" -or $key -like "*Connection*") {
        $displayValue = "***STORED IN KEY VAULT***"
    }
    
    Write-Host "  $key = $displayValue" -ForegroundColor Gray
}

$outputs | ConvertTo-Json -Depth 10 | Set-Content $OutputFile

Write-Host "`nOutputs saved to: $OutputFile" -ForegroundColor Green

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Deployment Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Resource Group: $ResourceGroupName" -ForegroundColor White
Write-Host "  Deployment Name: $deploymentName" -ForegroundColor White
Write-Host "  Status: $($deployment.ProvisioningState)" -ForegroundColor Green
Write-Host "  Duration: $($deployment.Duration)" -ForegroundColor White
Write-Host "  Outputs File: $OutputFile" -ForegroundColor White