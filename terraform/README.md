# Terraform

Two stacks, applied in order.

| Stack | Provisions | Docs |
| --- | --- | --- |
| [aws](aws) | EKS control plane, node groups, IAM roles | [aws/README.md](aws/README.md) |
| [kubernetes](kubernetes) | Ingress, observability, tracing, logging, the application | [kubernetes/README.md](kubernetes/README.md) |

## Why two roots

The Kubernetes, Helm and kubectl providers need `cluster_endpoint` and
`cluster_certificate_authority_data` to authenticate. Terraform evaluates
provider configuration before those values exist, and a single root would hit
two problems: an unknown-value error on the first plan, and a destroy that
removes the cluster before the resources configured against it.

Splitting the roots also means the platform can be re-applied without putting the
control plane in the plan at all.

The cost is a handover step between the two applies.

## The handover

Every output of the `aws` stack is named after the variable of the same name in
the `kubernetes` stack, so no per-value mapping is needed anywhere:

| `aws` output | `kubernetes` variable | Used for |
| --- | --- | --- |
| `region` | `region` | AWS provider, EKS token |
| `cluster_name` | `cluster_name` | Addons, hostname prefix, token |
| `cluster_endpoint` | `cluster_endpoint` | All three Kubernetes providers |
| `cluster_certificate_authority_data` | `cluster_certificate_authority_data` | All three Kubernetes providers |
| `grafana_role_arn` | `grafana_role_arn` | Grafana CloudWatch datasource |

```bash
cd terraform/aws
terraform output -json | jq 'map_values(.value)' > ../kubernetes/aws.auto.tfvars.json
```

Terraform auto-loads any `*.auto.tfvars.json`. Outputs the second stack does not
declare (`cluster_arn`, `node_groups`, …) produce warnings, not errors; narrow the
`jq` filter if they get noisy. The file is gitignored — it holds account
identifiers.

**Renaming either side means renaming both.** That parity is the only thing
keeping the handover a single line.

### Automating it

| Approach | Trade-off |
| --- | --- |
| `terraform output -json` → `.auto.tfvars.json` | What the commands above do. No extra tooling, no state coupling, but the ordering is on you |
| Terragrunt `dependency` blocks | `inputs = merge(dependency.aws.outputs, {…})` is one line precisely because the names match, and `run-all apply` orders the stacks. Needs the extra binary |
| `terraform_remote_state` | No new tooling, but the second stack gets read access to the whole first state file, and each value is mapped by hand |
| `data "aws_eks_cluster"` | Endpoint, CA and OIDC straight from the API, so only `cluster_name` and `region` need passing. Costs an API call per plan |
| SSM Parameter Store | Most decoupled, works cross-account and for non-Terraform consumers. Most glue |
| CI artifact | The first job publishes the JSON, the second consumes it. Ordering enforced by the pipeline |

Not worth it: collapsing both into one root, for the reasons above.

## State

Both stacks keep state on disk, so a local run needs nothing but AWS
credentials. The S3 backend is commented out in [aws/backend.tf](aws/backend.tf)
and [kubernetes/backend.tf](kubernetes/backend.tf) — fill in the bucket and
uncomment when the stacks move to shared state. Both have to be remote before
`terraform_remote_state` can read one from the other.

## Conventions

- `main.tf` wires modules, `vars.tf` declares inputs, `outputs.tf` publishes,
  `providers.tf` pins and configures providers. Root-level checks live in
  `validations.tf`.
- Root variables mirror their module's defaults so the root is the single place a
  value is set. When a module default changes, the root has to change with it.
- Every module takes its kubectl provider through a `kubectl.this` configuration
  alias, passed explicitly in the `providers` block of each call.
- `dev.tfvars.example` in each stack lists what has to be supplied. Copies named
  `*.tfvars` are gitignored.

## Checks

```bash
terraform fmt -recursive -check
terraform validate                   # per stack, after terraform init
trivy config terraform/              # see ../terraform-trivy-scan.txt
```
