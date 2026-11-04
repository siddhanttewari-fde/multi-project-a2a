locals {
  image_uri = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.agent_repo.repository_id}/${var.image_name}:${var.image_tag}"
  base_env_vars = {
    GOOGLE_GENAI_USE_VERTEXAI                  = "TRUE"
    GOOGLE_CLOUD_PROJECT                       = var.project_id
    GOOGLE_CLOUD_LOCATION                      = var.region
    GOOGLE_CLOUD_AGENT_ENGINE_LOCATION         = var.region
    GOOGLE_CLOUD_AGENT_ENGINE_ENABLE_TELEMETRY = "true"
    GATEWAY_PROJECT_ID                         = var.gateway_project_id
    REGION                                     = var.region
    GEMINI_MODEL                               = var.gemini_model
    REMOTE_AGENT_B_ID                          = var.remote_agent_b_id
  }
  merged_env_vars = merge(local.base_env_vars, var.extra_env_vars)
  engine_id       = var.deploy_agent ? google_vertex_ai_reasoning_engine.agent[0].name : ""
  spiffe_principal = var.deploy_agent ? (
    "principal://agents.global.org-${var.org_id}.system.id.goog/resources/aiplatform/projects/${var.project_number}/locations/${var.region}/reasoningEngines/${google_vertex_ai_reasoning_engine.agent[0].name}"
  ) : ""
}

# 1. Artifact Registry Docker Repository (Created in Pass 1 for image push)
resource "google_artifact_registry_repository" "agent_repo" {
  project       = var.project_id
  location      = var.region
  repository_id = "agent-repo"
  description   = "Container repository for ADK Agent Runtime images with Gateway Root CA"
  format        = "DOCKER"
}

# 2. Vertex AI Reasoning Engine with AGENT_IDENTITY and PSC Interface (Created in Pass 2)
resource "google_vertex_ai_reasoning_engine" "agent" {
  count           = var.deploy_agent ? 1 : 0
  provider        = google-beta
  project         = var.project_id
  region          = var.region
  display_name    = var.agent_display_name
  description     = var.agent_description
  deletion_policy = "FORCE"

  spec {
    identity_type   = "AGENT_IDENTITY"
    agent_framework = "google-adk"

    container_spec {
      image_uri = local.image_uri
    }

    deployment_spec {
      min_instances         = 1
      max_instances         = 4
      container_concurrency = 9

      psc_interface_config {
        network_attachment = var.network_attachment_id
      }

      dynamic "env" {
        for_each = local.merged_env_vars
        content {
          name  = env.key
          value = env.value
        }
      }
    }
  }
}

# 3. Bind Cross-Project Central Egress Gateway (agentToAnywhereConfig) on Reasoning Engine
resource "terraform_data" "bind_central_egress_gateway" {
  count = var.deploy_agent ? 1 : 0

  triggers_replace = [
    google_vertex_ai_reasoning_engine.agent[0].id,
    var.central_egress_gateway_id,
    local.image_uri,
  ]

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      TOKEN="$(gcloud auth print-access-token)"
      ENGINE_URI="https://${var.region}-aiplatform.googleapis.com/v1beta1/projects/${var.project_id}/locations/${var.region}/reasoningEngines/${google_vertex_ai_reasoning_engine.agent[0].name}"
      PAYLOAD='${jsonencode({
    spec = {
      containerSpec = {
        imageUri = local.image_uri
      }
      deploymentSpec = {
        agentGatewayConfig = {
          agentToAnywhereConfig = {
            agentGateway = var.central_egress_gateway_id
          }
        }
      }
    }
})}'
      OP_NAME="$(curl -sSf -X PATCH \
        -H "Authorization: Bearer $${TOKEN}" \
        -H "X-Goog-User-Project: ${var.project_id}" \
        -H "Content-Type: application/json" \
        -d "$${PAYLOAD}" \
        "$${ENGINE_URI}?updateMask=spec.containerSpec.imageUri,spec.deploymentSpec.agentGatewayConfig" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin).get("name",""))')"
      if [[ -n "$${OP_NAME}" ]]; then
        gcloud ai operations wait "$${OP_NAME}" --region="${var.region}" --project="${var.project_id}" >/dev/null 2>&1 || true
      fi
    EOT
}
}

# 4. Grant the Agent's SPIFFE Identity Permissions to Call Gemini & Write Logs/Traces in Its Host Project
resource "google_project_iam_member" "agent_vertex_ai_user" {
  count   = var.deploy_agent ? 1 : 0
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = local.spiffe_principal
}

resource "google_project_iam_member" "agent_log_writer" {
  count   = var.deploy_agent ? 1 : 0
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = local.spiffe_principal
}

resource "google_project_iam_member" "agent_trace_writer" {
  count   = var.deploy_agent ? 1 : 0
  project = var.project_id
  role    = "roles/cloudtrace.agent"
  member  = local.spiffe_principal
}

resource "google_project_iam_member" "agent_metric_writer" {
  count   = var.deploy_agent ? 1 : 0
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = local.spiffe_principal
}
