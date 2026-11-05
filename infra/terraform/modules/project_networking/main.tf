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

resource "google_compute_router" "agent_router" {
  project = var.project_id
  name    = "agent-nat-router"
  region  = var.region
  network = google_compute_network.agent_vpc.id
}

resource "google_compute_router_nat" "agent_nat" {
  project                            = var.project_id
  name                               = "agent-cloud-nat"
  router                             = google_compute_router.agent_router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "google_project_service_identity" "aiplatform_sa" {
  provider = google-beta
  project  = var.project_id
  service  = "aiplatform.googleapis.com"
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

resource "google_project_iam_member" "aiplatform_re_network_admin" {
  project = var.project_id
  role    = "roles/compute.networkAdmin"
  member  = "serviceAccount:service-${var.project_number}@gcp-sa-aiplatform-re.iam.gserviceaccount.com"
}

resource "google_project_iam_member" "aiplatform_re_dns_peer" {
  project = var.project_id
  role    = "roles/dns.peer"
  member  = "serviceAccount:service-${var.project_number}@gcp-sa-aiplatform-re.iam.gserviceaccount.com"
}
