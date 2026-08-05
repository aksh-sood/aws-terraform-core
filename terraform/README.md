# Terraform

Two stacks, applied in order. They are separate roots on purpose: the Kubernetes
providers need a cluster endpoint that does not exist until the first stack has
finished, and Terraform cannot configure a provider from a value that is unknown
at plan time.

```
terraform/
  aws/          EKS cluster, IAM roles, ECR repositories
  kubernetes/   load balancer controller, istio, monitoring, logging, jaeger
```

## Prerequisites

The VPC is **not** created here — this stack provisions the cluster, not the
network it sits in. Before the first apply you need:

| Prerequisite | Notes |
|---|---|
| A VPC | `vpc_id` |
| Private subnets in ≥3 AZs | `private_subnet_ids`. Node groups are only as available as the subnets they are placed in |
| Public subnets in ≥3 AZs | `public_subnet_ids`. An ALB needs a subnet in every zone it serves |
| Subnet tag `kubernetes.io/role/elb` on the public subnets | The load balancer controller discovers subnets by tag |
| Subnet tag `kubernetes.io/role/internal-elb` on the private subnets | Same, for the internal ALB |
| An ACM certificate | `acm_certificate_arn`, served by both istio ALBs |
| Two security groups | `elb_security_group`, `internal_alb_security_group` |
| A KMS key | `kms_key_arn`. Optional today, so envelope encryption of Kubernetes secrets is off unless you pass one |
| `aws` CLI on PATH | The Kubernetes providers mint API tokens with `aws eks get-token` |

All of these are checked in [aws/validations.tf](aws/validations.tf) and fail the
plan with a specific message rather than at apply time — a missing subnet tag in
particular produces no error at all, the ingress just never gets an address.
`minimum_availability_zones` (default 3) controls the zone assertion.

## Applying

```bash
# 1. Cluster, IAM, registries
cd terraform/aws
cp dev.tfvars.example dev.tfvars   # fill in the VPC, subnets and tags
terraform init
terraform apply -var-file=dev.tfvars

# 2. Hand the outputs over. Every output here is named after the variable of the
#    same name in terraform/kubernetes, so no per-value mapping is needed.
terraform output -json | jq 'map_values(.value)' \
  > ../kubernetes/aws.auto.tfvars.json

# 3. Platform components
cd ../kubernetes
cp dev.tfvars.example dev.tfvars   # fill in the domain, certificate and SGs
terraform init
terraform apply -var-file=dev.tfvars
```

Outputs the second stack does not declare (`cluster_arn`, `node_groups`, …)
produce warnings, not errors. Narrow the `jq` filter if they get noisy.

The handover can be automated with Terragrunt `dependency` blocks, a
`terraform_remote_state` data source, or a CI artifact — the matching names are
what make any of them a one-liner.

## Reaching a private cluster

`endpoint_public_access` defaults to `false`, so the API server is reachable only
from inside the VPC. **The second stack talks to that endpoint directly**, so it
has to run from somewhere inside the VPC too:

- a bastion in a private subnet, reached with `aws ssm start-session`, or
- an SSM port-forward to the endpoint from your workstation, or
- a CI runner or CodeBuild project attached to the VPC.

For a demo you can set `endpoint_public_access = true` and list your own address
in `public_access_cidrs`; the plan fails if you enable the endpoint and leave the
allow list empty. Public access is a deliberate exception, not the default.

## State

Both stacks keep state on disk, so a local run needs nothing but AWS
credentials. The S3 backend is commented out in [aws/backend.tf](aws/backend.tf)
and [kubernetes/backend.tf](kubernetes/backend.tf); fill in the bucket and
uncomment when the stacks move to shared state. They have to be remote before
the outputs of one can be read as the inputs of the other through
`terraform_remote_state`.

## Monitoring an application

Prometheus only scrapes `ServiceMonitor` objects carrying **all** of the labels
in the `service_monitor_labels` output — the selector is an AND:

```bash
terraform -chdir=terraform/kubernetes output -json service_monitor_labels
# { "prometheus": "prometheus-kube-prometheus-prometheus", "release": "prometheus" }
```

The output and the chart's `serviceMonitorSelector` are rendered from the same
local in [kubernetes/modules/monitoring/main.tf](kubernetes/modules/monitoring/main.tf),
so they cannot drift. An application chart should read the labels from there
rather than copy them.

Grafana dashboards are the JSON files in
[modules/grafana-config/dashboards/](kubernetes/modules/monitoring/modules/grafana-config/dashboards/),
applied through Terraform's Grafana provider. That provider talks to Grafana over
its public hostname, so dashboards, the developer user and the CloudWatch
datasource are only provisioned when `create_dns_records = true` — the same
variable feeds `configure_grafana`. On the default path Grafana comes up with the
chart's built-in dashboards only.

Reach the UIs by port-forward when there are no DNS records:

```bash
kubectl -n monitoring port-forward svc/prometheus-grafana 3000:80
terraform -chdir=terraform/kubernetes output grafana_password
```

## Known limitations

- **Controllers use node-role permissions, not IRSA.** The load balancer
  controller and both CSI drivers take their credentials from the node instance
  profile. `node-custom.json` grants `ec2:*`, `s3:*` and
  `secretsmanager:GetSecretValue` on `*`, so every pod on a node inherits them
  through IMDS. IRSA is enabled on the cluster and `oidc_provider_arn` is
  exported, but nothing consumes it yet.
- **The node role's trust policy** uses a wildcard federated principal, which
  will surface as an error at apply time. The IRSA work above removes it.
- **Istio, Jaeger and the OpenSearch logging stack** are heavier than a Hello
  World deployment needs and pull in a domain, a certificate and a WAF as
  prerequisites. `create_opensearch` is off by default; the mesh is not yet
  optional.
- **No application chart yet.** Nothing deploys a workload; the platform is the
  scope of this directory.
- **Provider pins are old** — `kubernetes 2.10.0` and `helm 2.10.1` are from
  2022. Upgrading helm past 2.x means rewriting every `set {}` block as a list.
