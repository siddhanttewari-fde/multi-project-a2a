output "central_egress_gateway_id" {
  description = "Full resource ID of Project 3's Central Egress Agent Gateway."
  value       = google_network_services_agent_gateway.central_egress_gw.id
}

output "central_egress_gateway_name" {
  description = "Short name of Project 3's Central Egress Agent Gateway."
  value       = google_network_services_agent_gateway.central_egress_gw.name
}

output "agent_gateway_card" {
  description = "Output card containing the Central Egress Gateway's Root CA certificates and mTLS endpoint."
  value       = google_network_services_agent_gateway.central_egress_gw.agent_gateway_card
}

output "custom_org_policy_constraint_name" {
  description = "Name of the custom Organization Policy constraint enforcing Central Egress Gateway binding."
  value       = google_org_policy_custom_constraint.require_central_egress_gw.name
}
