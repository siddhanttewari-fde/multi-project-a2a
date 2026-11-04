output "agent_invoker_role_name" {
  description = "Full IAM role name of the custom agentInvoker role in Project 2."
  value       = google_project_iam_custom_role.agent_invoker.name
}

output "registered_agent_b_id" {
  description = "Logical identifier of Specialist Agent B in Project 3's Central Agent Registry."
  value       = "agents/specialist-agent-b"
}
