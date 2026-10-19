# Tests run in plan mode against a mock helm provider — no cluster required.
mock_provider "helm" {}

# Defaults for every run: the module requires a chart version, and its
# precondition requires Valkey storage to be configured.
variables {
  chart_version = "1.2.0-beta"
  values        = ["valkey:\n  storageClass: encrypted-gp3\n"]
}

run "defaults" {
  command = plan

  assert {
    condition     = helm_release.ai_gateway_stack.chart == "ai-gateway-stack"
    error_message = "unexpected chart name"
  }

  assert {
    condition     = helm_release.ai_gateway_stack.repository == "oci://registry-1.docker.io/p0security"
    error_message = "unexpected repository"
  }

  assert {
    condition     = helm_release.ai_gateway_stack.name == "agentic-gateway"
    error_message = "default release name should be agentic-gateway"
  }

  assert {
    condition     = helm_release.ai_gateway_stack.namespace == "agentic-gateway"
    error_message = "default namespace should be agentic-gateway"
  }

  assert {
    condition     = helm_release.ai_gateway_stack.create_namespace == true
    error_message = "create_namespace should default to true"
  }

  assert {
    condition     = helm_release.ai_gateway_stack.timeout == 360
    error_message = "timeout should default to 360 so it outlasts the secrets Job's 300 second deadline"
  }

  assert {
    condition     = helm_release.ai_gateway_stack.wait == false
    error_message = "wait should default to false; the TLS certificate cannot issue before the DNS record exists"
  }

  assert {
    condition     = helm_release.ai_gateway_stack.version == "1.2.0-beta"
    error_message = "chart version should come from var.chart_version"
  }

  assert {
    condition     = output.chart_version == "1.2.0-beta"
    error_message = "chart_version output should match var.chart_version"
  }
}

run "override_release_metadata" {
  command = plan

  variables {
    release_name     = "my-mcp"
    namespace        = "platform"
    create_namespace = false
    timeout          = 900
    wait             = true
  }

  assert {
    condition     = helm_release.ai_gateway_stack.name == "my-mcp"
    error_message = "release name override not applied"
  }

  assert {
    condition     = helm_release.ai_gateway_stack.namespace == "platform"
    error_message = "namespace override not applied"
  }

  assert {
    condition     = helm_release.ai_gateway_stack.create_namespace == false
    error_message = "create_namespace override not applied"
  }

  assert {
    condition     = helm_release.ai_gateway_stack.timeout == 900 && helm_release.ai_gateway_stack.wait == true
    error_message = "timeout and wait overrides not applied"
  }

  assert {
    condition     = helm_release.ai_gateway_stack.version == "1.2.0-beta"
    error_message = "chart version should remain var.chart_version even when other metadata is overridden"
  }
}

run "values_passthrough" {
  command = plan

  variables {
    values = [
      "letsEncrypt:\n  env: staging\n",
      "letsEncrypt:\n  env: prod\n",
      "valkey:\n  storageClass: encrypted-gp3\n",
    ]
  }

  assert {
    condition     = length(helm_release.ai_gateway_stack.values) == 3
    error_message = "every values entry should be passed through to the helm release"
  }
}

# A timeout at or below the secrets Job's 300 second deadline puts the release
# timeout back in a race with the Job, which is the failure this input exists to
# avoid.
run "rejects_timeout_at_job_deadline" {
  command = plan

  variables {
    timeout = 300
  }

  expect_failures = [var.timeout]
}

# Chart 1.1.0-beta renamed the gateway subchart's values key. The module rewrites
# the old key so the console-generated shape keeps working unchanged.
run "values_rewrites_legacy_key" {
  command = plan

  variables {
    values = [yamlencode({
      letsEncrypt = { env = "prod", email = "ops@example.com" }
      agentic-gateway = {
        gateway           = { className = "agentic-gateway" }
        agenticAuthServer = { replicas = 2 }
      }
      valkey = { storageClass = "encrypted-gp3" }
    })]
  }

  assert {
    condition = helm_release.ai_gateway_stack.values[0] == yamlencode({
      letsEncrypt = { env = "prod", email = "ops@example.com" }
      ai-gateway = {
        gateway           = { className = "agentic-gateway" }
        agenticAuthServer = { replicas = 2 }
      }
      valkey = { storageClass = "encrypted-gp3" }
    })
    error_message = "agentic-gateway should be renamed to ai-gateway, with its contents (component keys included) unchanged"
  }
}

run "values_new_key_verbatim" {
  command = plan

  variables {
    values = [
      "# new key\nai-gateway:\n  gateway:\n    className: gw\n",
      "valkey:\n  storageClass: encrypted-gp3\n",
    ]
  }

  assert {
    condition     = helm_release.ai_gateway_stack.values[0] == "# new key\nai-gateway:\n  gateway:\n    className: gw\n"
    error_message = "a string without the old key should pass through verbatim"
  }
}

# Helm deep-merges separate strings, so each is handled on its own.
run "values_both_keys_separate_strings" {
  command = plan

  variables {
    values = [
      "agentic-gateway:\n  gateway:\n    className: gw\n",
      "ai-gateway:\n  braekhus:\n    orgSlug: acme\n",
      "valkey:\n  storageClass: encrypted-gp3\n",
    ]
  }

  assert {
    condition     = helm_release.ai_gateway_stack.values[0] == yamlencode({ ai-gateway = { gateway = { className = "gw" } } })
    error_message = "the string using the old key should be rewritten"
  }

  assert {
    condition     = helm_release.ai_gateway_stack.values[1] == "ai-gateway:\n  braekhus:\n    orgSlug: acme\n"
    error_message = "the string using the new key should pass through verbatim"
  }
}

# A shallow merge would drop settings, so one string with both keys fails at plan.
run "values_both_keys_one_string_fails" {
  command = plan

  variables {
    values = [
      "agentic-gateway:\n  gateway:\n    className: gw\nai-gateway:\n  braekhus:\n    orgSlug: acme\n",
      "valkey:\n  storageClass: encrypted-gp3\n",
    ]
  }

  expect_failures = [helm_release.ai_gateway_stack]
}

run "values_non_map_verbatim" {
  command = plan

  variables {
    values = [
      "# only a comment\n",
      "",
      "- agentic-gateway\n",
      "agentic-gateway",
      "valkey:\n  storageClass: encrypted-gp3\n",
    ]
  }

  assert {
    condition = helm_release.ai_gateway_stack.values == tolist([
      "# only a comment\n",
      "",
      "- agentic-gateway\n",
      "agentic-gateway",
      "valkey:\n  storageClass: encrypted-gp3\n",
    ])
    error_message = "comment-only, empty and non-map strings should pass through verbatim"
  }
}

run "chart_version_override" {
  command = plan

  variables {
    chart_version = "1.1.0-beta"
  }

  assert {
    condition     = helm_release.ai_gateway_stack.version == "1.1.0-beta" && output.chart_version == "1.1.0-beta"
    error_message = "chart_version should set the helm release version and the output"
  }
}

# A range or an empty string would let the installed chart change without a
# change to the caller's configuration.
run "rejects_chart_version_range" {
  command = plan

  variables {
    chart_version = "~1.2.0"
  }

  expect_failures = [var.chart_version]
}

run "rejects_empty_chart_version" {
  command = plan

  variables {
    chart_version = ""
  }

  expect_failures = [var.chart_version]
}

# Charts with Valkey persistence fail to render without valkey.storageClass. The
# precondition reports that at plan instead of partway through an apply.
run "valkey_storage_class_missing_fails" {
  command = plan

  variables {
    values = ["letsEncrypt:\n  env: prod\n"]
  }

  expect_failures = [helm_release.ai_gateway_stack]
}

run "valkey_storage_class_empty_fails" {
  command = plan

  variables {
    values = ["valkey:\n  storageClass: \"\"\n"]
  }

  expect_failures = [helm_release.ai_gateway_stack]
}

# No-persistence mode: the bundled Valkey is off and the caches point elsewhere.
run "valkey_disabled_passes" {
  command = plan

  variables {
    values = [yamlencode({
      valkey = { enabled = false }
      ai-gateway = {
        authServer = {
          caches = jsonencode({
            valkey   = { url = "redis://valkey.example.com:6379" }
            defaults = [{ type = "memory" }, { type = "valkey" }]
          })
        }
      }
    })]
  }

  assert {
    condition     = length(helm_release.ai_gateway_stack.values) == 1
    error_message = "valkey.enabled: false should satisfy the Valkey storage precondition"
  }
}

# Helm deep-merges the strings, so a later string that sets other valkey keys
# keeps the class set by an earlier one.
run "valkey_storage_class_from_earlier_string" {
  command = plan

  variables {
    values = [
      "valkey:\n  storageClass: encrypted-gp3\n",
      "valkey:\n  storageSize: 2Gi\n",
    ]
  }

  assert {
    condition     = length(helm_release.ai_gateway_stack.values) == 2
    error_message = "a class set in an earlier string should satisfy the precondition"
  }
}

# Last string wins, as in Helm: re-enabling Valkey without a class fails.
run "valkey_reenabled_without_class_fails" {
  command = plan

  variables {
    values = [
      "valkey:\n  enabled: false\n",
      "valkey:\n  enabled: true\n",
    ]
  }

  expect_failures = [helm_release.ai_gateway_stack]
}
