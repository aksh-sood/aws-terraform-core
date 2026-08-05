# Left commented so a first run needs nothing but AWS credentials. To use remote
# state, uncomment and run `terraform init -backend-config=backends/dev.hcl`.
# Both stacks have to be remote before the outputs of one can be read as the
# inputs of the other through terraform_remote_state.

# terraform {
#   backend "s3" {}
# }
