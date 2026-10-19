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

variable "chart_version" {
  description = "Exact version of the ai-gateway-stack chart to install, such as \"1.2.3\". See the compatibility matrix in README.md for the versions this module supports."
  type        = string
  nullable    = false

  # Exact versions only: a range would let the chart move under an unchanged plan.
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9A-Za-z.-]+)?(\\+[0-9A-Za-z.-]+)?$", var.chart_version))
    error_message = "chart_version must be an exact chart version, such as \"1.2.3\", not a range or an empty string."
  }
}

variable "values" {
  description = "List of YAML values strings merged left-to-right (last wins), equivalent to helm install -f. See the chart's values.yaml for the full schema."
  type        = list(string)
  default     = []
}

variable "timeout" {
  description = "Seconds Helm waits for an install or upgrade, hooks included. Must exceed the 300 second deadline of the chart's secrets Job so a stuck Job fails with its own error instead of a generic Helm timeout."
  type        = number
  default     = 360
  nullable    = false

  validation {
    condition     = var.timeout > 300
    error_message = "timeout must be greater than 300 seconds, the secrets Job's deadline."
  }
}

variable "wait" {
  description = "Wait for every resource to be ready before marking the release deployed. Off by default: the TLS certificate cannot issue until the DNS record for the gateway host exists, so waiting on a first install times out."
  type        = bool
  default     = false
  nullable    = false
}
