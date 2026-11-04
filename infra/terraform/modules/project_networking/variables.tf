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

variable "project_id" {
  description = "Target GCP project ID for VPC and PSC network attachment."
  type        = string
}

variable "project_number" {
  description = "Numeric GCP project number."
  type        = string
}

variable "region" {
  description = "GCP region for the /28 PSC subnet and network attachment."
  type        = string
}

variable "psc_subnet_cidr" {
  description = "Dedicated /28 CIDR block for Private Service Connect Interface."
  type        = string
  default     = "10.10.0.0/28"
}
