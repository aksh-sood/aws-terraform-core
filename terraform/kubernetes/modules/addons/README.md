# modules/addons

The AWS Load Balancer Controller. Everything else in the stack that asks for an
ALB depends on this being installed first.

## Creates

One Helm release, `aws-load-balancer-controller` from
`https://aws.github.io/eks-charts`, in `kube-system`, with `clusterName` set.

The chart also creates the `alb` IngressClass, which is what
[../istio](../istio/README.md) names in `ingress_class_name`.

## Inputs

| Variable | Notes |
| --- | --- |
| `cluster_name` | Passed to the chart as `clusterName`. The controller tags the load balancers it creates with it |
| `lbc_addon_version` | Chart version. `3.5.0` at the root |

## Gotchas

- **Subnet discovery is by tag.** The controller has no `subnets` annotation on
  the ingresses in `../istio`, so it discovers them from
  `kubernetes.io/role/elb` (internet-facing) and `kubernetes.io/role/internal-elb`
  (internal). Untagged subnets produce no error — the ingress simply never gets an
  address. The `aws` stack fails the plan early on this.
- **No IRSA.** The chart's service account carries no `eks.amazonaws.com/role-arn`
  annotation, so the controller uses the node instance profile, which has the ELB
  policy attached. It works, and it means every pod on the node holds the same
  permissions. See [the iam module](../../../aws/modules/iam/README.md#the-node-role-is-broader-than-it-looks).
- **Chart 3.x needs Gateway API CRDs** (v1.6.0) for its Gateway features. They are
  not installed here, so those features disable themselves; ALB Ingress — the only
  thing this stack uses — is unaffected.
