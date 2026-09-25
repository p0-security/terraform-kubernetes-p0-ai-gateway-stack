locals {
  # Pinned chart version for this module release. Update in lockstep with
  # module version tags — see the compatibility matrix in README.md.
  chart_version = "0.14.0"
}

resource "helm_release" "ai_gateway_stack" {
  name             = var.release_name
  namespace        = var.namespace
  create_namespace = var.create_namespace

  repository = "oci://registry-1.docker.io/p0security"
  chart      = "ai-gateway-stack"
  version    = local.chart_version

  timeout = var.timeout
  wait    = var.wait

  values = var.values
}

# Keeps consumers on a no-op plan when they swap `source` to this module: without
# these, each resource rename reads as a destroy/create of the whole release.
# Chained deliberately — Terraform resolves the hops transitively, so a state
# written by any published lineage lands on the current address:
#   p0-oauthed-mcp (<= 0.1.9) -> p0-agentic-gateway-stack (0.2.x) -> this module.
moved {
  from = helm_release.oauthed_mcp
  to   = helm_release.p0_agentic_gateway_stack
}

moved {
  from = helm_release.p0_agentic_gateway_stack
  to   = helm_release.ai_gateway_stack
}
