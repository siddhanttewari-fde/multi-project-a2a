locals {
  restricted_services = [
    "aiplatform.googleapis.com",
    "artifactregistry.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com",
  ]
}

resource "google_access_context_manager_access_level" "admin_access" {
  parent      = "accessPolicies/${var.vpc_sc_policy_id}"
  name        = "accessPolicies/${var.vpc_sc_policy_id}/accessLevels/a2a_admin_access"
  title       = "A2A Enterprise Admin & Platform Build Access"
  description = "Allows the designated Argolis administrator and project Cloud Build / Vertex AI service agents to interact with resources inside the 3-project A2A perimeter."

  basic {
    conditions {
      members = [
        var.vpc_sc_admin_user,
        "serviceAccount:${var.gateway_project_number}-compute@developer.gserviceaccount.com",
        "serviceAccount:${var.agent_a_project_number}-compute@developer.gserviceaccount.com",
        "serviceAccount:${var.agent_b_project_number}-compute@developer.gserviceaccount.com",
        "serviceAccount:service-${var.agent_a_project_number}@gcp-sa-aiplatform.iam.gserviceaccount.com",
        "serviceAccount:service-${var.agent_b_project_number}@gcp-sa-aiplatform.iam.gserviceaccount.com",
        "serviceAccount:service-${var.agent_a_project_number}@gcp-sa-aiplatform-re.iam.gserviceaccount.com",
        "serviceAccount:service-${var.agent_b_project_number}@gcp-sa-aiplatform-re.iam.gserviceaccount.com",
      ]
    }
  }
}

resource "google_access_context_manager_service_perimeter" "a2a_perimeter" {
  parent         = "accessPolicies/${var.vpc_sc_policy_id}"
  name           = "accessPolicies/${var.vpc_sc_policy_id}/servicePerimeters/a2a_enterprise_perimeter"
  title          = "3-Project A2A Agent Gateway Perimeter"
  description    = "VPC-SC perimeter enclosing Project 1 (Agent A), Project 2 (Agent B), and Project 3 (Central Egress Gateway)."
  perimeter_type = "PERIMETER_TYPE_REGULAR"

  status {
    resources = [
      "projects/${var.gateway_project_number}",
      "projects/${var.agent_a_project_number}",
      "projects/${var.agent_b_project_number}",
    ]

    access_levels = [
      google_access_context_manager_access_level.admin_access.name,
    ]

    restricted_services = local.restricted_services

    vpc_accessible_services {
      enable_restriction = true
      allowed_services   = ["RESTRICTED-SERVICES"]
    }

    ingress_policies {
      ingress_from {
        identity_type = "ANY_IDENTITY"
        sources {
          access_level = "*"
        }
      }
      ingress_to {
        resources = ["*"]
        dynamic "operations" {
          for_each = local.restricted_services
          content {
            service_name = operations.value
            method_selectors {
              method = "*"
            }
          }
        }
      }
    }

    egress_policies {
      egress_from {
        identity_type = "ANY_IDENTITY"
      }
      egress_to {
        resources = ["*"]
        dynamic "operations" {
          for_each = local.restricted_services
          content {
            service_name = operations.value
            method_selectors {
              method = "*"
            }
          }
        }
      }
    }
  }
}
