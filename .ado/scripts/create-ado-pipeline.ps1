<#
.SYNOPSIS
    Creates ADO pipeline for SFDC Read MCP APIM deployment
.PARAMETER OrganizationUrl
    ADO organization URL
.PARAMETER ProjectName
    ADO project name
.PARAMETER RepositoryName
    GitHub repository name
.EXAMPLE
    .\create-ado-pipeline.ps1
#>

param(
    [string]$OrganizationUrl = "https://dev.azure.com/AMNEngineering",
    [string]$ProjectName = "Cloud Operations",
    [string]$RepositoryName = "AMNEngineering/sfdc-read-mcp-apim",
    [string]$PipelineName = "sfdc-read-mcp-apim-deploy",
    [string]$YamlPath = ".ado/pipelines/deploy.yml"
)

$ErrorActionPreference = "Stop"

Write-Host "🚀 Creating ADO Pipeline for SFDC Read MCP APIM" -ForegroundColor Cyan

# Check prerequisites
Write-Host "Checking prerequisites..." -ForegroundColor Cyan
$azVersion = az version 2>&1 | ConvertFrom-Json
if (-not $azVersion) {
    throw "Azure CLI not found. Install from https://aka.ms/installazurecli"
}

$extensions = az extension list | ConvertFrom-Json
if (-not ($extensions | Where-Object { $_.name -eq "azure-devops" })) {
    Write-Host "Installing azure-devops extension..." -ForegroundColor Yellow
    az extension add --name azure-devops
}

# Set defaults
Write-Host "Configuring ADO defaults..." -ForegroundColor Cyan
az devops configure --defaults organization=$OrganizationUrl project=$ProjectName

# Check if pipeline exists
Write-Host "Checking if pipeline '$PipelineName' exists..." -ForegroundColor Cyan
$existingPipeline = az pipelines list --name $PipelineName 2>$null | ConvertFrom-Json

if ($existingPipeline) {
    Write-Host "Pipeline '$PipelineName' already exists (ID: $($existingPipeline[0].id))" -ForegroundColor Yellow
    Write-Host "View at: $OrganizationUrl/$ProjectName/_build?definitionId=$($existingPipeline[0].id)" -ForegroundColor Cyan
    exit 0
}

# Create pipeline
Write-Host "Creating pipeline '$PipelineName'..." -ForegroundColor Green
Write-Host "  Repository: $RepositoryName" -ForegroundColor Gray
Write-Host "  YAML path: $YamlPath" -ForegroundColor Gray

try {
    $pipeline = az pipelines create `
        --name $PipelineName `
        --description "Terraform deployment pipeline for SFDC Read MCP APIM contract" `
        --repository $RepositoryName `
        --repository-type github `
        --branch main `
        --yml-path $YamlPath `
        --skip-first-run `
        --output json | ConvertFrom-Json

    Write-Host "`n✅ Pipeline created successfully!" -ForegroundColor Green
    Write-Host "   Pipeline ID: $($pipeline.id)" -ForegroundColor Gray
    Write-Host "   Pipeline Name: $($pipeline.name)" -ForegroundColor Gray
    Write-Host "   View at: $OrganizationUrl/$ProjectName/_build?definitionId=$($pipeline.id)" -ForegroundColor Cyan

    Write-Host "`n📋 Next steps:" -ForegroundColor Yellow
    Write-Host "   1. Ensure all variable groups are created (dev/int/prod)" -ForegroundColor Gray
    Write-Host "   2. Grant pipeline access to variable groups" -ForegroundColor Gray
    Write-Host "   3. Create service connections: Azure-APIM-SFDC-{dev|int|prod}" -ForegroundColor Gray
    Write-Host "   4. Create ADO environment: sfdc-read-mcp-production (with approval gate)" -ForegroundColor Gray
    Write-Host "   5. Run pipeline manually: az pipelines run --name '$PipelineName' --parameters environment=dev action=plan" -ForegroundColor Gray
}
catch {
    Write-Host "`n❌ Failed to create pipeline" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host "`nManual creation steps:" -ForegroundColor Yellow
    Write-Host "   1. Go to: $OrganizationUrl/$ProjectName/_build" -ForegroundColor Gray
    Write-Host "   2. Click 'New pipeline'" -ForegroundColor Gray
    Write-Host "   3. Select 'GitHub'" -ForegroundColor Gray
    Write-Host "   4. Select repository: $RepositoryName" -ForegroundColor Gray
    Write-Host "   5. Select 'Existing Azure Pipelines YAML file'" -ForegroundColor Gray
    Write-Host "   6. Path: /$YamlPath" -ForegroundColor Gray
    Write-Host "   7. Save (don't run yet)" -ForegroundColor Gray

    exit 1
}
