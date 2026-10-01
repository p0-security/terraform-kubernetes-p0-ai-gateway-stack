provider "helm" {
  kubernetes = {
    config_path    = var.kube_config_path
    config_context = var.kube_context
  }
}

module "ai_gateway_stack" {
  source  = "p0-security/ai-gateway-stack/kubernetes"
  version = "0.7.0"

  release_name     = var.release_name
  namespace        = var.namespace
  create_namespace = var.create_namespace
  values           = [file(var.values_file)]
}

output "release_name" { value = module.ai_gateway_stack.release_name }
output "namespace" { value = module.ai_gateway_stack.namespace }
output "chart_version" { value = module.ai_gateway_stack.chart_version }
