terraform {
  required_version = ">= 1.9, < 2.0"

  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.21"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "azurerm" {
  storage_use_azuread = true
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    virtual_machine {
      delete_os_disk_on_deletion = true
    }
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }
  }
}

data "azurerm_client_config" "current" {}

## Section to provide a random Azure region for the resource group
# This allows us to randomize the region for the resource group.
module "regions" {
  source  = "Azure/avm-utl-regions/azurerm"
  version = "0.9.2"
}

# This allows us to randomize the region for the resource group.
resource "random_integer" "region_index" {
  max = length(module.regions.regions) - 1
  min = 0
}
## End of section to provide a random Azure region for the resource group

# Sufijo aleatorio para garantizar unicidad global de nombres (storage, kv, cosmos, etc.)
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
  numeric = true
}

locals {
  prefix = "saba"
  suffix = random_string.suffix.result
}

# This ensures we have unique CAF compliant names for our resources.
module "naming" {
  source  = "Azure/naming/azurerm"
  version = "0.4.2"
}


module "test" {
  source = "../../"

  location            = "eastus2"
  resource_group_name = "rg-${local.prefix}-lab"
  vnet_definition = {
    name          = "vnet-${local.prefix}-lab"
    address_space = ["10.220.164.0/24"]
    subnets = {
      AIFoundrySubnet = {
        name           = "snet-${local.prefix}-foundry"
        address_prefix = "10.220.164.0/26" # .0   - .63
      }
      PrivateEndpointSubnet = {
        name           = "snet-${local.prefix}-pep"
        address_prefix = "10.220.164.64/26" # .64  - .127
      }
      APIMSubnet = {
        name           = "snet-${local.prefix}-apim"
        address_prefix = "10.220.164.128/27" # .128 - .159
      }
      JumpboxSubnet = {
        name           = "snet-${local.prefix}-jump"
        address_prefix = "10.220.164.160/29" # .160 - .167
      }
      DevOpsBuildSubnet = {
        name           = "snet-${local.prefix}-build"
        enabled        = false
        address_prefix = "10.220.164.176/28" # .176 - .191
      }
      ContainerAppEnvironmentSubnet = {
        name           = "snet-${local.prefix}-aca"
        enabled        = false
        address_prefix = "10.220.164.192/27" # .192 - .223
      }
      AppGatewaySubnet = {
        name           = "snet-${local.prefix}-agw"
        enabled        = false
        address_prefix = "10.220.164.224/27" # .224 - .255
      }
    }
  }

  ai_foundry_definition = {
    purge_on_destroy = true
    ai_foundry = {
      name                          = "${local.prefix}-foundry-${local.suffix}"
      allow_project_management      = true
      create_ai_agent_service       = true
      sku                           = "S0"
      private_dns_zone_resource_ids = ["/subscriptions/4c7ae2e2-8d3e-4712-9b7d-04ccbdcc7e70/resourceGroups/rg-tfstate/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com", "/subscriptions/4c7ae2e2-8d3e-4712-9b7d-04ccbdcc7e70/resourceGroups/rg-tfstate/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com", "/subscriptions/4c7ae2e2-8d3e-4712-9b7d-04ccbdcc7e70/resourceGroups/rg-tfstate/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com"]
      role_assignments              = {}
      enable_diagnostic_settings    = false
    }

    ai_model_deployments = {
      "gpt-4.1" = {
        name = "gpt-4.1"
        model = {
          format  = "OpenAI"
          name    = "gpt-4.1"
          version = "2025-04-14"
        }
        scale = {
          type     = "GlobalStandard"
          capacity = 1
        }
      }
    }
    ai_projects = {
      project_1 = {
        name                       = "${local.prefix}-foundry-models"
        description                = "Saba Lab Foundry Models"
        display_name               = "Saba Lab Foundry Models"
        create_project_connections = true
        cosmos_db_connection = {
          new_resource_map_key = "cosmos1"
        }
        ai_search_connection = {
          new_resource_map_key = "search1"
        }
        storage_account_connection = {
          new_resource_map_key = "storage1"
        }
        role_assignments = {}
      }
    }

    ai_search_definition = {
      search1 = {
        name                       = "${local.prefix}-search-${local.suffix}"
        sku                        = "standard"
        semantic_search_sku        = "standard"
        semantic_search_enabled    = false
        hosting_mode               = "default"
        enable_diagnostic_settings = false
        enable_telemetry           = true
        role_assignments           = {}
      }
    }

    cosmosdb_definition = {
      cosmos1 = {
        name                          = "${local.prefix}-cosmos-${local.suffix}"
        public_network_access_enabled = false
        analytical_storage_enabled    = true
        automatic_failover_enabled    = true
        local_authentication_disabled = true
        enable_diagnostic_settings    = false
        consistency_policy = {
          consistency_level = "Session"
        }
        role_assignments = {}
      }
    }

    key_vault_definition = {
      kv1 = {
        name                       = "${local.prefix}-kv-${local.suffix}"
        sku                        = "standard"
        enable_diagnostic_settings = false
        role_assignments           = {}
      }
    }

    storage_account_definition = {
      storage1 = {
        name                       = "${local.prefix}${local.suffix}sa"
        account_kind               = "StorageV2"
        account_tier               = "Standard"
        account_replication_type   = "LRS"
        access_tier                = "Hot"
        shared_access_key_enabled  = true
        enable_diagnostic_settings = false
        endpoints = {
          blob = {
            type = "blob"
          }
        }
        role_assignments = {}
      }
    }

  }

  apim_definition = {
    deploy_sample_apis = true
    deploy             = true
    name               = "${local.prefix}-apim-${local.suffix}"
    publisher_email    = "admin@${local.prefix}.local"
    publisher_name     = "Saba Lab"
    sku_root           = "Developer"
    sku_capacity       = 1

    # revisar vnet integration
  }

  app_gateway_definition = {
    deploy = false
    backend_address_pools = {
      example_pool = {
        name = "example-backend-pool"
      }
    }

    backend_http_settings = {
      example_http_settings = {
        name     = "example-http-settings"
        port     = 80
        protocol = "Http"
      }
    }

    frontend_ports = {
      example_frontend_port = {
        name = "example-frontend-port"
        port = 80
      }
    }

    http_listeners = {
      example_listener = {
        name               = "example-listener"
        frontend_port_name = "example-frontend-port"
      }
    }

    request_routing_rules = {
      example_rule = {
        name                       = "example-rule"
        rule_type                  = "Basic"
        http_listener_name         = "example-listener"
        backend_address_pool_name  = "example-backend-pool"
        backend_http_settings_name = "example-http-settings"
        priority                   = 100
      }
    }
  }
  bastion_definition = {

  }
  container_app_environment_definition = {
    deploy                     = false
    enable_diagnostic_settings = false
  }
  enable_telemetry           = var.enable_telemetry
  flag_platform_landing_zone = true
  genai_app_configuration_definition = {
    enable_diagnostic_settings = false
  }
  genai_container_registry_definition = {
    deploy                     = false
    enable_diagnostic_settings = false
  }
  genai_cosmosdb_definition = {
    deploy            = false
    consistency_level = "Session"
  }
  genai_key_vault_definition = {
    deploy                        = false
    public_network_access_enabled = false # configured for testing
  }
  genai_storage_account_definition = {
    deploy = false
  }
  ks_ai_search_definition = {
    deploy                     = false
    enable_diagnostic_settings = false
  }
  ks_bing_grounding_definition = {
    deploy = false
  }
  waf_policy_definition = {
    deploy = false
  }
  private_dns_zones = {
    azure_policy_pe_zone_linking_enabled      = true
    existing_zones_resource_group_resource_id = "/subscriptions/4c7ae2e2-8d3e-4712-9b7d-04ccbdcc7e70/resourceGroups/rg-tfstate"
  }
}
