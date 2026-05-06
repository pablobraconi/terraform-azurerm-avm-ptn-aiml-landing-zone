<#
.SYNOPSIS
    Configura todo lo necesario en Azure para que GitHub Actions pueda
    desplegar este modulo (examples/*) usando OIDC.

.DESCRIPTION
    Crea (o reutiliza si ya existe) un App Registration + Service Principal,
    le asigna roles sobre la suscripcion, registra Federated Credentials
    para el environment y/o branch indicados, y pre-registra los Resource
    Providers que usa el modulo.

    Requiere:
      - Azure CLI (az) autenticado: az login
      - Permisos en el tenant para crear App Registrations
      - Owner / User Access Administrator sobre la suscripcion para asignar roles

.PARAMETER GitHubOwner
    Owner (usuario u organizacion) del repositorio en GitHub.

.PARAMETER GitHubRepo
    Nombre del repositorio en GitHub.

.PARAMETER SubscriptionId
    Id de la suscripcion Azure objetivo.

.PARAMETER AppName
    Nombre del App Registration. Por defecto: gh-oidc-<repo>.

.PARAMETER Environment
    Nombre del GitHub Environment a federar. Por defecto: test.

.PARAMETER Branches
    Branches a federar para workflow_dispatch / push. Por defecto: @('main').

.PARAMETER IncludePullRequest
    Si se incluye, agrega un federated credential para pull_request.

.PARAMETER GrantUserAccessAdministrator
    Si se incluye, asigna tambien el rol "User Access Administrator"
    (necesario porque el modulo crea role_assignments).

.EXAMPLE
    ./setup-github-oidc.ps1 `
        -GitHubOwner pablobraconi `
        -GitHubRepo terraform-azurerm-avm-ptn-aiml-landing-zone `
        -SubscriptionId 00000000-0000-0000-0000-000000000000 `
        -GrantUserAccessAdministrator
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GitHubOwner,

    [Parameter(Mandatory = $true)]
    [string]$GitHubRepo,

    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [string]$AppName,

    [string]$Environment = 'test',

    [string[]]$Branches = @('main'),

    [switch]$IncludePullRequest,

    [switch]$GrantUserAccessAdministrator
)

$ErrorActionPreference = 'Stop'

if (-not $AppName -or [string]::IsNullOrWhiteSpace($AppName)) {
    $AppName = "gh-oidc-$GitHubRepo"
}

function Write-Step([string]$msg) {
    Write-Host ""
    Write-Host "==> $msg" -ForegroundColor Cyan
}

# 0. Validaciones previas ------------------------------------------------------
Write-Step "Validando az CLI"
$null = & az --version 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "Azure CLI (az) no esta instalado o no esta en PATH."
}

$account = az account show --output json 2>$null | ConvertFrom-Json
if (-not $account) {
    throw "No hay sesion de az activa. Ejecuta 'az login' primero."
}

Write-Step "Seleccionando suscripcion $SubscriptionId"
az account set --subscription $SubscriptionId | Out-Null

$tenantId = (az account show --query tenantId -o tsv)
Write-Host "Tenant   : $tenantId"
Write-Host "Repo     : $GitHubOwner/$GitHubRepo"
Write-Host "App      : $AppName"
Write-Host "Env      : $Environment"
Write-Host "Branches : $($Branches -join ', ')"

# 1. App Registration + Service Principal -------------------------------------
Write-Step "Creando / reutilizando App Registration '$AppName'"
$appJson = az ad app list --display-name $AppName --output json | ConvertFrom-Json
if ($appJson.Count -gt 0) {
    $app = $appJson[0]
    Write-Host "App ya existe (appId=$($app.appId))"
} else {
    $app = az ad app create --display-name $AppName --output json | ConvertFrom-Json
    Write-Host "App creada (appId=$($app.appId))"
}
$appId = $app.appId
$appObjectId = $app.id

Write-Step "Creando / reutilizando Service Principal"
$spJson = az ad sp list --filter "appId eq '$appId'" --output json | ConvertFrom-Json
if ($spJson.Count -gt 0) {
    $sp = $spJson[0]
    Write-Host "SP ya existe (objectId=$($sp.id))"
} else {
    $sp = az ad sp create --id $appId --output json | ConvertFrom-Json
    Write-Host "SP creado (objectId=$($sp.id))"
}
$spObjectId = $sp.id

# 2. Role assignments sobre la suscripcion ------------------------------------
function Ensure-RoleAssignment {
    param(
        [string]$Role,
        [string]$Scope,
        [string]$AssigneeObjectId
    )
    $existing = az role assignment list `
        --assignee-object-id $AssigneeObjectId `
        --assignee-principal-type ServicePrincipal `
        --role $Role `
        --scope $Scope `
        --output json | ConvertFrom-Json
    if ($existing.Count -gt 0) {
        Write-Host "Role '$Role' ya asignado sobre $Scope"
        return
    }
    az role assignment create `
        --assignee-object-id $AssigneeObjectId `
        --assignee-principal-type ServicePrincipal `
        --role $Role `
        --scope $Scope | Out-Null
    Write-Host "Role '$Role' asignado sobre $Scope"
}

$scope = "/subscriptions/$SubscriptionId"

Write-Step "Asignando rol Contributor"
Ensure-RoleAssignment -Role 'Contributor' -Scope $scope -AssigneeObjectId $spObjectId

if ($GrantUserAccessAdministrator) {
    Write-Step "Asignando rol User Access Administrator (modulo crea role_assignments)"
    Ensure-RoleAssignment -Role 'User Access Administrator' -Scope $scope -AssigneeObjectId $spObjectId
} else {
    Write-Host ""
    Write-Host "AVISO: este modulo crea role_assignments. Si el plan falla con" -ForegroundColor Yellow
    Write-Host "       AuthorizationFailed al crear roleAssignments, vuelve a correr" -ForegroundColor Yellow
    Write-Host "       este script con -GrantUserAccessAdministrator." -ForegroundColor Yellow
}

# 3. Federated credentials ----------------------------------------------------
function Ensure-FederatedCredential {
    param(
        [string]$AppObjectId,
        [string]$Name,
        [string]$Subject
    )
    $existing = az ad app federated-credential list --id $AppObjectId --output json | ConvertFrom-Json
    $match = $existing | Where-Object { $_.name -eq $Name -or $_.subject -eq $Subject }
    if ($match) {
        Write-Host "Federated credential '$Name' ya existe (subject=$Subject)"
        return
    }
    $payload = @{
        name      = $Name
        issuer    = 'https://token.actions.githubusercontent.com'
        subject   = $Subject
        audiences = @('api://AzureADTokenExchange')
    } | ConvertTo-Json -Compress

    $tmp = New-TemporaryFile
    try {
        Set-Content -Path $tmp -Value $payload -Encoding utf8
        az ad app federated-credential create --id $AppObjectId --parameters "@$tmp" | Out-Null
    } finally {
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }
    Write-Host "Federated credential '$Name' creada (subject=$Subject)"
}

Write-Step "Registrando Federated Credentials"

# Environment
$envName    = "github-env-$Environment"
$envSubject = "repo:$GitHubOwner/$GitHubRepo`:environment:$Environment"
Ensure-FederatedCredential -AppObjectId $appObjectId -Name $envName -Subject $envSubject

# Branches
foreach ($branch in $Branches) {
    $brName    = "github-branch-$branch"
    $brSubject = "repo:$GitHubOwner/$GitHubRepo`:ref:refs/heads/$branch"
    Ensure-FederatedCredential -AppObjectId $appObjectId -Name $brName -Subject $brSubject
}

# Pull request (opcional)
if ($IncludePullRequest) {
    $prSubject = "repo:$GitHubOwner/$GitHubRepo`:pull_request"
    Ensure-FederatedCredential -AppObjectId $appObjectId -Name 'github-pull-request' -Subject $prSubject
}

# 4. Resource Providers --------------------------------------------------------
$providers = @(
    'Microsoft.CognitiveServices',
    'Microsoft.Search',
    'Microsoft.DocumentDB',
    'Microsoft.KeyVault',
    'Microsoft.ApiManagement',
    'Microsoft.App',
    'Microsoft.OperationalInsights',
    'Microsoft.Insights',
    'Microsoft.Network',
    'Microsoft.Compute',
    'Microsoft.Storage'
)

Write-Step "Pre-registrando Resource Providers"
foreach ($rp in $providers) {
    $state = az provider show --namespace $rp --query registrationState -o tsv 2>$null
    if ($state -eq 'Registered') {
        Write-Host "$rp : Registered"
        continue
    }
    Write-Host "$rp : registrando..."
    az provider register --namespace $rp | Out-Null
}

# 5. Resumen -------------------------------------------------------------------
Write-Step "Listo"
Write-Host ""
Write-Host "Configura estos valores como GitHub Secrets en el environment '$Environment':" -ForegroundColor Green
Write-Host ""
Write-Host "  ARM_TENANT_ID       = $tenantId"
Write-Host "  ARM_SUBSCRIPTION_ID = $SubscriptionId"
Write-Host "  ARM_CLIENT_ID       = $appId"
Write-Host ""
Write-Host "GitHub UI: Settings -> Environments -> $Environment -> Add secret"
Write-Host ""
Write-Host "O via gh CLI:" -ForegroundColor Green
Write-Host "  gh secret set ARM_TENANT_ID       --env $Environment --body $tenantId       --repo $GitHubOwner/$GitHubRepo"
Write-Host "  gh secret set ARM_SUBSCRIPTION_ID --env $Environment --body $SubscriptionId  --repo $GitHubOwner/$GitHubRepo"
Write-Host "  gh secret set ARM_CLIENT_ID       --env $Environment --body $appId           --repo $GitHubOwner/$GitHubRepo"
Write-Host ""
