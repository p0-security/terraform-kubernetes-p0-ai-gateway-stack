output "release_name" {
  description = "Name of the Helm release."
  value       = helm_release.ai_gateway_stack.name
}

output "namespace" {
  description = "Kubernetes namespace the release was deployed into."
  value       = helm_release.ai_gateway_stack.namespace
}

output "chart_version" {
  description = "Version of the chart that was deployed."
  value       = var.chart_version
}
