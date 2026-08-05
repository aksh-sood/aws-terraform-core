# modules/eks

Wraps [`terraform-aws-modules/eks/aws`](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws)
`~> 21.24`. The wrapper exists to pin the choices this platform has already made,
so the root passes intent rather than upstream plumbing.

## Creates

- The EKS control plane, with the API endpoint access and logging the root asks for
- Managed node groups from `var.node_groups`
- Two security groups with fixed names, `<cluster>-cluster` and `<cluster>-node`,
  rather than generated suffixes
- The EKS addons in `var.cluster_addons`
- The OIDC provider (`enable_irsa = true`), including the root CA thumbprint
- The CloudWatch log group for control plane logs

## Does not create

- **IAM roles.** `create_iam_role = false` on both the cluster and the node
  groups; ARNs come from [../iam](../iam/README.md). This is why the root's
  `module.eks` has an explicit `depends_on = [module.iam]` — policy attachments
  are separate resources, so the role ARN reference alone does not guarantee they
  exist before nodes launch, or survive until after they are gone.
- **A KMS key.** `create_kms_key = false`. Envelope encryption is configured only
  when the root supplies `kms_key_arn`; `encryption_config` is `null` otherwise.

## Node group defaults

[locals.tf](locals.tf) merges three settings into every entry of
`var.node_groups`, so callers describe the shape of a group and not its wiring:

| Setting | Why |
| --- | --- |
| `create_iam_role = false`, `iam_role_arn` | The role is the iam module's |
| `attach_cluster_primary_security_group = true` | Nodes reach the control plane through the group EKS creates for the cluster |

Any key a caller sets wins, since the caller's map is merged second.

## Inputs

See [vars.tf](vars.tf). Every argument is passed through from the root
explicitly, and the root's defaults mirror this module's — when one changes, the
other has to change with it.

## Outputs

`cluster_name`, `cluster_arn`, `cluster_endpoint`,
`cluster_certificate_authority_data`, `cluster_version`, `cluster_cidr`,
`cluster_primary_security_group_id`, `cluster_oidc_issuer_url`,
`oidc_provider_arn`, `cloudwatch_log_group_name`, `node_groups`,
`node_groups_autoscaling_group_names`, `cluster_addons`.

`oidc_provider_arn` is what an IRSA trust policy needs. Nothing consumes it yet.

## Gotchas

- **`node_security_group_enable_recommended_rules`** adds node-to-node ingress on
  ephemeral ports *and* unrestricted egress to `0.0.0.0/0`. Trivy flags the egress
  rule as AWS-0104. Nodes do need to reach registries, STS and the EKS API, so
  closing it means VPC endpoints first.
- **`cluster_cidr`** is the upstream `cluster_service_cidr`, renamed on the way
  out.
- **Addon ordering.** `vpc-cni` and `kube-proxy` carry `before_compute = true` in
  the root's defaults; they have to exist before nodes join or the nodes never
  become ready.
