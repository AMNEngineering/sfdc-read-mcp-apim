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

# Note: az pipelines create with GitHub requires interactive authentication
# which can lock up PowerShell. Using manual approach instead.

Write-Host "`n⚠️  Pipeline creation requires GitHub authentication" -ForegroundColor Yellow
Write-Host "To avoid PowerShell lockup, use the manual approach below:" -ForegroundColor Yellow

Write-Host "`n📋 Manual Pipeline Creation Steps:" -ForegroundColor Cyan
Write-Host "1. Open browser: $OrganizationUrl/$ProjectName/_build" -ForegroundColor White
Write-Host "2. Click 'New pipeline'" -ForegroundColor White
Write-Host "3. Select 'GitHub'" -ForegroundColor White
Write-Host "4. Authenticate to GitHub (one-time OAuth)" -ForegroundColor White
Write-Host "5. Select repository: $RepositoryName" -ForegroundColor White
Write-Host "6. Select 'Existing Azure Pipelines YAML file'" -ForegroundColor White
Write-Host "7. Branch: main" -ForegroundColor White
Write-Host "8. Path: /$YamlPath" -ForegroundColor White
Write-Host "9. Click 'Continue' then 'Save' (don't run yet)" -ForegroundColor White

Write-Host "`n💡 Alternative: Create via ADO REST API with your existing auth" -ForegroundColor Cyan
$createPipeline = Read-Host "Would you like to try automated creation? (y/n)"

if ($createPipeline -eq 'y') {
    Write-Host "`nAttempting automated creation..." -ForegroundColor Green
    Write-Host "Note: This may prompt for GitHub authentication" -ForegroundColor Yellow

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
    }
    catch {
        Write-Host "`n❌ Automated creation failed: $_" -ForegroundColor Red
        Write-Host "Please use manual steps above" -ForegroundColor Yellow
        exit 1
    }
}
else {
    Write-Host "`n✅ Use manual steps above to create pipeline" -ForegroundColor Green
    Write-Host "This avoids authentication prompts and PowerShell lockups" -ForegroundColor Gray
}

Write-Host "`n📋 After pipeline is created:" -ForegroundColor Yellow
Write-Host "   1. Ensure all variable groups are created (dev/int/prod)" -ForegroundColor Gray
Write-Host "   2. Grant pipeline access to variable groups" -ForegroundColor Gray
Write-Host "   3. Service connections already exist (ADO-AMNEngineering-CloudOps-lower/Upper)" -ForegroundColor Gray
Write-Host "   4. Create ADO environment: sfdc-read-mcp-production (with approval gate)" -ForegroundColor Gray
Write-Host "   5. Run pipeline manually: az pipelines run --name '$PipelineName' --parameters environment=dev action=plan" -ForegroundColor Gray
