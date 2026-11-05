locals {
  central_registry_uri = "//agentregistry.googleapis.com/projects/${var.gateway_project_id}/locations/${var.region}"
  essential_gcp_endpoints = [
    { url = "https://aiplatform.googleapis.com", protocolBinding = "HTTP_JSON" },
    { url = "https://aiplatform.mtls.googleapis.com", protocolBinding = "HTTP_JSON" },
    { url = "https://${var.region}-aiplatform.googleapis.com", protocolBinding = "HTTP_JSON" },
    { url = "https://${var.region}-aiplatform.mtls.googleapis.com", protocolBinding = "HTTP_JSON" },
    { url = "https://aiplatform.${var.region}.rep.googleapis.com", protocolBinding = "HTTP_JSON" },
    { url = "https://aiplatform.${var.region}.rep.mtls.googleapis.com", protocolBinding = "HTTP_JSON" },
    { url = "https://logging.googleapis.com", protocolBinding = "GRPC" },
    { url = "https://logging.mtls.googleapis.com", protocolBinding = "GRPC" },
    { url = "https://telemetry.googleapis.com", protocolBinding = "GRPC" },
    { url = "https://telemetry.mtls.googleapis.com", protocolBinding = "GRPC" },
    { url = "https://cloudtrace.googleapis.com", protocolBinding = "GRPC" },
    { url = "https://cloudtrace.mtls.googleapis.com", protocolBinding = "GRPC" },
    { url = "https://monitoring.googleapis.com", protocolBinding = "GRPC" },
    { url = "https://monitoring.mtls.googleapis.com", protocolBinding = "GRPC" },
    { url = "https://agentregistry.googleapis.com", protocolBinding = "HTTP_JSON" },
    { url = "https://agentregistry.mtls.googleapis.com", protocolBinding = "HTTP_JSON" },
    { url = "https://cloudresourcemanager.googleapis.com", protocolBinding = "HTTP_JSON" },
    { url = "https://cloudresourcemanager.mtls.googleapis.com", protocolBinding = "HTTP_JSON" },
    { url = "https://iamcredentials.googleapis.com", protocolBinding = "HTTP_JSON" },
    { url = "https://iamcredentials.mtls.googleapis.com", protocolBinding = "HTTP_JSON" },
    { url = "https://oauth2.googleapis.com", protocolBinding = "HTTP_JSON" },
    { url = "https://iap.googleapis.com", protocolBinding = "HTTP_JSON" },
  ]
}

# 1. Single Central Egress Agent Gateway (AGENT_TO_ANYWHERE) in Project 3
resource "google_network_services_agent_gateway" "central_egress_gw" {
  provider    = google-beta
  project     = var.gateway_project_id
  location    = var.region
  name        = "central-egress-gw"
  description = "Central Egress Agent Gateway governing cross-project A2A and LLM traffic for Project 1 and Project 2"
  protocols   = ["MCP"]
  registries  = [local.central_registry_uri]

  google_managed {
    governed_access_path = "AGENT_TO_ANYWHERE"
  }
}

# 2. IAP Request Authorization Extension (Unified Access Policy v2, failOpen = false)
resource "google_network_services_authz_extension" "iap_ext" {
  provider    = google-beta
  project     = var.gateway_project_id
  location    = var.region
  name        = "central-egress-iap-ext"
  description = "IAP UAP v2 authorization extension for Central Egress Gateway"
  service     = "iap.googleapis.com"
  fail_open   = false
  timeout     = "1s"

  metadata = var.iap_enforcement_mode == "DRY_RUN" ? {
    iapPolicyVersion   = "V2"
    iamEnforcementMode = "DRY_RUN"
    } : {
    iapPolicyVersion = "V2"
  }
}

# 3. Network Security Authz Policy attaching IAP Extension to Central Egress Gateway
resource "google_network_security_authz_policy" "iap_policy" {
  provider       = google-beta
  project        = var.gateway_project_id
  location       = var.region
  name           = "central-egress-iap-policy"
  description    = "REQUEST_AUTHZ policy delegating outbound agent access decisions to IAP UAP v2"
  policy_profile = "REQUEST_AUTHZ"
  action         = "CUSTOM"

  target {
    resources = [google_network_services_agent_gateway.central_egress_gw.id]
  }

  custom_provider {
    authz_extension {
      resources = [google_network_services_authz_extension.iap_ext.id]
    }
  }
}

# 4. Cross-Project Gateway Binding Custom Role & IAM Grants for Project 1 & Project 2 Vertex AI Service Agents
resource "google_project_iam_custom_role" "ar_agw_cross_project_sa" {
  project     = var.gateway_project_id
  role_id     = "ar_agw_cross_project_sa"
  title       = "Agent Runtime Cross-Project Agent Gateway Binder"
  description = "Allows Vertex AI Service Agents in Project 1 and Project 2 to bind Reasoning Engines to Project 3's Central Egress Gateway"
  permissions = [
    "networkservices.agentGateways.get",
    "networkservices.operations.get",
  ]
}

resource "google_project_iam_member" "agent_a_cross_project_gw_bind" {
  project = var.gateway_project_id
  role    = google_project_iam_custom_role.ar_agw_cross_project_sa.name
  member  = "serviceAccount:service-${var.agent_a_project_number}@gcp-sa-aiplatform.iam.gserviceaccount.com"
}

resource "google_project_iam_member" "agent_a_re_cross_project_gw_bind" {
  project = var.gateway_project_id
  role    = google_project_iam_custom_role.ar_agw_cross_project_sa.name
  member  = "serviceAccount:service-${var.agent_a_project_number}@gcp-sa-aiplatform-re.iam.gserviceaccount.com"
}

resource "google_project_iam_member" "agent_b_cross_project_gw_bind" {
  project = var.gateway_project_id
  role    = google_project_iam_custom_role.ar_agw_cross_project_sa.name
  member  = "serviceAccount:service-${var.agent_b_project_number}@gcp-sa-aiplatform.iam.gserviceaccount.com"
}

resource "google_project_iam_member" "agent_b_re_cross_project_gw_bind" {
  project = var.gateway_project_id
  role    = google_project_iam_custom_role.ar_agw_cross_project_sa.name
  member  = "serviceAccount:service-${var.agent_b_project_number}@gcp-sa-aiplatform-re.iam.gserviceaccount.com"
}

# 5. Control-Plane Anti-Bypass Custom Organization Policy Constraint
resource "google_org_policy_custom_constraint" "require_central_egress_gw" {
  provider       = google-beta
  parent         = "organizations/${var.org_id}"
  name           = "custom.allowlistedEgressAgentGatewaysForAgentEngine"
  display_name   = "Require Central Egress Agent Gateway for Vertex AI Agent Engine"
  description    = "Prevents creating or updating any ReasoningEngine unless its agentToAnywhereConfig is bound to Project 3's central-egress-gw."
  action_type    = "ALLOW"
  method_types   = ["CREATE", "UPDATE"]
  resource_types = ["aiplatform.googleapis.com/ReasoningEngine"]
  condition      = "resource.spec.deploymentSpec.agentGatewayConfig.agentToAnywhereConfig.agentGateway in ['${google_network_services_agent_gateway.central_egress_gw.id}']"
}

# 6. Register Essential GCP APIs (Vertex AI, Logging, Trace, Monitoring, Agent Registry) in Project 3's Agent Registry
resource "terraform_data" "essential_gcp_apis_service" {
  triggers_replace = [
    var.gateway_project_id,
    var.region,
    jsonencode(local.essential_gcp_endpoints),
  ]

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      TOKEN="$(gcloud auth print-access-token)"
      API_BASE="https://agentregistry.googleapis.com/v1alpha/projects/${var.gateway_project_id}/locations/${var.region}"
      BODY='${jsonencode({
    displayName = "Essential Google Cloud APIs"
    description = "Allowlisted Vertex AI, Cloud Logging, Cloud Trace, Cloud Monitoring, and Agent Registry endpoints for Agent Runtime workloads"
    endpointSpec = {
      type = "NO_SPEC"
    }
    interfaces = local.essential_gcp_endpoints
})}'
      HTTP_CODE="$(curl -s -o /dev/null -w "%%{http_code}" \
        -H "Authorization: Bearer $${TOKEN}" \
        -H "X-Goog-User-Project: ${var.gateway_project_id}" \
        "$${API_BASE}/services/essential-gcp-apis")"
      if [[ "$${HTTP_CODE}" == "200" ]]; then
        curl -sSf -X PATCH \
          -H "Authorization: Bearer $${TOKEN}" \
          -H "X-Goog-User-Project: ${var.gateway_project_id}" \
          -H "Content-Type: application/json" \
          -d "$${BODY}" \
          "$${API_BASE}/services/essential-gcp-apis?updateMask=displayName,description,endpointSpec,interfaces" >/dev/null
      else
        curl -sSf -X POST \
          -H "Authorization: Bearer $${TOKEN}" \
          -H "X-Goog-User-Project: ${var.gateway_project_id}" \
          -H "Content-Type: application/json" \
          -d "$${BODY}" \
          "$${API_BASE}/services?serviceId=essential-gcp-apis" >/dev/null
      fi
    EOT
}
}

# 7. Grant roles/iap.egressor on Project 3's Agent Registry to Project 1 & Project 2 Agent Runtime Principal Sets
resource "google_iap_agent_registry_iam_member" "project_a_essential_egressor" {
  provider   = google-beta
  project    = var.gateway_project_id
  location   = var.region
  role       = "roles/iap.egressor"
  member     = "principalSet://agents.global.org-${var.org_id}.system.id.goog/attribute.platformContainer/aiplatform/projects/${var.agent_a_project_number}"
  depends_on = [terraform_data.essential_gcp_apis_service]
}

resource "google_iap_agent_registry_iam_member" "project_b_essential_egressor" {
  provider   = google-beta
  project    = var.gateway_project_id
  location   = var.region
  role       = "roles/iap.egressor"
  member     = "principalSet://agents.global.org-${var.org_id}.system.id.goog/attribute.platformContainer/aiplatform/projects/${var.agent_b_project_number}"
  depends_on = [terraform_data.essential_gcp_apis_service]
}
