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
    displayName = "specialist_agent_b"
    description = "Specialist agent hosted in Project 2 that retrieves enterprise governance ticket statuses over the Agent-to-Agent (A2A) protocol."
    agentSpec = {
      type = "A2A_AGENT_CARD"
      content = {
        name               = "specialist_agent_b"
        description        = "Specialist agent hosted in Project 2 that retrieves enterprise governance ticket statuses over the Agent-to-Agent (A2A) protocol."
        version            = "0.1.0"
        protocolVersion    = "0.3.0"
        preferredTransport = "JSONRPC"
        url                = var.agent_b_a2a_url
        additionalInterfaces = [
          {
            url       = var.agent_b_a2a_mtls_url
            transport = "JSONRPC"
          }
        ]
        capabilities = {
          streaming = true
        }
        defaultInputModes  = ["text/plain"]
        defaultOutputModes = ["text/plain"]
        skills = [
          {
            id          = "get_ticket_status"
            name        = "get_ticket_status"
            description = "Return the deterministic governance status for an enterprise ticket."
            tags        = ["governance", "tickets"]
          }
        ]
      }
    }
    interfaces = []
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

# 3. Register Coordinator Agent A (Project 1) in Project 3's Central Agent Registry
resource "terraform_data" "register_coordinator_agent_a" {
  count = var.deploy_agents ? 1 : 0

  triggers_replace = [
    var.gateway_project_id,
    var.region,
    var.agent_a_a2a_url,
    var.agent_a_a2a_mtls_url,
  ]

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      TOKEN="$(gcloud auth print-access-token)"
      API_BASE="https://agentregistry.googleapis.com/v1alpha/projects/${var.gateway_project_id}/locations/${var.region}"
      BODY='${jsonencode({
    displayName = "coordinator_agent_a"
    description = "Coordinator agent hosted in Project 1 that resolves Specialist Agent B in Project 3 Central Agent Registry and delegates enterprise ticket status lookups across projects over A2A."
    agentSpec = {
      type = "A2A_AGENT_CARD"
      content = {
        name               = "coordinator_agent_a"
        description        = "Coordinator agent hosted in Project 1 that resolves Specialist Agent B in Project 3 Central Agent Registry and delegates enterprise ticket status lookups across projects over A2A."
        version            = "0.1.0"
        protocolVersion    = "0.3.0"
        preferredTransport = "JSONRPC"
        url                = var.agent_a_a2a_url
        additionalInterfaces = [
          {
            url       = var.agent_a_a2a_mtls_url
            transport = "JSONRPC"
          }
        ]
        capabilities = {
          streaming = true
        }
        defaultInputModes  = ["text/plain"]
        defaultOutputModes = ["text/plain"]
        skills = [
          {
            id          = "delegate_ticket_lookup"
            name        = "delegate_ticket_lookup"
            description = "Delegate enterprise ticket lookups to Specialist Agent B over A2A."
            tags        = ["coordinator", "a2a"]
          }
        ]
      }
    }
    interfaces = []
})}'
      HTTP_CODE="$(curl -s -o /dev/null -w "%%{http_code}" \
        -H "Authorization: Bearer $${TOKEN}" \
        -H "X-Goog-User-Project: ${var.gateway_project_id}" \
        "$${API_BASE}/services/coordinator-agent-a")"
      if [[ "$${HTTP_CODE}" == "200" ]]; then
        curl -sSf -X PATCH \
          -H "Authorization: Bearer $${TOKEN}" \
          -H "X-Goog-User-Project: ${var.gateway_project_id}" \
          -H "Content-Type: application/json" \
          -d "$${BODY}" \
          "$${API_BASE}/services/coordinator-agent-a?updateMask=displayName,description,agentSpec,interfaces" >/dev/null
      else
        curl -sSf -X POST \
          -H "Authorization: Bearer $${TOKEN}" \
          -H "X-Goog-User-Project: ${var.gateway_project_id}" \
          -H "Content-Type: application/json" \
          -d "$${BODY}" \
          "$${API_BASE}/services?serviceId=coordinator-agent-a" >/dev/null
      fi
    EOT
}
}

# 4. Grant Agent A's SPIFFE Identity `roles/agentregistry.viewer` in Project 3 for Identifier Discovery
resource "google_project_iam_member" "agent_a_registry_viewer" {
  count   = var.deploy_agents ? 1 : 0
  project = var.gateway_project_id
  role    = "roles/agentregistry.viewer"
  member  = var.agent_a_spiffe_principal
}

# 5. Grant Agent A and Agent B SPIFFE Identities `roles/iap.egressor` in Project 3's Agent Registry (UAP v2)
resource "google_iap_agent_registry_iam_member" "agent_a_to_agent_b_egressor" {
  count      = var.deploy_agents ? 1 : 0
  provider   = google-beta
  project    = var.gateway_project_id
  location   = var.region
  role       = "roles/iap.egressor"
  member     = var.agent_a_spiffe_principal
  depends_on = [terraform_data.register_specialist_agent_b]
}

resource "google_iap_agent_registry_iam_member" "agent_b_egressor" {
  count      = var.deploy_agents ? 1 : 0
  provider   = google-beta
  project    = var.gateway_project_id
  location   = var.region
  role       = "roles/iap.egressor"
  member     = var.agent_b_spiffe_principal
  depends_on = [terraform_data.register_specialist_agent_b]
}

# 6. Resource-Scoped IAM: Grant `agentInvoker` on Agent B (Project 2) EXCLUSIVELY to Agent A's SPIFFE ID
resource "google_vertex_ai_reasoning_engine_iam_member" "agent_a_invokes_agent_b" {
  count            = var.deploy_agents ? 1 : 0
  provider         = google-beta
  project          = var.agent_b_project_id
  region           = var.region
  reasoning_engine = var.agent_b_engine_id
  role             = google_project_iam_custom_role.agent_invoker.name
  member           = var.agent_a_spiffe_principal
}

# 7. Attach Custom Organization Policy on Project 1 and Project 2 After Both Engines Bind to Central Egress Gateway
resource "terraform_data" "wait_for_gateway_bindings" {
  count = var.deploy_agents ? 1 : 0

  triggers_replace = [
    var.agent_a_gateway_binding_id,
    var.agent_b_gateway_binding_id,
  ]
}

resource "google_org_policy_policy" "enforce_egress_gw_project_a" {
  count    = var.deploy_agents ? 1 : 0
  provider = google-beta
  parent   = "projects/${var.agent_a_project_id}"
  name     = "projects/${var.agent_a_project_id}/policies/${var.custom_org_policy_constraint_name}"

  spec {
    rules {
      enforce = "TRUE"
    }
  }

  depends_on = [terraform_data.wait_for_gateway_bindings]
}

resource "google_org_policy_policy" "enforce_egress_gw_project_b" {
  count    = var.deploy_agents ? 1 : 0
  provider = google-beta
  parent   = "projects/${var.agent_b_project_id}"
  name     = "projects/${var.agent_b_project_id}/policies/${var.custom_org_policy_constraint_name}"

  spec {
    rules {
      enforce = "TRUE"
    }
  }

  depends_on = [terraform_data.wait_for_gateway_bindings]
}
