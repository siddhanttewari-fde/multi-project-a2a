variable "org_id" {
  description = "Numeric GCP Organization ID (Argolis)."
  type        = string
}

variable "region" {
  description = "Primary GCP region for Agent Runtime, Agent Gateway, and Agent Registry."
  type        = string
  default     = "us-central1"
}

variable "gateway_project_id" {
  description = "Project 3: Central Governance & Agent Gateway Host Project ID."
  type        = string
}

variable "gateway_project_number" {
  description = "Project 3: Numeric project number."
  type        = string
}

variable "agent_a_project_id" {
  description = "Project 1: Coordinator Agent A Host Project ID."
  type        = string
}

variable "agent_a_project_number" {
  description = "Project 1: Numeric project number."
  type        = string
}

variable "agent_b_project_id" {
  description = "Project 2: Specialist Agent B Host Project ID."
  type        = string
}

variable "agent_b_project_number" {
  description = "Project 2: Numeric project number."
  type        = string
}

variable "vpc_sc_policy_id" {
  description = "Numeric Access Context Manager policy ID for the organization."
  type        = string
}

variable "vpc_sc_admin_user" {
  description = "IAM principal (e.g., user:admin@domain.com) granted access inside the VPC-SC Access Level."
  type        = string
}

variable "gemini_model" {
  description = "Default Gemini model ID used by both ADK agents."
  type        = string
  default     = "gemini-2.5-flash"
}

variable "remote_agent_b_id" {
  description = "Logical identifier of Specialist Agent B in Project 3's Central Agent Registry."
  type        = string
  default     = "agents/specialist-agent-b"
}

variable "deploy_agents" {
  description = "Two-stage deployment toggle: false during Pass 1 (base infra + gateway CA generation), true during Pass 2 (after container images are built and pushed)."
  type        = bool
  default     = false
}

variable "iap_enforcement_mode" {
  description = "IAP Unified Access Policy enforcement mode on Central Egress Gateway (DRY_RUN or ENFORCED)."
  type        = string
  default     = "DRY_RUN"

  validation {
    condition     = contains(["DRY_RUN", "ENFORCED"], var.iap_enforcement_mode)
    error_message = "iap_enforcement_mode must be either DRY_RUN or ENFORCED."
  }
}

variable "coordinator_image_tag" {
  description = "Container image tag for Coordinator Agent A in Project 1's Artifact Registry."
  type        = string
  default     = "latest"
}

variable "specialist_image_tag" {
  description = "Container image tag for Specialist Agent B in Project 2's Artifact Registry."
  type        = string
  default     = "latest"
}
