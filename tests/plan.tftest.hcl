# Tests run in plan mode against a mock helm provider — no cluster required.
mock_provider "helm" {}

run "defaults" {
  command = plan

  variables {
    values = []
  }

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
    condition     = helm_release.ai_gateway_stack.wait == true
    error_message = "wait should default to true, matching the Helm provider's own default"
  }

  assert {
    condition     = helm_release.ai_gateway_stack.version == local.chart_version
    error_message = "chart version should be pinned to local.chart_version"
  }

  assert {
    condition     = output.chart_version == local.chart_version
    error_message = "chart_version output should match the pinned local"
  }
}

run "override_release_metadata" {
  command = plan

  variables {
    release_name     = "my-mcp"
    namespace        = "platform"
    create_namespace = false
    timeout          = 900
    wait             = false
    values           = []
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
    condition     = helm_release.ai_gateway_stack.timeout == 900 && helm_release.ai_gateway_stack.wait == false
    error_message = "timeout and wait overrides not applied"
  }

  assert {
    condition     = helm_release.ai_gateway_stack.version == local.chart_version
    error_message = "chart version should remain pinned even when other metadata is overridden"
  }
}

run "values_passthrough" {
  command = plan

  variables {
    values = [
      "letsEncrypt:\n  env: staging\n",
      "letsEncrypt:\n  env: prod\n",
    ]
  }

  assert {
    condition     = length(helm_release.ai_gateway_stack.values) == 2
    error_message = "both values entries should be passed through to the helm release"
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
