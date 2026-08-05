# The VPC is a prerequisite, not something this stack creates. These checks fail
# the plan when it does not meet the assumptions the cluster is built on, which
# is cheaper than finding out from a half-built cluster or from an ingress that
# never gets an address.

data "aws_subnet" "private" {
  for_each = toset(var.private_subnet_ids)

  id = each.value
}

data "aws_subnet" "public" {
  for_each = toset(var.public_subnet_ids)

  id = each.value
}

locals {
  private_azs = distinct([for subnet in data.aws_subnet.private : subnet.availability_zone])
  public_azs  = distinct([for subnet in data.aws_subnet.public : subnet.availability_zone])

  subnets_in_other_vpcs = [
    for subnet in concat(values(data.aws_subnet.private), values(data.aws_subnet.public)) :
    subnet.id if subnet.vpc_id != var.vpc_id
  ]

  # The load balancer controller finds its subnets by tag — the ingresses in
  # terraform/kubernetes/modules/istio carry no subnets annotation. Untagged
  # subnets do not produce an error, the ingress just never gets an address.
  public_subnets_missing_tag = [
    for subnet in data.aws_subnet.public :
    subnet.id if !contains(keys(subnet.tags), "kubernetes.io/role/elb")
  ]

  private_subnets_missing_tag = [
    for subnet in data.aws_subnet.private :
    subnet.id if !contains(keys(subnet.tags), "kubernetes.io/role/internal-elb")
  ]
}

resource "terraform_data" "network_prerequisites" {
  input = {
    vpc_id             = var.vpc_id
    private_subnet_ids = var.private_subnet_ids
    public_subnet_ids  = var.public_subnet_ids
  }

  lifecycle {
    precondition {
      condition     = length(local.subnets_in_other_vpcs) == 0
      error_message = "Subnets ${join(", ", local.subnets_in_other_vpcs)} are not in ${var.vpc_id}."
    }

    precondition {
      condition     = length(local.private_azs) >= var.minimum_availability_zones
      error_message = "private_subnet_ids spans ${length(local.private_azs)} availability zone(s), minimum_availability_zones requires ${var.minimum_availability_zones}. Node groups are only as highly available as the subnets they are placed in."
    }

    precondition {
      condition     = length(local.public_azs) >= var.minimum_availability_zones
      error_message = "public_subnet_ids spans ${length(local.public_azs)} availability zone(s), minimum_availability_zones requires ${var.minimum_availability_zones}. An ALB needs a subnet in each zone it serves."
    }

    precondition {
      condition     = length(local.public_subnets_missing_tag) == 0
      error_message = "Public subnets ${join(", ", local.public_subnets_missing_tag)} are missing the kubernetes.io/role/elb tag, so the load balancer controller cannot place internet-facing load balancers in them."
    }

    precondition {
      condition     = length(local.private_subnets_missing_tag) == 0
      error_message = "Private subnets ${join(", ", local.private_subnets_missing_tag)} are missing the kubernetes.io/role/internal-elb tag, so the load balancer controller cannot place internal load balancers in them."
    }

    # Turning the public endpoint on is a deliberate act; leaving the allow list
    # empty at the same time is not.
    precondition {
      condition     = var.endpoint_public_access ? length(var.public_access_cidrs) > 0 : true
      error_message = "endpoint_public_access is on but public_access_cidrs is empty. List the CIDRs allowed to reach the API server."
    }
  }
}
