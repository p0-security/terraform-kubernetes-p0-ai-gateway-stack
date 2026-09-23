# terraform-kubernetes-ai-gateway-stack

Terraform module that deploys [agentic-gateway](https://github.com/p0-security/agentic-gateway) via the [ai-gateway-stack](https://github.com/p0-security/p0-helm-oauthed-mcp) umbrella Helm chart. The chart bundles Envoy Gateway, cert-manager, Let's Encrypt (ACME HTTP-01), PostgreSQL, and Valkey into a single install.

## Usage

```hcl
provider "helm" {
  kubernetes = {
    config_path = "~/.kube/config"
  }
}

module "ai_gateway_stack" {
  source  = "p0-security/ai-gateway-stack/kubernetes"
  version = "0.3.0"

  values = [
    file("${path.module}/values.yaml"),
    yamlencode({
      letsEncrypt = {
        email = var.acme_email
        env   = "prod"
      }
      "agentic-gateway" = {
        gateway = {
          className = "agentic-gateway"  # must be unique per release in the cluster
        }
      }
    }),
  ]
}
```

Values are merged left-to-right (last wins), equivalent to `helm install -f`. See the [chart's values.yaml](https://github.com/p0-security/p0-helm-oauthed-mcp/blob/main/values.yaml) for the full schema.

There is no secret setup step to run before `terraform apply`. The chart creates `app-secrets` itself, from a pre-install hook. The cluster prerequisites still apply, though — a working block-storage StorageClass for the bundled PostgreSQL, which on EKS means the EBS CSI driver add-on. Those are listed in the [chart's deployment guide](https://github.com/p0-security/p0-helm-oauthed-mcp#prerequisites).

Afterwards, patch in the real OIDC client secret, and on an external database the real PostgreSQL password. The hook writes a placeholder for the first and never overwrites either once set. Restart both Deployments after patching — they read the Secret when a pod starts, so running pods keep the old value until they are replaced:

```bash
kubectl -n <namespace> patch secret app-secrets \
  --type merge \
  -p '{"stringData":{"OIDC_CLIENT_SECRET":"<your-oidc-client-secret>"}}'

kubectl -n <namespace> rollout restart deploy/agentic-auth-server deploy/agentic-gateway-server
```

If your secrets already come from External Secrets or Vault, set `agentic-gateway.secretsJob.enabled: false` in `values` and create the Secret yourself. It has to exist before the release is created, so with `create_namespace = true` the namespace does not exist yet at that point — create it outside Terraform and set `create_namespace = false`, or let a separate `kubernetes_namespace` resource own it.

For all post-deploy steps (DNS, verification, staging→prod), follow the [deployment guide](https://github.com/p0-security/p0-helm-oauthed-mcp#deploy).

## Migrating from `p0-agentic-gateway-stack`

This module was published as `p0-security/p0-agentic-gateway-stack/kubernetes`
through version 0.2.3, and as `p0-security/p0-oauthed-mcp/kubernetes` through
version 0.1.9. Both repositories are archived: the versions already published
there stay resolvable, but no new version will appear at either address.

Repointing is a `source` and `version` change, nothing more:

```hcl
module "ai_gateway_stack" {
  source  = "p0-security/ai-gateway-stack/kubernetes"
  version = "0.3.0"

  values = [...]
}
```

**No defaults changed in this release.** `release_name` and `namespace` still
default to `agentic-gateway`, so unlike the 0.1.x → 0.2.x move there is nothing
to pin to avoid a replacement. The `helm_release` resource was renamed, but
chained `moved` blocks in this module handle that from either older lineage.
`terraform plan` should report a move plus at most an in-place update — never a
replacement, which would destroy the release along with its PostgreSQL and
Valkey data. Confirm that before applying.

The pinned chart also changed name, from `agentic-gateway-stack` to
`ai-gateway-stack`. The two are the same package pushed under two names at the
same version, so this renders identical manifests. `ai-gateway-stack` is the
chart's real name; `agentic-gateway-stack` is a compatibility alias that will be
dropped once its remaining consumers have migrated, which is why this module no
longer pulls it. The pre-rename `p0-helm-oauthed-mcp` chart is retired.

### Coming from 0.1.x

If you are still on `p0-oauthed-mcp` and relied on the old defaults, the release
name and namespace changed from `oauthed-mcp` to `agentic-gateway` in 0.2.0, and
both are replace-forcing in the Helm provider. Pin them explicitly:

```hcl
  release_name = "oauthed-mcp"
  namespace    = "oauthed-mcp"
```

Values keys followed that same rename: the subchart block is `agentic-gateway`
rather than `oauthed-mcp`.

## Compatibility matrix

Each module version pins an exact chart version. To use a specific chart version, use the corresponding module version.

| Module version | Chart version |
|----------------|---------------|
| 0.3.1          | 0.12.0        |
| 0.3.0          | 0.11.0        |

Earlier module versions were published at the module's two previous addresses,
and their matrices live with them: 0.2.0–0.2.3 (chart 0.10.0–0.11.0) in
[terraform-kubernetes-p0-agentic-gateway-stack](https://github.com/p0-security/terraform-kubernetes-p0-agentic-gateway-stack#compatibility-matrix),
and 0.1.x (chart 0.8.6 and earlier) in
[terraform-kubernetes-p0-oauthed-mcp](https://github.com/p0-security/terraform-kubernetes-p0-oauthed-mcp#compatibility-matrix).
Both are archived.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.7 |
| helm | >= 3.0 |

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| release\_name | Helm release name. | `string` | `"agentic-gateway"` |
| namespace | Kubernetes namespace to deploy into. | `string` | `"agentic-gateway"` |
| create\_namespace | Create the namespace if it does not exist. | `bool` | `true` |
| values | List of YAML values strings merged left-to-right. | `list(string)` | `[]` |
| timeout | Seconds Helm waits for an install or upgrade, hooks included. | `number` | `360` |
| wait | Wait for every resource to be ready before marking the release deployed. | `bool` | `false` |

Both defaults differ from the Helm provider's own.

`timeout` must be greater than 300 seconds. The chart's secrets Job gives up at
300, and a release timeout at or below that hides the Job's own error behind a
generic Helm timeout.

`wait` is off because a first install cannot reach readiness: the TLS
certificate needs a DNS record pointing at a load balancer that does not exist
until the apply finishes. Turn it on once DNS is in place and you want later
applies to block on rollout.

## Outputs

| Name | Description |
|------|-------------|
| release\_name | Name of the Helm release. |
| namespace | Namespace the release was deployed into. |
| chart\_version | Chart version that was deployed. |
