terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "7.28.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "7.28.0"
    }
  }
}

variable "region" {
  description = "Primary GCP region."
  type        = string
}

variable "gateway_project_id" {
  description = "Project 3: Central Governance & Agent Gateway Host Project ID."
  type        = string
}

variable "agent_a_project_id" {
  description = "Project 1: Coordinator Agent A Host Project ID."
  type        = string
}

variable "agent_b_project_id" {
  description = "Project 2: Specialist Agent B Host Project ID."
  type        = string
}

variable "deploy_agents" {
  description = "Whether the Reasoning Engines are deployed (Pass 2)."
  type        = bool
  default     = false
}

variable "custom_org_policy_constraint_name" {
  description = "Name of the Custom Organization Policy constraint enforcing Central Egress Gateway binding."
  type        = string
}

variable "agent_a_spiffe_principal" {
  description = "Deterministic SPIFFE IAM principal of Coordinator Agent A (Project 1)."
  type        = string
  default     = ""
}

variable "agent_a_a2a_url" {
  description = "Standard HTTPS /api/a2a/app URL for Coordinator Agent A."
  type        = string
  default     = ""
}

variable "agent_a_a2a_mtls_url" {
  description = "mTLS HTTPS /api/a2a/app URL for Coordinator Agent A."
  type        = string
  default     = ""
}

variable "agent_a_gateway_binding_id" {
  description = "Completion token for Agent A's Central Egress Gateway binding."
  type        = string
  default     = ""
}

variable "agent_b_engine_id" {
  description = "Numeric Reasoning Engine ID of Specialist Agent B (Project 2)."
  type        = string
  default     = ""
}

variable "agent_b_spiffe_principal" {
  description = "Deterministic SPIFFE IAM principal of Specialist Agent B (Project 2)."
  type        = string
  default     = ""
}

variable "agent_b_a2a_url" {
  description = "Standard HTTPS /api/a2a/app URL for Specialist Agent B."
  type        = string
  default     = ""
}

variable "agent_b_a2a_mtls_url" {
  description = "mTLS HTTPS /api/a2a/app URL for Specialist Agent B."
  type        = string
  default     = ""
}

variable "agent_b_gateway_binding_id" {
  description = "Completion token for Agent B's Central Egress Gateway binding."
  type        = string
  default     = ""
}
