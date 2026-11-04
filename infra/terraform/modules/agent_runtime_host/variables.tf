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

variable "project_id" {
  description = "Host GCP project ID (Project 1 or Project 2)."
  type        = string
}

variable "project_number" {
  description = "Numeric GCP project number."
  type        = string
}

variable "region" {
  description = "GCP region for Artifact Registry and Vertex AI Reasoning Engine."
  type        = string
}

variable "gateway_project_id" {
  description = "Project 3: Central Governance & Agent Gateway Host Project ID."
  type        = string
}

variable "central_egress_gateway_id" {
  description = "Full resource ID of Project 3's Central Egress Agent Gateway."
  type        = string
}

variable "network_attachment_id" {
  description = "Full resource ID of the host project's PSC network attachment."
  type        = string
}

variable "deploy_agent" {
  description = "Whether to provision the Vertex AI Reasoning Engine (Pass 2 after container image push)."
  type        = bool
  default     = false
}

variable "agent_display_name" {
  description = "Display name of the Vertex AI Reasoning Engine."
  type        = string
}

variable "agent_description" {
  description = "Description of the Vertex AI Reasoning Engine."
  type        = string
}

variable "image_name" {
  description = "Container image name inside the project's Artifact Registry repository."
  type        = string
}

variable "image_tag" {
  description = "Container image tag."
  type        = string
  default     = "latest"
}

variable "gemini_model" {
  description = "Gemini model ID injected into the agent container environment."
  type        = string
}

variable "remote_agent_b_id" {
  description = "Logical identifier of Specialist Agent B in Project 3's Central Agent Registry."
  type        = string
  default     = "agents/specialist-agent-b"
}

variable "extra_env_vars" {
  description = "Additional environment variables injected into the Reasoning Engine container."
  type        = map(string)
  default     = {}
}
