resource "google_compute_network" "agent_vpc" {
  project                 = var.project_id
  name                    = "agent-vpc"
  auto_create_subnetworks = false
  description             = "Dedicated VPC for Agent Runtime & Agent Gateway PSC Interface"
}

resource "google_compute_subnetwork" "agent_psc_subnet" {
  project                  = var.project_id
  name                     = "agent-psc-subnet"
  region                   = var.region
  network                  = google_compute_network.agent_vpc.id
  ip_cidr_range            = var.psc_subnet_cidr
  private_ip_google_access = true
  description              = "Dedicated /28 subnet for Private Service Connect network attachment"
}

resource "google_compute_network_attachment" "agent_psc_attachment" {
  project               = var.project_id
  name                  = "agent-psc-attachment"
  region                = var.region
  connection_preference = "ACCEPT_AUTOMATIC"
  subnetworks           = [google_compute_subnetwork.agent_psc_subnet.id]
  description           = "PSC network attachment for Vertex AI Agent Runtime and Agent Gateway"
}

resource "google_project_service_identity" "aiplatform_sa" {
  provider = google-beta
  project  = var.project_id
  service  = "aiplatform.googleapis.com"
}

resource "google_project_service_identity" "networkservices_sa" {
  provider = google-beta
  project  = var.project_id
  service  = "networkservices.googleapis.com"
}

resource "google_project_iam_member" "aiplatform_network_admin" {
  project = var.project_id
  role    = "roles/compute.networkAdmin"
  member  = "serviceAccount:${google_project_service_identity.aiplatform_sa.email}"
}

resource "google_project_iam_member" "aiplatform_dns_peer" {
  project = var.project_id
  role    = "roles/dns.peer"
  member  = "serviceAccount:${google_project_service_identity.aiplatform_sa.email}"
}

resource "google_project_iam_member" "networkservices_network_admin" {
  project = var.project_id
  role    = "roles/compute.networkAdmin"
  member  = "serviceAccount:${google_project_service_identity.networkservices_sa.email}"
}
