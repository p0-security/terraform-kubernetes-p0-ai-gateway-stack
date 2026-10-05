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
  description = "Wait for every resource to be ready before marking the release deployed. Matches the Helm provider's own default (true) — override to false only if you specifically want the apply to return without waiting on rollout."
  type        = bool
  default     = true
  nullable    = false
}
