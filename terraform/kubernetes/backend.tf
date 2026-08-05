# Keep this stack's state separate from the aws stack's, in the same bucket.
# Both have to be remote before the outputs of one can be read as the inputs of
# the other through terraform_remote_state.

# terraform {
#   backend "s3" {
#     bucket         = "my-terraform-state-bucket"
#     key            = "kubernetes/terraform.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "terraform-state-lock"
#     encrypt        = true
#   }
# }
