# Partial backend configuration. Uncomment the backend block in backend.tf, then
#
#   terraform init -backend-config=backends/dev.hcl
#
# The same AWS credentials already in your environment are used for the bucket,
# so this works for local runs as well as CI. For a throwaway local run with no
# bucket at all, leave backend.tf commented and state stays on disk.

bucket = "REPLACE-terraform-state-bucket"
key    = "aws/terraform.tfstate"
region = "us-east-1"

encrypt = true

# S3 native locking. Replaces the dynamodb_table argument, which is deprecated
# as of Terraform 1.11 and AWS provider 6.x.
use_lockfile = true
