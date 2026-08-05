# Partial backend configuration. Uncomment the backend block in backend.tf, then
#
#   terraform init -backend-config=backends/dev.hcl
#
# Same bucket as the aws stack, different key, so terraform_remote_state can
# read one from the other if you decide to wire the handover that way.

bucket = "REPLACE-terraform-state-bucket"
key    = "kubernetes/terraform.tfstate"
region = "us-east-1"

encrypt = true

# S3 native locking. Replaces the dynamodb_table argument, which is deprecated
# as of Terraform 1.11 and AWS provider 6.x.
use_lockfile = true
