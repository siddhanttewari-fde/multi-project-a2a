output "artifact_registry_repo_url" {
  description = "Docker repository URL in Artifact Registry."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.agent_repo.repository_id}"
}

output "engine_id" {
  description = "Numeric ID of the deployed Vertex AI Reasoning Engine."
  value       = local.engine_id
}

output "engine_resource_name" {
  description = "Full resource name of the deployed Vertex AI Reasoning Engine."
  value       = var.deploy_agent ? google_vertex_ai_reasoning_engine.agent[0].id : ""
}

output "spiffe_principal" {
  description = "Deterministic SPIFFE IAM principal assigned to the Reasoning Engine."
  value       = local.spiffe_principal
}

output "a2a_endpoint_url" {
  description = "Standard HTTPS A2A passthrough endpoint URL for the Reasoning Engine."
  value = var.deploy_agent ? (
    "https://${var.region}-aiplatform.googleapis.com/reasoningEngines/v1/projects/${var.project_number}/locations/${var.region}/reasoningEngines/${local.engine_id}/api/a2a/app"
  ) : ""
}

output "a2a_mtls_endpoint_url" {
  description = "mTLS HTTPS A2A passthrough endpoint URL for the Reasoning Engine."
  value = var.deploy_agent ? (
    "https://${var.region}-aiplatform.mtls.googleapis.com/reasoningEngines/v1/projects/${var.project_number}/locations/${var.region}/reasoningEngines/${local.engine_id}/api/a2a/app"
  ) : ""
}

output "gateway_binding_id" {
  description = "Completion token for the cross-project Central Egress Gateway binding."
  value       = var.deploy_agent ? terraform_data.bind_central_egress_gateway[0].id : ""
}
