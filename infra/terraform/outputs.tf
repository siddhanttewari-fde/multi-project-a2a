output "central_egress_gateway_id" {
  description = "Full resource ID of Project 3's Central Egress Agent Gateway."
  value       = module.central_gateway.central_egress_gateway_id
}

output "agent_gateway_card" {
  description = "Output card containing Project 3's Central Egress Gateway Root CA certificates."
  value       = module.central_gateway.agent_gateway_card
}

output "custom_org_policy_constraint_name" {
  description = "Name of the Custom Organization Policy constraint enforcing Central Egress Gateway binding."
  value       = module.central_gateway.custom_org_policy_constraint_name
}

output "vpc_sc_perimeter_name" {
  description = "Resource name of the 3-project VPC Service Controls perimeter."
  value       = module.vpc_sc.perimeter_name
}

output "agent_a_artifact_registry" {
  description = "Docker repository URL in Project 1 for Coordinator Agent A."
  value       = module.agent_a_host.artifact_registry_repo_url
}

output "agent_b_artifact_registry" {
  description = "Docker repository URL in Project 2 for Specialist Agent B."
  value       = module.agent_b_host.artifact_registry_repo_url
}

output "agent_a_engine_id" {
  description = "Numeric Reasoning Engine ID of Coordinator Agent A in Project 1."
  value       = module.agent_a_host.engine_id
}

output "agent_b_engine_id" {
  description = "Numeric Reasoning Engine ID of Specialist Agent B in Project 2."
  value       = module.agent_b_host.engine_id
}

output "agent_a_spiffe_principal" {
  description = "SPIFFE IAM principal of Coordinator Agent A (Project 1)."
  value       = module.agent_a_host.spiffe_principal
}

output "agent_b_spiffe_principal" {
  description = "SPIFFE IAM principal of Specialist Agent B (Project 2)."
  value       = module.agent_b_host.spiffe_principal
}

output "agent_b_a2a_endpoint_url" {
  description = "A2A HTTP passthrough endpoint URL for Specialist Agent B in Project 2."
  value       = module.agent_b_host.a2a_endpoint_url
}

output "console_links" {
  description = "Direct Google Cloud Console URLs for testing in Phase E."
  value = {
    project_3_agent_gateways = "https://console.cloud.google.com/net-services/agent-gateways/list?project=${var.gateway_project_id}"
    project_3_agent_registry = "https://console.cloud.google.com/agent-registry/agents?project=${var.gateway_project_id}"
    project_1_agent_engine   = "https://console.cloud.google.com/vertex-ai/agents/agent-engines?project=${var.agent_a_project_id}"
    project_2_agent_engine   = "https://console.cloud.google.com/vertex-ai/agents/agent-engines?project=${var.agent_b_project_id}"
  }
}
