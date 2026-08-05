# Values shared by both stacks, and the ones that change per environment.
#
# Everything marked REPLACE_ME is a prerequisite this repository does not create,
# so it has to be filled in before the first run. Leaving a placeholder in place
# makes the plan fail loudly rather than build against the wrong network.

locals {
  # ---- Remote state -------------------------------------------------------
  # The bucket and lock table must exist before the first `terragrunt init`.
  state_bucket     = "REPLACE_ME-terraform-state"
  state_lock_table = "REPLACE_ME-terraform-locks"
  state_region     = "eu-west-2"

  # ---- Shared by both stacks ---------------------------------------------
  region       = "eu-west-2"
  cluster_name = "lucidity-test"

  tags = {
    Environment = "lucidity-test"
    ManagedBy   = "terragrunt"
  }

  # ---- Network: must already exist ---------------------------------------
  # terraform/aws/validations.tf requires the private subnets to span at least
  # `minimum_availability_zones` (3 by default).
  vpc_id             = "REPLACE_ME"   # vpc-0123456789abcdef0
  private_subnet_ids = ["REPLACE_ME"] # subnet-..., three AZs
  public_subnet_ids  = ["REPLACE_ME"] # subnet-..., three AZs

  # ---- Ingress and DNS: consumed by the kubernetes stack ------------------
  domain_name                 = "REPLACE_ME" # example.com
  acm_certificate_arn         = "REPLACE_ME" # arn:aws:acm:eu-west-2:...:certificate/...
  elb_security_group          = "REPLACE_ME" # sg-..., public istio ALB
  internal_alb_security_group = "REPLACE_ME" # sg-..., internal istio ALB
}
