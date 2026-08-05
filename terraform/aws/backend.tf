# Left commented so a first run needs nothing but AWS credentials. To use remote
# state, uncomment and run `terraform init -backend-config=backends/dev.hcl` —
# the bucket is reached with the same credentials, so local runs keep working.

# terraform {
#   backend "s3" {}
# }
