# ==============================================================================
# Root Terraform Orchestration: 3-Project Enterprise A2A Governance (Argolis)
# ==============================================================================
# Project 1 (`agent_a_project_id`): Coordinator ADK Agent (`coordinator-agent-a`)
# Project 2 (`agent_b_project_id`): Specialist ADK Agent (`specialist-agent-b`)
# Project 3 (`gateway_project_id`): Single Central Egress Agent Gateway + Registry + IAP UAP v2
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Per-Project Networking (VPC, /28 PSC Subnet & PSC Network Attachment)
# ------------------------------------------------------------------------------
module "gateway_networking" {
  source = "./modules/project_networking"

  project_id      = var.gateway_project_id
  project_number  = var.gateway_project_number
  region          = var.region
  psc_subnet_cidr = "10.10.0.0/28"
}

module "agent_a_networking" {
  source = "./modules/project_networking"

  project_id      = var.agent_a_project_id
  project_number  = var.agent_a_project_number
  region          = var.region
  psc_subnet_cidr = "10.10.1.0/28"
}

module "agent_b_networking" {
  source = "./modules/project_networking"

  project_id      = var.agent_b_project_id
  project_number  = var.agent_b_project_number
  region          = var.region
  psc_subnet_cidr = "10.10.2.0/28"
}

# ------------------------------------------------------------------------------
# 2. Organization-Level VPC Service Controls (VPC-SC) Perimeter Across All 3 Projects
# ------------------------------------------------------------------------------
module "vpc_sc" {
  source = "./modules/vpc_sc"

  vpc_sc_policy_id       = var.vpc_sc_policy_id
  vpc_sc_admin_user      = var.vpc_sc_admin_user
  gateway_project_number = var.gateway_project_number
  agent_a_project_number = var.agent_a_project_number
  agent_b_project_number = var.agent_b_project_number
}

# ------------------------------------------------------------------------------
# 3. Project 3: Central Egress Agent Gateway, Agent Registry, IAP UAP v2 & Custom Org Policy
# ------------------------------------------------------------------------------
module "central_gateway" {
  source = "./modules/central_gateway"

  org_id                    = var.org_id
  region                    = var.region
  gateway_project_id        = var.gateway_project_id
  gateway_project_number    = var.gateway_project_number
  agent_a_project_id        = var.agent_a_project_id
  agent_a_project_number    = var.agent_a_project_number
  agent_b_project_id        = var.agent_b_project_id
  agent_b_project_number    = var.agent_b_project_number
  network_attachment_id     = module.gateway_networking.network_attachment_id
  iap_enforcement_mode      = var.iap_enforcement_mode
  enforce_custom_org_policy = var.deploy_agents
}

# ------------------------------------------------------------------------------
# 4. Project 2: Specialist Agent B Runtime Host (Artifact Registry + Reasoning Engine)
# ------------------------------------------------------------------------------
module "agent_b_host" {
  source = "./modules/agent_runtime_host"

  org_id                    = var.org_id
  project_id                = var.agent_b_project_id
  project_number            = var.agent_b_project_number
  region                    = var.region
  gateway_project_id        = var.gateway_project_id
  central_egress_gateway_id = module.central_gateway.central_egress_gateway_id
  network_attachment_id     = module.agent_b_networking.network_attachment_id
  deploy_agent              = var.deploy_agents
  agent_display_name        = "specialist-agent-b"
  agent_description         = "Specialist ADK Agent in Project 2 serving enterprise ticket status lookups over A2A"
  image_name                = "specialist-agent"
  image_tag                 = var.specialist_image_tag
  gemini_model              = var.gemini_model
  remote_agent_b_id         = var.remote_agent_b_id
}

# ------------------------------------------------------------------------------
# 5. Project 1: Coordinator Agent A Runtime Host (Artifact Registry + Reasoning Engine)
# ------------------------------------------------------------------------------
module "agent_a_host" {
  source = "./modules/agent_runtime_host"

  org_id                    = var.org_id
  project_id                = var.agent_a_project_id
  project_number            = var.agent_a_project_number
  region                    = var.region
  gateway_project_id        = var.gateway_project_id
  central_egress_gateway_id = module.central_gateway.central_egress_gateway_id
  network_attachment_id     = module.agent_a_networking.network_attachment_id
  deploy_agent              = var.deploy_agents
  agent_display_name        = "coordinator-agent-a"
  agent_description         = "Coordinator ADK Agent in Project 1 delegating ticket lookups over A2A to Specialist Agent B"
  image_name                = "coordinator-agent"
  image_tag                 = var.coordinator_image_tag
  gemini_model              = var.gemini_model
  remote_agent_b_id         = var.remote_agent_b_id
}

# ------------------------------------------------------------------------------
# 6. Cross-Project A2A Registration in Project 3 & SPIFFE IAM Bindings
# ------------------------------------------------------------------------------
module "a2a_governance" {
  source = "./modules/a2a_governance"

  region                            = var.region
  gateway_project_id                = var.gateway_project_id
  agent_a_project_id                = var.agent_a_project_id
  agent_b_project_id                = var.agent_b_project_id
  deploy_agents                     = var.deploy_agents
  custom_org_policy_constraint_name = module.central_gateway.custom_org_policy_constraint_name
  agent_a_spiffe_principal          = module.agent_a_host.spiffe_principal
  agent_a_a2a_url                   = module.agent_a_host.a2a_endpoint_url
  agent_a_a2a_mtls_url              = module.agent_a_host.a2a_mtls_endpoint_url
  agent_a_gateway_binding_id        = module.agent_a_host.gateway_binding_id
  agent_b_engine_id                 = module.agent_b_host.engine_id
  agent_b_spiffe_principal          = module.agent_b_host.spiffe_principal
  agent_b_a2a_url                   = module.agent_b_host.a2a_endpoint_url
  agent_b_a2a_mtls_url              = module.agent_b_host.a2a_mtls_endpoint_url
  agent_b_gateway_binding_id        = module.agent_b_host.gateway_binding_id
}
