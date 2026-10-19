# Helm provider's Kubernetes auth variables

variable "kube_config_path" {
  description = "Path to the kubeconfig file."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "kubectl context name to deploy into."
  type        = string
}

# Passthrough variables of the agentic-gateway-stack helm chart

variable "release_name" {
  description = "Helm release name."
  type        = string
  default     = "agentic-gateway"
}

variable "namespace" {
  description = "Kubernetes namespace to deploy into."
  type        = string
  default     = "agentic-gateway"
}

variable "create_namespace" {
  description = "Create the namespace if it does not exist."
  type        = bool
  default     = true
}

variable "values_file" {
  description = "Path to a Helm values YAML file. See the chart's values.yaml for the full schema."
  type        = string
}
