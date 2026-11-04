output "access_level_name" {
  description = "Resource name of the VPC-SC admin access level."
  value       = google_access_context_manager_access_level.admin_access.name
}

output "perimeter_name" {
  description = "Resource name of the 3-project VPC-SC service perimeter."
  value       = google_access_context_manager_service_perimeter.a2a_perimeter.name
}
