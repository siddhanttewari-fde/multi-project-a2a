output "vpc_id" {
  description = "Full resource ID of the agent VPC."
  value       = google_compute_network.agent_vpc.id
}

output "psc_subnet_id" {
  description = "Full resource ID of the /28 PSC subnet."
  value       = google_compute_subnetwork.agent_psc_subnet.id
}

output "network_attachment_id" {
  description = "Full resource ID of the PSC network attachment."
  value       = google_compute_network_attachment.agent_psc_attachment.id
}

output "aiplatform_sa_email" {
  description = "Email of the project's Vertex AI Service Agent."
  value       = google_project_service_identity.aiplatform_sa.email
}
