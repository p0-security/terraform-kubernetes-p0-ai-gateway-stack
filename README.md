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
  version = "1.3.0"

  chart_version = "1.3.0-beta"

  values = [
    file("${path.module}/values.yaml"),
    yamlencode({
      letsEncrypt = {
        email = var.acme_email
        env   = "prod"
      }
      "ai-gateway" = {
        gateway = {
          className = "agentic-gateway"  # must be unique per release in the cluster
        }
      }
    }),
  ]
}
```

`values.yaml` holds the rest of your chart values, including the StorageClasses:

```yaml
postgresql:
  storageClass: <class>
victorialogs:
  storageClass: <class>
valkey:
  storageClass: <encrypted-class>  # holds credentials; see "Valkey storage"
```

`chart_version` is required and takes an exact chart version. See the [compatibility matrix](#compatibility-matrix) for the versions each module version supports.

Values are merged left-to-right (last wins), equivalent to `helm install -f`. See the [chart's values.yaml](https://github.com/p0-security/p0-helm-oauthed-mcp/blob/main/values.yaml) for the full schema.

Cluster prerequisites apply: A working block-storage StorageClass for the bundled PostgreSQL, VictoriaLogs, and Valkey. EKS requires the EBS CSI driver add-on. Name the classes in your values file, and make Valkey's an encrypted one; see [Valkey storage](#valkey-storage). Values are listed in the [chart's deployment guide](https://github.com/p0-security/p0-helm-oauthed-mcp#prerequisites).

Afterwards, patch in the real OIDC client secret, and on an external database the real PostgreSQL password. The hook writes a placeholder for the first and never overwrites either once set. Restart both Deployments after patching — they read the Secret when a pod starts, so running pods keep the old value until they are replaced:

```bash
kubectl -n <namespace> patch secret app-secrets \
  --type merge \
  -p '{"stringData":{"OIDC_CLIENT_SECRET":"<your-oidc-client-secret>"}}'

kubectl -n <namespace> rollout restart deploy/agentic-auth-server deploy/agentic-gateway-server
```

If your secrets already come from External Secrets or Vault, set `ai-gateway.secretsJob.enabled: false` in `values` and create the Secret yourself. It has to exist before the release is created, so with `create_namespace = true` the namespace does not exist yet at that point — create it outside Terraform and set `create_namespace = false`, or let a separate `kubernetes_namespace` resource own it.

For all post-deploy steps (DNS, verification, staging→prod), follow the [deployment guide](https://github.com/p0-security/p0-helm-oauthed-mcp#deploy).

## Valkey storage

From chart 1.3.0-beta, the bundled Valkey keeps its data on a PersistentVolumeClaim. Set its StorageClass in your values file, next to `postgresql.storageClass` and `victorialogs.storageClass`:

```yaml
valkey:
  storageClass: <encrypted-class>
  storageSize: 1Gi  # optional; the chart defaults to 1Gi
```

**The class must be encrypted.** Valkey's volume holds credentials, including the gateway's registrations with upstream authorization servers. Reuse `postgresql.storageClass` only if that class is encrypted; EKS's stock `gp2` is not. The module cannot tell whether a class is encrypted, so this is on you to check. The chart's [block storage section](https://github.com/p0-security/ai-gateway-stack#block-storage-provisioner) describes what Valkey holds and how to encrypt its volume.

**Without a StorageClass**, run Valkey outside the chart. Set `valkey.enabled: false` and point the auth server's caches at your own Valkey:

```yaml
valkey:
  enabled: false
ai-gateway:
  authServer:
    caches: '{"valkey":{"url":"redis://<your-valkey-host>:6379"},"defaults":[{"type":"memory"},{"type":"valkey"}]}'
```

`terraform plan` fails if no `values` string sets either `valkey.storageClass` or `valkey.enabled: false`. Without the check, the chart would fail with "storageClass is required" partway through `terraform apply`. The check reads the strings the way Helm merges them, so a later string overrides an earlier one.

Changing `valkey.storageClass` on a running release fails, because a claim's StorageClass is immutable. The chart's README has the [steps to switch classes](https://github.com/p0-security/ai-gateway-stack#block-storage-provisioner).

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

From 1.3.0, the module installs the chart version you pass in `chart_version`. The row shows the chart version that module version was tested with. Earlier module versions pin an exact chart version, so to use one of those chart versions, use the corresponding module version.

| Module version | Chart version |
|----------------|---------------|
| 1.3.0          | `chart_version` (1.3.0-beta) |
| 1.2.0-beta     | 1.2.0-beta    |
| 1.1.0-beta     | 1.1.0-beta    |
| 1.0.0-beta     | 1.0.0-beta    |
| 0.6.0          | 0.16.0        |
| 0.5.0          | 0.14.0        |
| 0.4.0          | 0.13.0        |
| 0.3.1          | 0.12.0        |
| 0.3.0          | 0.11.0        |

Earlier module versions were published at the module's two previous addresses,
and their matrices live with them: 0.2.0–0.2.3 (chart 0.10.0–0.11.0) in
[terraform-kubernetes-p0-agentic-gateway-stack](https://github.com/p0-security/terraform-kubernetes-p0-agentic-gateway-stack#compatibility-matrix),
and 0.1.x (chart 0.8.6 and earlier) in
[terraform-kubernetes-p0-oauthed-mcp](https://github.com/p0-security/terraform-kubernetes-p0-oauthed-mcp#compatibility-matrix).
Both are archived.

## Upgrading to 1.3.0

Module 1.3.0 no longer pins the chart. Two changes are needed before `terraform plan` succeeds:

- **Set `chart_version`** to `"1.3.0-beta"`. The input is required and takes an exact version, not a range.
- **Configure Valkey storage** in your values file: set `valkey.storageClass` to an encrypted class, or set `valkey.enabled: false` and point `ai-gateway.authServer.caches` at an external Valkey. See [Valkey storage](#valkey-storage).

The apply restarts Valkey. Valkey is unavailable for up to a minute and comes back empty this once. Users will need to re-authorize upstream MCP servers. Later restarts keep data. The chart's [upgrade notes](https://github.com/p0-security/ai-gateway-stack#upgrading-from-chart-120-beta-or-earlier) cover rollback.

## Upgrading to 1.1.0-beta

Module 1.1.0-beta pins chart 1.1.0-beta, which renames the gateway subchart's values key from `agentic-gateway` to `ai-gateway`. The module rewrites a top-level `agentic-gateway` key to `ai-gateway` in each `values` string, so existing values keep working without edits. A single string that sets both keys fails at plan, because the two cannot be merged reliably; move its `agentic-gateway` settings under `ai-gateway`. Separate strings may use different keys.

The rewrite is temporary, and a later module release removes it. Move your values to `ai-gateway`, and the component keys to `authServer` and `accessProxy`, when convenient. The chart's [upgrade notes](https://github.com/p0-security/ai-gateway-stack#upgrading) describe the new keys.

The first apply shows a `values` diff only for strings that used the old key, since the module re-encodes them. No manifest change is expected beyond the chart upgrade itself.

## Upgrading to 0.5.0

Module 0.5.0 pins chart 0.14.0, which adds a mandatory `braekhus-client` Deployment (a tunnel dialing out to P0's controller) and renames the secrets-provisioning hook Job. Both are breaking: new required `values` keys (`agentic-gateway.braekhus.orgSlug`/`gatewayId`/`tunnelHost`) must be set before upgrading, and the renamed Job leaves its previous RBAC objects orphaned — see the chart's own [changelog](https://github.com/p0-security/p0-helm-oauthed-mcp) for the exact values and cleanup command.

## Upgrading to 0.4.0

Module 0.4.0 pins chart 0.13.0, which moves Envoy Gateway to v1.9.0 and needs Kubernetes 1.33 or later. Helm never upgrades CRDs, so a deployment made with an earlier module version keeps its old Gateway API and Envoy Gateway CRDs. Apply the new ones before running `terraform apply` with 0.4.0. The commands are in the chart's [upgrade section](https://github.com/p0-security/p0-helm-oauthed-mcp#upgrading-from-chart-0120-or-earlier).

A new install needs no extra step.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.7 |
| helm | >= 3.0 |

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| chart\_version | Exact ai-gateway-stack chart version to install. | `string` | n/a (required) |
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
