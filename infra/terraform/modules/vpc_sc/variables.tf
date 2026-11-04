terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "7.28.0"
    }
  }
}

variable "vpc_sc_policy_id" {
  description = "Numeric Access Context Manager policy ID for the organization."
  type        = string
}

variable "vpc_sc_admin_user" {
  description = "IAM principal (e.g., user:admin@domain.com) granted access inside the VPC-SC Access Level."
  type        = string
}

variable "gateway_project_number" {
  description = "Project 3 (Gateway Hub) numeric project number."
  type        = string
}

variable "agent_a_project_number" {
  description = "Project 1 (Coordinator Agent A) numeric project number."
  type        = string
}

variable "agent_b_project_number" {
  description = "Project 2 (Specialist Agent B) numeric project number."
  type        = string
}
