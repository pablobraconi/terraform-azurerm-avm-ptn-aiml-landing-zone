<#
.SYNOPSIS
    Crea (idempotente) el backend remoto de Terraform en Azure Storage.

.DESCRIPTION
    Provisiona un Resource Group, Storage Account y Blob Container para
    almacenar el state remoto de Terraform. Asigna al SP indicado el rol
    "Storage Blob Data Contributor" para que pueda leer/escribir el state
    via OIDC (sin keys).

.PARAMETER SubscriptionId
    Id de la suscripcion donde se crea el backend.

.PARAMETER ResourceGroupName
    Resource Group para el backend. Default: rg-tfstate.

.PARAMETER Location
    Region. Default: eastus2.

.PARAMETER StorageAccountName
    Nombre global del Storage Account. Debe ser unico en Azure
    (3-24 chars, lowercase, sin guiones).

.PARAMETER ContainerName
    Nombre del blob container. Default: tfstate.

.PARAMETER GrantSpObjectId
    Object Id del Service Principal de GitHub Actions. Si se indica,
    se le asigna 'Storage Blob Data Contributor' sobre el storage account.

.EXAMPLE
    ./scripts/setup-tfstate-backend.ps1 `
        -SubscriptionId 11111111-1111-1111-1111-111111111111 `
        -StorageAccountName araucotfstatedev `
        -GrantSpObjectId <objectId-del-SP>
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [string]$ResourceGroupName = 'rg-tfstate',

    [string]$Location = 'eastus2',

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9]{3,24}$')]
    [string]$StorageAccountName,

    [string]$ContainerName = 'tfstate',

    [string]$GrantSpObjectId
)

$ErrorActionPreference = 'Stop'

function Write-Step([string]$msg) {
    Write-Host ""
    Write-Host "==> $msg" -ForegroundColor Cyan
}

Write-Step "Validando az CLI"
$null = & az --version 2>$null
if ($LASTEXITCODE -ne 0) { throw "Azure CLI no esta instalado." }

az account set --subscription $SubscriptionId | Out-Null
$tenantId = az account show --query tenantId -o tsv

Write-Host "Tenant       : $tenantId"
Write-Host "Subscription : $SubscriptionId"
Write-Host "RG           : $ResourceGroupName"
Write-Host "Location     : $Location"
Write-Host "Storage      : $StorageAccountName"
Write-Host "Container    : $ContainerName"

# 1. Resource Group
Write-Step "Resource Group"
$rgExists = az group exists --name $ResourceGroupName
if ($rgExists -eq 'true') {
    Write-Host "RG '$ResourceGroupName' ya existe"
} else {
    az group create --name $ResourceGroupName --location $Location | Out-Null
    Write-Host "RG creado"
}

# 2. Storage Account
Write-Step "Storage Account"
$saJson = az storage account list --resource-group $ResourceGroupName --query "[?name=='$StorageAccountName']" -o json | ConvertFrom-Json
if ($saJson.Count -gt 0) {
    Write-Host "Storage Account '$StorageAccountName' ya existe"
} else {
    az storage account create `
        --name $StorageAccountName `
        --resource-group $ResourceGroupName `
        --location $Location `
        --sku Standard_LRS `
        --kind StorageV2 `
        --min-tls-version TLS1_2 `
        --allow-blob-public-access false `
        --https-only true | Out-Null
    Write-Host "Storage Account creado"
}

# Habilitar versioning + soft delete del blob (proteger el state)
Write-Step "Habilitando versioning + soft delete"
az storage account blob-service-properties update `
    --account-name $StorageAccountName `
    --resource-group $ResourceGroupName `
    --enable-versioning true `
    --enable-delete-retention true `
    --delete-retention-days 30 `
    --enable-container-delete-retention true `
    --container-delete-retention-days 30 | Out-Null

# 3. Blob container
Write-Step "Blob container"
$saId = az storage account show --name $StorageAccountName --resource-group $ResourceGroupName --query id -o tsv

# Damos al usuario actual permiso temporal para crear el container via Entra ID
$userObjId = az ad signed-in-user show --query id -o tsv 2>$null
if ($userObjId) {
    $existing = az role assignment list --assignee $userObjId --scope $saId --role "Storage Blob Data Contributor" -o json | ConvertFrom-Json
    if ($existing.Count -eq 0) {
        az role assignment create --assignee-object-id $userObjId --assignee-principal-type User --role "Storage Blob Data Contributor" --scope $saId | Out-Null
        Write-Host "Asignado 'Storage Blob Data Contributor' al usuario actual (para crear container)"
        Write-Host "Esperando propagacion (15s)..."
        Start-Sleep -Seconds 15
    }
}

$ctnExists = az storage container exists --name $ContainerName --account-name $StorageAccountName --auth-mode login --query exists -o tsv 2>$null
if ($ctnExists -eq 'true') {
    Write-Host "Container '$ContainerName' ya existe"
} else {
    az storage container create --name $ContainerName --account-name $StorageAccountName --auth-mode login | Out-Null
    Write-Host "Container creado"
}

# 4. Asignar rol al SP de GitHub Actions
if ($GrantSpObjectId) {
    Write-Step "Asignando rol al Service Principal de GitHub Actions"
    $existing = az role assignment list `
        --assignee-object-id $GrantSpObjectId `
        --assignee-principal-type ServicePrincipal `
        --scope $saId `
        --role "Storage Blob Data Contributor" `
        -o json | ConvertFrom-Json
    if ($existing.Count -gt 0) {
        Write-Host "SP ya tiene 'Storage Blob Data Contributor' sobre $StorageAccountName"
    } else {
        az role assignment create `
            --assignee-object-id $GrantSpObjectId `
            --assignee-principal-type ServicePrincipal `
            --role "Storage Blob Data Contributor" `
            --scope $saId | Out-Null
        Write-Host "SP recibio 'Storage Blob Data Contributor'"
    }
}

# 5. Resumen
Write-Step "Listo"
Write-Host ""
Write-Host "Configura tu backend.tf con estos valores:" -ForegroundColor Green
Write-Host ""
Write-Host "  resource_group_name  = `"$ResourceGroupName`""
Write-Host "  storage_account_name = `"$StorageAccountName`""
Write-Host "  container_name       = `"$ContainerName`""
Write-Host "  key                  = `"<algo-unico-por-scenario>.tfstate`""
Write-Host ""
Write-Host "En el workflow exporta tambien:" -ForegroundColor Green
Write-Host "  ARM_USE_AZUREAD = true   # autentica el backend via OIDC sin keys"
Write-Host ""
