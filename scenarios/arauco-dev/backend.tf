terraform {
  backend "azurerm" {
    # Estos valores se completan vía -backend-config en `terraform init`
    # desde el workflow de GitHub Actions, o copiando los valores que
    # imprime ./scripts/setup-tfstate-backend.ps1.
    #
    # resource_group_name  = "rg-tfstate"
    # storage_account_name = "araucotfstatedev"
    # container_name       = "tfstate"
    # key                  = "arauco-dev.tfstate"
    #
    # use_azuread_auth se activa por la variable de entorno ARM_USE_AZUREAD=true
    # use_oidc          se activa por la variable de entorno ARM_USE_OIDC=true
  }
}
