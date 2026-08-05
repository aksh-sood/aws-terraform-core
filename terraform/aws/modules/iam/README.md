# modules/iam

Every IAM role the cluster uses. Kept out of [../eks](../eks/README.md) so the
roles outlive any single cluster resource and so policy attachments are ordered
explicitly against cluster creation.

## Creates

| Role | Assumed by | Carries |
| --- | --- | --- |
| `eks_cluster_<cluster>_<region>` | `eks.amazonaws.com` | `var.cluster_policies`, plus the ELB and CloudWatch-metrics policies below |
| `eks_node_<cluster>_<region>` | `ec2.amazonaws.com`, and a federated principal for the EFS CSI driver | `var.node_policies`, the ELB policy, `node-custom.json`, and anything in `var.additional_node_policies` / `var.additional_node_inline_policy` |
| `grafana_<cluster>_<region>` | The account root and the node role | `var.grafana_policies` — `CloudWatchReadOnlyAccess` by default |

Three customer-managed policies come from [policies/](policies):

| File | Purpose |
| --- | --- |
| `eksctl-cluster-PolicyELBPermissions.json` | Scoped ELB and target group management, as the load balancer controller needs |
| `eksctl-cluster-PolicyCloudWatchMetric.json` | `cloudwatch:PutMetricData` |
| `node-custom.json` | Broad node permissions — see below |

## Outputs

`cluster_role_arn`, `node_role_arn`, `grafana_role_arn`, and
`cluster_policies_map` for inspecting what ended up attached.

## The node role is broader than it looks

`node-custom.json` grants, on `Resource: "*"`:

- `ec2:*`, `s3:*`, `elasticloadbalancing:*`, `autoscaling:*`, `cloudwatch:*`,
  `waf:*` / `wafv2:*`
- `secretsmanager:GetSecretValue`, `ListSecrets`, `DescribeSecret`

Nothing in the cluster uses IRSA, so pods take their AWS credentials from the
instance metadata service — which hands back this role. There is no pod-level
boundary: any container that can reach IMDS gets all of the above, including the
application pod. One RCE in a workload is: read every secret in the account,
read and write every bucket, terminate any instance.

The fix is IRSA (or EKS Pod Identity): strip the wide policies off the node role,
leaving the three baseline managed ones, and give each controller a role whose
trust policy names its exact service account —
`system:serviceaccount:kube-system:aws-load-balancer-controller`,
`…:ebs-csi-controller-sa`, `…:efs-csi-controller-sa`. `oidc_provider_arn` from the
eks module is the trust anchor. Setting the IMDS hop limit to 1 on the node groups
stops pods reaching the metadata service at all.

The Grafana role has the same shape of problem: it trusts the *node role*, so any
pod on a node can assume it.

## Other things to know

- **The node role's trust policy** includes a federated principal of
  `arn:aws:iam::<account>:oidc-provider/*` with `"*:aud"` and `"*:sub"`
  conditions. Wildcards are not valid in a federated principal ARN and `*:aud` is
  not a resolvable condition key, so this will error at apply time. The IRSA work
  above removes it.
- **Three of the four default `cluster_policies` do nothing.** The control plane
  role is assumed only by `eks.amazonaws.com`; `AmazonEKS_CNI_Policy` is needed by
  the CNI DaemonSet on nodes, `AmazonEBSCSIDriverPolicy` by the CSI controller pod,
  and `AmazonEKSServicePolicy` is legacy. Only `AmazonEKSClusterPolicy` is
  required. The ELB and CloudWatch policies attached to that role are no-ops too.
- **Role names are not prefixed with `name_prefix`**, so a second cluster with the
  same name in the same region collides. Deliberate — the names are predictable
  for access entries and trust policies elsewhere.
