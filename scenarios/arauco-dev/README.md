# arauco-dev

Despliegue real de la AI/ML Landing Zone para el ambiente **dev de Arauco**.

A diferencia de `examples/`, esta carpeta:

- **No** la ejecuta el `PR Check` de AVM.
- Sí la ejecuta [`.github/workflows/deploy-arauco-dev.yml`](../../.github/workflows/deploy-arauco-dev.yml)
  con state remoto en Azure Storage.

## Mecanismo de implementacion

```
feature/* ── PR ──▶ main
   │                 │
   │  plan en PR     │  apply automatico
   ▼                 ▼
GitHub Actions    GitHub Actions
(comenta plan)   (terraform apply)
```

1. Trabaja en una rama `feature/*` o `chore/*`.
2. Modifica `scenarios/arauco-dev/main.tf` (o cualquier `*.tf` del modulo raiz).
3. Abre un PR a `main`.
4. El workflow corre `terraform plan` y deja el resultado como comentario.
5. Al mergear a `main`, se dispara `terraform apply` automaticamente.
6. Para destruir: `Actions -> Deploy arauco-dev -> Run workflow -> action: destroy`.

## Configuracion inicial (una sola vez)

### 1. Crear el backend remoto del state

```pwsh
# Toma el objectId del SP creado por setup-github-oidc.ps1:
$spId = az ad sp list --display-name "gh-oidc-terraform-azurerm-avm-ptn-aiml-landing-zone" --query "[0].id" -o tsv

./scripts/setup-tfstate-backend.ps1 `
    -SubscriptionId 85fbd7d4-c974-44b3-8f11-47bc1d72ee5b `
    -StorageAccountName araucotfstatedev `
    -GrantSpObjectId $spId
```

> El nombre del Storage Account (`araucotfstatedev`) debe ser unico en Azure.
> Si ya existe, elige otro.

### 2. Agregar federated credential del environment `arauco-dev`

Re-ejecuta el script de OIDC apuntando al nuevo environment:

```pwsh
./scripts/setup-github-oidc.ps1 `
    -GitHubOwner pablobraconi `
    -GitHubRepo terraform-azurerm-avm-ptn-aiml-landing-zone `
    -SubscriptionId 85fbd7d4-c974-44b3-8f11-47bc1d72ee5b `
    -Environment arauco-dev `
    -GrantUserAccessAdministrator
```

Es idempotente: reutiliza el App Registration y el SP, solo agrega el
federated credential nuevo (`repo:.../...:environment:arauco-dev`).

### 3. Crear el environment `arauco-dev` en GitHub + cargar secrets / variables

```pwsh
$repo = "pablobraconi/terraform-azurerm-avm-ptn-aiml-landing-zone"

gh api -X PUT repos/$repo/environments/arauco-dev

# Secrets (mismos valores que el environment 'test'):
gh secret set ARM_TENANT_ID       --env arauco-dev --body 85fbd7d4-c974-44b3-8f11-47bc1d72ee5b --repo $repo
gh secret set ARM_SUBSCRIPTION_ID --env arauco-dev --body <subscription-id>                     --repo $repo
gh secret set ARM_CLIENT_ID       --env arauco-dev --body b076cdda-be7e-4453-af59-1659b75799f1 --repo $repo

# Variables del backend (NO secrets, valores no sensibles):
gh variable set TFSTATE_RG        --env arauco-dev --body rg-tfstate         --repo $repo
gh variable set TFSTATE_SA        --env arauco-dev --body araucotfstatedev   --repo $repo
gh variable set TFSTATE_CONTAINER --env arauco-dev --body tfstate            --repo $repo
gh variable set TFSTATE_KEY       --env arauco-dev --body arauco-dev.tfstate --repo $repo
```

## Donde defino que se despliega

Todos los parametros estan en `main.tf` de esta carpeta:

| Parametro | Donde se define |
|---|---|
| Region, RG, vnet, subnets | `module "test"` (bloque principal) |
| AI Foundry, modelos, proyectos | `ai_foundry_definition` |
| APIM, App Gateway, ACA, etc. | `apim_definition`, `app_gateway_definition`, ... |
| DNS zones existentes | `private_dns_zones.existing_zones_resource_group_resource_id` |

Cambias el archivo, lo commiteas en una rama, abres PR, revisas el `plan` y mergeas.

## Ejecucion local (debug)

Si necesitas correrlo localmente sin GitHub Actions:

```pwsh
$env:ARM_USE_AZUREAD = 'true'
az login

cd scenarios/arauco-dev
terraform init `
  -backend-config="resource_group_name=rg-tfstate" `
  -backend-config="storage_account_name=araucotfstatedev" `
  -backend-config="container_name=tfstate" `
  -backend-config="key=arauco-dev.tfstate"

terraform plan
```
