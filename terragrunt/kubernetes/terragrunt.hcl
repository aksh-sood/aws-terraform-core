# The in-cluster stack: addons, istio, monitoring, logging, jaeger and the app.
# Every cluster coordinate it needs comes from the aws unit below.

include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  common = read_terragrunt_config(find_in_parent_folders("common.hcl"))
}

terraform {
  source = "${get_parent_terragrunt_dir()}/../terraform/kubernetes"
}

dependency "aws" {
  config_path = "../aws"

  # Lets plan and validate run before the cluster exists. `apply` and `destroy`
  # are deliberately absent, so those always use real outputs.
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "refresh"]

  mock_outputs = {
    region                             = local.common.locals.region
    cluster_name                       = local.common.locals.cluster_name
    cluster_endpoint                   = "https://000000000000000000000000000000.gr7.eu-west-2.eks.amazonaws.com"
    cluster_certificate_authority_data = "bW9jay1jZXJ0aWZpY2F0ZS1hdXRob3JpdHk="
    grafana_role_arn                   = "arn:aws:iam::000000000000:role/mock-grafana"
  }
}

inputs = merge(
  # terraform/aws names its outputs to match this stack's variables, so the whole
  # set is injected rather than mapped value by value. region, cluster_name,
  # cluster_endpoint, cluster_certificate_authority_data and grafana_role_arn are
  # the five that land; the rest have no matching variable here and are ignored,
  # because terragrunt passes inputs as TF_VAR_ environment variables and
  # terraform skips those it has no variable for.
  dependency.aws.outputs,

  {
    # Prerequisites from common.hcl, not produced by the cluster stack.
    domain_name                 = local.common.locals.domain_name
    acm_certificate_arn         = local.common.locals.acm_certificate_arn
    elb_security_group          = local.common.locals.elb_security_group
    internal_alb_security_group = local.common.locals.internal_alb_security_group

    # The chart sits at the repository root, outside this stack's directory.
    # terragrunt runs terraform against a copy of the source under
    # .terragrunt-cache, where the module-relative default cannot reach it.
    helm_chart_path = "${get_parent_terragrunt_dir()}/../helm-chart"
  },
)
