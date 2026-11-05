locals {
  image_uri = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.agent_repo.repository_id}/${var.image_name}:${var.image_tag}"
  # Note: GOOGLE_CLOUD_PROJECT, GOOGLE_CLOUD_AGENT_ENGINE_ID, and
  # GOOGLE_CLOUD_AGENT_ENGINE_LOCATION are automatically injected by Vertex AI
  # Agent Runtime and are reserved (must not be specified in deployment_spec.env).
  base_env_vars = {
    GOOGLE_GENAI_USE_VERTEXAI                  = "TRUE"
    GOOGLE_CLOUD_LOCATION                      = "global"
    GOOGLE_CLOUD_AGENT_ENGINE_ENABLE_TELEMETRY = "true"
    GOOGLE_API_USE_CLIENT_CERTIFICATE          = "false"
    GOOGLE_API_USE_MTLS_ENDPOINT               = "never"
    GATEWAY_PROJECT_ID                         = var.gateway_project_id
    REGION                                     = var.region
    GEMINI_MODEL                               = var.gemini_model
    REMOTE_AGENT_B_ID                          = var.remote_agent_b_id
  }
  merged_env_vars = merge(local.base_env_vars, var.extra_env_vars)
  adk_class_methods = jsonencode([
    { name = "get_session", api_mode = "" },
    { name = "list_sessions", api_mode = "" },
    { name = "create_session", api_mode = "" },
    { name = "delete_session", api_mode = "" },
    { name = "async_get_session", api_mode = "async" },
    { name = "async_list_sessions", api_mode = "async" },
    { name = "async_create_session", api_mode = "async" },
    { name = "async_delete_session", api_mode = "async" },
    { name = "async_add_session_to_memory", api_mode = "async" },
    { name = "async_search_memory", api_mode = "async" },
    { name = "stream_query", api_mode = "stream" },
    { name = "async_stream_query", api_mode = "async_stream" },
    { name = "streaming_agent_run_with_events", api_mode = "async_stream" },
  ])
  engine_id = var.deploy_agent ? google_vertex_ai_reasoning_engine.agent[0].name : ""
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

resource "google_artifact_registry_repository_iam_member" "aiplatform_sa_repo_reader" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.agent_repo.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:service-${var.project_number}@gcp-sa-aiplatform.iam.gserviceaccount.com"
}

resource "google_artifact_registry_repository_iam_member" "aiplatform_re_sa_repo_reader" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.agent_repo.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:service-${var.project_number}@gcp-sa-aiplatform-re.iam.gserviceaccount.com"
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
    class_methods   = local.adk_class_methods

    container_spec {
      image_uri = local.image_uri
    }

    deployment_spec {
      min_instances         = 1
      max_instances         = 4
      container_concurrency = 9

      dynamic "env" {
        for_each = local.merged_env_vars
        content {
          name  = env.key
          value = env.value
        }
      }
    }
  }

  depends_on = [
    google_artifact_registry_repository_iam_member.aiplatform_sa_repo_reader,
    google_artifact_registry_repository_iam_member.aiplatform_re_sa_repo_reader,
  ]

  lifecycle {
    ignore_changes = [
      spec[0].deployment_spec[0].env,
    ]
  }
}

# 3. Bind Cross-Project Central Egress Gateway (agentToAnywhereConfig) on Reasoning Engine
resource "terraform_data" "bind_central_egress_gateway" {
  count = var.deploy_agent ? 1 : 0

  triggers_replace = [
    google_vertex_ai_reasoning_engine.agent[0].id,
    var.central_egress_gateway_id,
    local.image_uri,
    jsonencode(local.merged_env_vars),
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
        env = [for k, v in local.merged_env_vars : { name = k, value = v }]
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
        "$${ENGINE_URI}?updateMask=spec.containerSpec.imageUri,spec.deploymentSpec.env,spec.deploymentSpec.agentGatewayConfig" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin).get("name",""))')"
      if [[ -n "$${OP_NAME}" ]]; then
        for _ in $(seq 1 60); do
          TOKEN="$(gcloud auth print-access-token)"
          OP_JSON="$(curl -sSf -H "Authorization: Bearer $${TOKEN}" -H "X-Goog-User-Project: ${var.project_id}" "https://${var.region}-aiplatform.googleapis.com/v1beta1/$${OP_NAME}")"
          DONE="$(echo "$${OP_JSON}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("done", False))')"
          if [[ "$${DONE}" == "True" ]]; then
            ERR="$(echo "$${OP_JSON}" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin).get("error", {})))')"
            if [[ "$${ERR}" != "{}" ]]; then
              echo "ERROR binding gateway: $${ERR}" >&2
              exit 1
            fi
            break
          fi
          sleep 10
        done
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

resource "google_project_iam_member" "agent_service_usage_consumer" {
  count   = var.deploy_agent ? 1 : 0
  project = var.project_id
  role    = "roles/serviceusage.serviceUsageConsumer"
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
