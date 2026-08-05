# EKS platform and Hello World service

Terraform provisions an EKS cluster and the platform that runs on it — ingress,
observability, alerting — and deploys an HTTP microservice onto it from a Helm
chart in this repository.

Everything is Infrastructure as Code. There is no step where you click something
in a console or run `kubectl apply` by hand.

## Layout

```
terraform/
  aws/            EKS cluster, node groups, IAM roles          → terraform/aws/README.md
  kubernetes/     load balancer controller, istio, monitoring,
                  logging, tracing, and the application release → terraform/kubernetes/README.md
helm-chart/       the microservice chart                        → helm-chart/README.md
pipeline/         GitHub Actions deploy, tag rollout only       → pipeline/README.md
.github/workflows/  the trigger for it
```

Two Terraform stacks, applied in order. They are separate roots because the
Kubernetes providers need a cluster endpoint that does not exist until the first
stack has finished, and Terraform cannot configure a provider from a value that
is unknown at plan time. [terraform/README.md](terraform/README.md) covers the
split and how values move between them.

## What gets built

| Layer | Components |
| --- | --- |
| Cluster | EKS control plane across 3 AZs, managed node group (3–6 × `m6a.large`, gp3 encrypted), `vpc-cni`, `kube-proxy`, `coredns`, EBS and EFS CSI drivers |
| Identity | Control plane, node and Grafana IAM roles; OIDC provider for IRSA |
| Ingress | AWS Load Balancer Controller, Istio via the Sail operator, one internet-facing and one internal ALB terminating TLS, basic auth on the platform UIs |
| Storage | `ebs` or `efs` StorageClass, selected by `enable_ebs_persistent_storage` |
| Observability | kube-prometheus-stack — Prometheus (90d retention), Alertmanager routing to Slack and PagerDuty, Grafana with cluster dashboards, 9 built-in alert rules |
| Tracing | Jaeger, wired to the mesh |
| Logging | Filebeat shipping to OpenSearch, with a Kibana route — optional, off by default |
| Application | `deploy-service` chart: 3-AZ topology spread, non-root read-only container, startup/readiness/liveness probes, Istio Gateway and VirtualService, ServiceMonitor |
| Delivery | GitHub Actions workflow that rolls the release onto a new image tag, authenticating with OIDC rather than stored keys |

## Prerequisites

- A VPC with public and private subnets across **at least 3 availability zones**,
  tagged for load balancer discovery. This stack provisions the cluster, not the
  network it sits in — the full list, and the plan-time checks that enforce it,
  is in [terraform/aws/README.md](terraform/aws/README.md#prerequisites).
- An ACM certificate and two security groups for the ALBs.
- Terraform >= 1.4, the `aws` CLI (the Kubernetes providers mint API tokens with
  `aws eks get-token`), `kubectl`, `helm`.
- AWS credentials in the environment.
- KMS key for encryption of resources

## Quickstart

```bash
# 1. Cluster, node groups, IAM
cd terraform/aws
cp dev.tfvars.example dev.tfvars        # VPC, subnets, tags
terraform init
terraform apply -var-file=dev.tfvars

# 2. Hand the outputs over. Every output is named after the variable of the same
#    name in the second stack, so no per-value mapping is needed.
terraform output -json | jq 'map_values(.value)' > ../kubernetes/aws.auto.tfvars.json

# 3. Platform and application
cd ../kubernetes
cp dev.tfvars.example dev.tfvars        # domain, certificate, security groups
terraform init
terraform apply -var-file=dev.tfvars

# 4. The application
terraform output service_urls
```

By default the API server has no public endpoint, so **step 3 has to run from
inside the VPC** — see
[reaching a private cluster](terraform/kubernetes/README.md#reaching-a-private-cluster).
With `create_dns_records = false` (also the default) the UIs are reached by
port-forward rather than by hostname.

## Design decisions

**Two stacks, not one.** A single root would have to configure the Kubernetes
provider from the cluster's own attributes. Terraform evaluates provider
configuration before it knows those values, and a `terraform destroy` would pull
the provider config out from under the resources that depend on it. The cost is a
handover step between applies; the mitigation is naming every output after the
variable it feeds, so the handover is one `jq` line and can be automated with
Terragrunt, `terraform_remote_state`, or a CI artifact.

**The VPC is an input.** The scope is the cluster. Accepting `vpc_id` and subnet
IDs keeps the stack usable in an account where the network is owned by someone
else. To stop that becoming an unverified assumption,
[validations.tf](terraform/aws/validations.tf) fails the plan if the subnets span
too few zones, sit in a different VPC, or lack the tags the load balancer
controller discovers on — a missing tag otherwise produces no error at all, the
ingress simply never gets an address.

**Private API endpoint by default.** `endpoint_public_access` defaults to `false`.
Turning it on requires an explicit CIDR allow list, enforced by a precondition,
so a public API server is always a deliberate act.

**The chart lives in this repository.** `helm_release` installs it from a local
path rather than a registry, so the chart is versioned with the Terraform that
deploys it and a rollback moves both together.

**The pipeline deploys tags, not configuration.** [pipeline](pipeline) moves the
release onto a different image tag with `helm upgrade --reuse-values
--set-string image.tag=…` and nothing else. Every other value stays owned by
`terraform/kubernetes`, which installed the release, so there is exactly one
writer per field and a deploy cannot quietly drift the chart away from what
Terraform believes is deployed.

**Opinionated chart, small values file.** `values.yaml` exposes only what varies
between deployments. Security context, rollout strategy, probe timings and
topology spread are fixed in the templates with the reasoning written beside
each. See [what is fixed, and why](helm-chart/README.md#what-is-fixed-and-why).

**Istio rather than a plain ALB.** It buys the basic auth on the platform UIs,
per-app Gateways and VirtualServices owned by the app's own namespace, and the
tracing integration. The cost is that a domain, a certificate and pre-existing
security groups become prerequisites — heavier than a Hello World strictly needs.

## Known limitations

- **Controllers run on node-role permissions, not IRSA.** The load balancer
  controller and both CSI drivers take credentials from the node instance
  profile, whose custom policy grants `ec2:*`, `s3:*` and
  `secretsmanager:GetSecretValue` on `*`. Every pod on a node inherits that
  through IMDS, including the application pod. IRSA is enabled on the cluster and
  `oidc_provider_arn` is exported, but nothing consumes it yet. This is the
  largest open item.
- **Secrets are not encrypted with a customer key.** `kms_key_arn` defaults to
  `null`, so envelope encryption is off unless one is supplied. Flagged by Trivy
  as AWS-0039.
- **Nodes have unrestricted egress**, from the EKS module's recommended security
  group rules. Flagged by Trivy as AWS-0104. Closing it properly means VPC
  endpoints for ECR, S3, STS and the EKS API.
- **The node role's trust policy** uses a wildcard federated principal, which will
  surface as an error at apply time.
- **`replicaCount` defaults to 1** in both the chart and `app_replica_count`,
  despite the topology spread constraints being written for three. There is no
  PodDisruptionBudget, so a node drain can take every replica.
- **The application exposes no metrics.** `metrics.enabled` is off, so the
  ServiceMonitor is not rendered and Prometheus scrapes nothing from the app. The
  labels it needs are already correct on both sides.
- **No application-level alerts or dashboard.** Alerting and the Grafana
  dashboards are cluster-level.
- **`pipeline` and `.github` are gitignored**, so neither reaches a clone of this
  repository — and GitHub only runs workflows it can see under
  `.github/workflows`. Remove both entries from [.gitignore](.gitignore) before
  submitting.
- **Nothing builds or pushes an image.** The pipeline deploys a tag that must
  already exist in the registry, and there is no registry in the Terraform
  either — the default image comes from a public one.
- **No checks in CI.** `terraform fmt`/`validate`, `helm lint` and the Trivy scan
  in [terraform-trivy-scan.txt](terraform-trivy-scan.txt) were all run by hand.
- **Provider pins are old** — `kubernetes 2.10.0` and `helm 2.10.1`. Moving past
  helm 2.x means rewriting every `set {}` block as a list.
- **`modules/jaeger` hardcodes a manifest count.** Changing `istio_version` needs
  that count checked against the upstream file.

## Where the assignment requirements live

| Requirement | Where |
| --- | --- |
| EKS cluster via Terraform | [terraform/aws](terraform/aws) |
| Hello World microservice over HTTP | [helm-chart](helm-chart), `image: hashicorp/http-echo` serving `Hello World` on `:8080` |
| Helm chart for the deployment | [helm-chart](helm-chart), installed by `helm_release.app_release` |
| Prometheus and Grafana, service and cluster | [terraform/kubernetes/modules/monitoring](terraform/kubernetes/modules/monitoring) and the chart's ServiceMonitor |
| Deployment pipeline | [pipeline](pipeline) — GitHub Actions, OIDC to AWS, `helm upgrade` onto a new tag with `--atomic` rollback |
