locals {
  # Chart 1.1.0-beta renamed the gateway subchart's values key and Helm ignores
  # unknown keys, so callers' old key is rewritten here. Remove in a breaking release.
  values_key        = "ai-gateway"
  legacy_values_key = "agentic-gateway"

  # Strings that are not a YAML map (comment-only, empty, invalid) decode to a
  # non-map and are passed through untouched.
  decoded_values = [for v in var.values : try(yamldecode(v), null)]
  has_legacy_key = [for d in local.decoded_values : try(contains(keys(d), local.legacy_values_key), false)]
  has_both_keys  = [for i, d in local.decoded_values : local.has_legacy_key[i] && try(contains(keys(d), local.values_key), false)]

  # Only strings using the old key are re-encoded; the rest stay verbatim so
  # existing callers see no values diff. Helm deep-merges the strings afterwards.
  values = [
    for i, v in var.values : local.has_legacy_key[i] && !local.has_both_keys[i] ? yamlencode(merge(
      { for k, val in local.decoded_values[i] : k => val if k != local.legacy_values_key },
      { (local.values_key) = local.decoded_values[i][local.legacy_values_key] },
    )) : v
  ]

  # Charts after 1.2.0-beta render Valkey's claim from valkey.storageClass and
  # fail with "storageClass is required" without it. Resolve both keys the way
  # Helm does (last string that sets one wins) so plan can catch it first.
  valkey_enabled_settings       = [for d in local.decoded_values : try(d.valkey.enabled, null)]
  valkey_storage_class_settings = [for d in local.decoded_values : try(d.valkey.storageClass, null)]
  valkey_enabled                = try(reverse([for e in local.valkey_enabled_settings : e if e != null])[0], true)
  valkey_storage_class          = try(reverse([for c in local.valkey_storage_class_settings : c if c != null])[0], "")
  valkey_storage_configured     = try(local.valkey_enabled == false || trimspace(tostring(local.valkey_storage_class)) != "", false)
}

resource "helm_release" "ai_gateway_stack" {
  name             = var.release_name
  namespace        = var.namespace
  create_namespace = var.create_namespace

  repository = "oci://registry-1.docker.io/p0security"
  chart      = "ai-gateway-stack"
  version    = var.chart_version

  timeout = var.timeout
  wait    = var.wait

  values = local.values

  lifecycle {
    # merge() is shallow, so one string holding both keys cannot be combined
    # without dropping settings. Ask the caller to pick one.
    precondition {
      condition     = !anytrue(local.has_both_keys)
      error_message = "A values string sets both \"${local.legacy_values_key}\" and \"${local.values_key}\" (values index ${join(", ", [for i, both in local.has_both_keys : tostring(i) if both])}). Move the \"${local.legacy_values_key}\" settings under \"${local.values_key}\" in that string."
    }

    # Valkey's volume holds credentials, so the class is the caller's choice
    # and must be encrypted. The module only checks that one is set.
    precondition {
      condition     = local.valkey_storage_configured
      error_message = "No values string sets valkey.storageClass. Set it to an encrypted StorageClass, or set valkey.enabled: false and point ai-gateway.authServer.caches at an external Valkey. See \"Valkey storage\" in the module README."
    }
  }
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
