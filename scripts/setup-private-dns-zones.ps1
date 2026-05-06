<#
.SYNOPSIS
    Crea (idempotente) las DNS zones privadas que necesita la AI/ML Landing Zone.

.DESCRIPTION
    El modulo levanta este conjunto de zonas privadas cuando
    flag_platform_landing_zone = true. Este script las pre-crea en el RG
    indicado para emular un hub central de DNS.

.PARAMETER SubscriptionId
    Id de la suscripcion donde se crean las zonas.

.PARAMETER ResourceGroupName
    Resource Group destino. Default: rg-tfstate.

.PARAMETER VnetResourceId
    (Opcional) Resource Id de una VNet a vincular a cada zona via virtual-network-link.
    Si se omite, las zonas quedan creadas pero sin link.

.EXAMPLE
    ./scripts/setup-private-dns-zones.ps1 `
        -SubscriptionId 85fbd7d4-c974-44b3-8f11-47bc1d72ee5b `
        -ResourceGroupName rg-tfstate
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [string]$ResourceGroupName = 'rg-tfstate',

    [string]$VnetResourceId
)

$ErrorActionPreference = 'Stop'

# Lista alineada con locals.networking.tf -> private_dns_zone_map
$zones = @(
    'privatelink.vaultcore.azure.net',
    'privatelink.azure-api.net',
    'privatelink.documents.azure.com',
    'privatelink.blob.core.windows.net',
    'privatelink.web.core.windows.net',
    'privatelink.search.windows.net',
    'privatelink.azurecr.io',
    'privatelink.azconfig.io',
    'privatelink.openai.azure.com',
    'privatelink.services.ai.azure.com',
    'privatelink.cognitiveservices.azure.com'
)

function Write-Step([string]$msg) {
    Write-Host ""
    Write-Host "==> $msg" -ForegroundColor Cyan
}

Write-Step "Validando az CLI"
$null = & az --version 2>$null
if ($LASTEXITCODE -ne 0) { throw "Azure CLI no esta instalado." }

az account set --subscription $SubscriptionId | Out-Null
Write-Host "Subscription : $SubscriptionId"
Write-Host "RG           : $ResourceGroupName"
Write-Host "Zonas        : $($zones.Count)"
if ($VnetResourceId) { Write-Host "VNet link    : $VnetResourceId" }

# Verifica RG
Write-Step "Verificando Resource Group"
$rgExists = az group exists --name $ResourceGroupName
if ($rgExists -ne 'true') {
    throw "El RG '$ResourceGroupName' no existe. Crealo primero (p.ej. con setup-tfstate-backend.ps1)."
}

# Crea zonas
Write-Step "Creando DNS zones privadas"
foreach ($zone in $zones) {
    $existing = az network private-dns zone show --resource-group $ResourceGroupName --name $zone --output json 2>$null
    if ($LASTEXITCODE -eq 0 -and $existing) {
        Write-Host "[skip]  $zone"
    } else {
        az network private-dns zone create --resource-group $ResourceGroupName --name $zone --output none
        Write-Host "[ok]    $zone"
    }
}

# VNet links opcionales
if ($VnetResourceId) {
    Write-Step "Creando virtual-network-links"
    foreach ($zone in $zones) {
        $linkName = "lnk-" + ($zone -replace '\.', '-')
        if ($linkName.Length -gt 80) { $linkName = $linkName.Substring(0, 80) }

        $existing = az network private-dns link vnet show --resource-group $ResourceGroupName --zone-name $zone --name $linkName --output json 2>$null
        if ($LASTEXITCODE -eq 0 -and $existing) {
            Write-Host "[skip]  $zone -> $linkName"
        } else {
            az network private-dns link vnet create `
                --resource-group $ResourceGroupName `
                --zone-name $zone `
                --name $linkName `
                --virtual-network $VnetResourceId `
                --registration-enabled false `
                --output none
            Write-Host "[ok]    $zone -> $linkName"
        }
    }
}

# Resumen
Write-Step "Listo"
$rgId = az group show --name $ResourceGroupName --query id -o tsv
Write-Host ""
Write-Host "Para usar estas zonas desde el modulo, en scenarios/arauco-dev/main.tf:" -ForegroundColor Green
Write-Host ""
Write-Host "  flag_platform_landing_zone = true"
Write-Host "  private_dns_zones = {"
Write-Host "    azure_policy_pe_zone_linking_enabled      = true"
Write-Host "    existing_zones_resource_group_resource_id = `"$rgId`""
Write-Host "  }"
Write-Host ""
