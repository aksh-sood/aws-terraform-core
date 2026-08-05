# aws

The first of the two stacks: an EKS cluster, its node groups, and the IAM roles
they run as. Nothing inside the cluster — that is
[../kubernetes](../kubernetes/README.md).

```
main.tf          module wiring
validations.tf   plan-time checks on the supplied network
vars.tf          inputs, mirroring each module's defaults
outputs.tf       the contract with the kubernetes stack
modules/eks      cluster, node groups, addons, security groups   → modules/eks/README.md
modules/iam      cluster, node and Grafana roles                 → modules/iam/README.md
```

## Prerequisites

The VPC is an input, not something this stack creates. Before the first apply:

| Prerequisite | Variable | Notes |
| --- | --- | --- |
| A VPC | `vpc_id` | |
| Private subnets across ≥3 AZs | `private_subnet_ids` | Node groups are only as available as the subnets they are placed in |
| Public subnets across ≥3 AZs | `public_subnet_ids` | An ALB needs a subnet in every zone it serves |
| Tag `kubernetes.io/role/elb` on the public subnets | — | The load balancer controller discovers subnets by tag |
| Tag `kubernetes.io/role/internal-elb` on the private subnets | — | Same, for the internal ALB |
| AWS credentials in the environment | — | The provider takes no static credentials |

All of it is checked in [validations.tf](validations.tf), which fails the plan
with a specific message rather than letting the problem surface mid-apply. The
subnet tags matter most: an untagged subnet produces no error anywhere, the
ingress created later just never gets an address. `minimum_availability_zones`
(default 3) sets the zone floor.

The same file also refuses a plan where `endpoint_public_access` is on and
`public_access_cidrs` is empty, so a wide-open API server cannot happen by
omission.

## Applying

```bash
cp dev.tfvars.example dev.tfvars
terraform init
terraform apply -var-file=dev.tfvars
```

Then hand the outputs to the second stack — see
[../README.md](../README.md#the-handover).

## Inputs worth knowing

Full descriptions are in [vars.tf](vars.tf). The ones that change behaviour
rather than values:

| Variable | Default | Effect |
| --- | --- | --- |
| `kubernetes_version` | `1.34` | Control plane version |
| `endpoint_private_access` / `endpoint_public_access` | `true` / `false` | Private-only API server by default. Public access needs `public_access_cidrs` |
| `node_groups` | one group, 3–6 × `m6a.large` | Keyed map; each entry is passed to the upstream module, so any of its node group arguments work |
| `cluster_addons` | CNI, kube-proxy, CoreDNS, EBS + EFS CSI | `before_compute = true` on the two that have to exist before nodes join |
| `kms_key_arn` | `null` | Envelope encryption for Kubernetes secrets. Off while null — see security notes |
| `enabled_cluster_log_types` | all five | Control plane logs to CloudWatch, 90 day retention |
| `authentication_mode` | `API_AND_CONFIG_MAP` | `API` alone is the stricter choice |
| `minimum_availability_zones` | `3` | Zone floor enforced by `validations.tf` |
| `node_security_group_enable_recommended_rules` | `true` | Adds node-to-node ingress **and unrestricted egress** |

## Outputs

Consumed by the `kubernetes` stack under the same names: `region`,
`cluster_name`, `cluster_endpoint`, `cluster_certificate_authority_data`,
`grafana_role_arn`.

Published for completeness and for anything else that needs them: `cluster_arn`,
`cluster_version`, `cluster_cidr`, `cluster_primary_security_group_id`,
`cluster_oidc_issuer_url`, `oidc_provider_arn`, `node_groups`, `cluster_addons`,
`cluster_role_arn`, `node_role_arn`.

`oidc_provider_arn` is the one to reach for when adding IRSA roles.

## Security notes

What is in place: private API endpoint by default, all five control plane log
types shipped to CloudWatch, encrypted gp3 root volumes, an OIDC provider for
IRSA, and separate roles for the control plane and the nodes.

What is not, in the order it matters:

1. **Nothing uses IRSA.** The load balancer controller and both CSI drivers take
   credentials from the node instance profile. `modules/iam/policies/node-custom.json`
   grants `ec2:*`, `s3:*` and `secretsmanager:GetSecretValue` on `*`, so every pod
   on a node inherits all of it through IMDS. See
   [modules/iam/README.md](modules/iam/README.md#the-node-role-is-broader-than-it-looks).
2. **Secrets are not encrypted with a customer key** while `kms_key_arn` is null.
   Trivy AWS-0039. Enabling it on a cluster is one-way — the key can be rotated,
   the setting cannot be removed.
3. **Nodes have unrestricted egress**, from the recommended rules above. Trivy
   AWS-0104. Narrowing it properly means VPC endpoints for ECR, S3, STS and the
   EKS API, then dropping the internet rule.
4. **The node role's trust policy** uses a wildcard federated principal, which
   will error at apply time.
5. **Three of the four `cluster_policies`** do nothing on a role only
   `eks.amazonaws.com` assumes. Harmless, but they read as unexamined.
