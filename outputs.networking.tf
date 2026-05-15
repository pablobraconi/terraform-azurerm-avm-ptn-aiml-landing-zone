output "subnets" {
  description = "A map of the deployed subnets in the AI PTN LZA."
  value = { for key, value in local.deployed_subnets : key => merge(
    value,
    {
      address_prefixes = length(var.vnet_definition.existing_byo_vnet) > 0 ? module.byo_subnets[key].address_prefixes : module.ai_lz_vnet[0].subnets[key].address_prefixes
    }
  ) }
}

output "virtual_network" {
  description = "The deployed virtual network in the AI PTN LZA."
  value       = length(var.vnet_definition.existing_byo_vnet) == 0 ? module.ai_lz_vnet[0] : null
}

output "subnet_resource_ids" {
  description = "Map of subnet logical key (e.g. PrivateEndpointSubnet) to its Azure resource ID."
  value       = local.subnet_ids
}
