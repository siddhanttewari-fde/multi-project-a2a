# 1. Least-Privilege Custom Role `agentInvoker` in Project 2 (Specialist Agent Host)
resource "google_project_iam_custom_role" "agent_invoker" {
  project     = var.agent_b_project_id
  role_id     = "agentInvoker"
  title       = "Vertex AI Reasoning Engine A2A Invoker"
  description = "Least-privilege role allowing an authorized remote SPIFFE agent identity to query a Reasoning Engine over A2A."
  permissions = [
    "aiplatform.reasoningEngines.get",
    "aiplatform.reasoningEngines.query",
  ]
}

# 2. Register Specialist Agent B (Project 2) in Project 3's Central Agent Registry
resource "terraform_data" "register_specialist_agent_b" {
  count = var.deploy_agents ? 1 : 0

  triggers_replace = [
    var.gateway_project_id,
    var.region,
    var.agent_b_a2a_url,
    var.agent_b_a2a_mtls_url,
  ]

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      TOKEN="$(gcloud auth print-access-token)"
      API_BASE="https://agentregistry.googleapis.com/v1alpha/projects/${var.gateway_project_id}/locations/${var.region}"
      BODY='${jsonencode({
    displayName = "Specialist Agent B (Project 2)"
    description = "Enterprise ticket status specialist agent hosted in Project 2 and exposed over A2A"
    agentSpec = {
      type = "NO_SPEC"
    }
    interfaces = [
      {
        url             = var.agent_b_a2a_url
        protocolBinding = "JSONRPC"
      },
      {
        url             = var.agent_b_a2a_mtls_url
        protocolBinding = "JSONRPC"
      },
    ]
})}'
      HTTP_CODE="$(curl -s -o /dev/null -w "%%{http_code}" \
        -H "Authorization: Bearer $${TOKEN}" \
        -H "X-Goog-User-Project: ${var.gateway_project_id}" \
        "$${API_BASE}/services/specialist-agent-b")"
      if [[ "$${HTTP_CODE}" == "200" ]]; then
        curl -sSf -X PATCH \
          -H "Authorization: Bearer $${TOKEN}" \
          -H "X-Goog-User-Project: ${var.gateway_project_id}" \
          -H "Content-Type: application/json" \
          -d "$${BODY}" \
          "$${API_BASE}/services/specialist-agent-b?updateMask=displayName,description,agentSpec,interfaces" >/dev/null
      else
        curl -sSf -X POST \
          -H "Authorization: Bearer $${TOKEN}" \
          -H "X-Goog-User-Project: ${var.gateway_project_id}" \
          -H "Content-Type: application/json" \
          -d "$${BODY}" \
          "$${API_BASE}/services?serviceId=specialist-agent-b" >/dev/null
      fi
    EOT
}
}

# 3. Grant Agent A's SPIFFE Identity `roles/agentregistry.viewer` in Project 3 for Identifier Discovery
resource "google_project_iam_member" "agent_a_registry_viewer" {
  count   = var.deploy_agents ? 1 : 0
  project = var.gateway_project_id
  role    = "roles/agentregistry.viewer"
  member  = var.agent_a_spiffe_principal
}

# 4. Grant Agent A's SPIFFE Identity `roles/iap.egressor` in Project 3's Agent Registry (UAP v2)
resource "google_iap_agent_registry_iam_member" "agent_a_to_agent_b_egressor" {
  count      = var.deploy_agents ? 1 : 0
  provider   = google-beta
  project    = var.gateway_project_id
  location   = var.region
  role       = "roles/iap.egressor"
  member     = var.agent_a_spiffe_principal
  depends_on = [terraform_data.register_specialist_agent_b]
}

# 5. Resource-Scoped IAM: Grant `agentInvoker` on Agent B (Project 2) EXCLUSIVELY to Agent A's SPIFFE ID
resource "google_vertex_ai_reasoning_engine_iam_member" "agent_a_invokes_agent_b" {
  count            = var.deploy_agents ? 1 : 0
  provider         = google-beta
  project          = var.agent_b_project_id
  region           = var.region
  reasoning_engine = var.agent_b_engine_id
  role             = google_project_iam_custom_role.agent_invoker.name
  member           = var.agent_a_spiffe_principal
}
