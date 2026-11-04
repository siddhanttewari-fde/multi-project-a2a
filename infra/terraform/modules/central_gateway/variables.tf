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

variable "org_id" {
  description = "Numeric GCP Organization ID."
  type        = string
}

variable "region" {
  description = "GCP region for the Central Egress Gateway and Agent Registry."
  type        = string
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

variable "network_attachment_id" {
  description = "Full resource ID of Project 3's PSC network attachment."
  type        = string
}

variable "iap_enforcement_mode" {
  description = "IAP Unified Access Policy enforcement mode (DRY_RUN or ENFORCED)."
  type        = string
  default     = "DRY_RUN"
}

variable "enforce_custom_org_policy" {
  description = "Whether to attach the custom.allowlistedEgressAgentGatewaysForAgentEngine Org Policy to Projects 1 and 2."
  type        = bool
  default     = false
}
