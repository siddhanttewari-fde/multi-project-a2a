terraform {
  required_version = ">= 1.5.0"

  backend "gcs" {}

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

provider "google" {
  region                = var.region
  user_project_override = true
  billing_project       = var.gateway_project_id
}

provider "google-beta" {
  region                = var.region
  user_project_override = true
  billing_project       = var.gateway_project_id
}
