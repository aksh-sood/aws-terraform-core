# Root configuration, included by every unit. It owns the state layout and the
# inputs both stacks share; everything environment-specific lives in common.hcl.
#
# Named root.hcl rather than terragrunt.hcl on purpose: run-all and
# graph-dependencies treat every terragrunt.hcl they find as a unit to run, and
# this file is only ever included.

locals {
  common = read_terragrunt_config(find_in_parent_folders("common.hcl"))
}

# terraform/aws/backend.tf is a commented-out stub and the kubernetes stack has
# no backend file at all, so the block is generated here instead. That keeps the
# state layout in one place and gives each unit its own key.
remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite"
  }

  config = {
    bucket = local.common.locals.state_bucket

    # Resolves to aws/terraform.tfstate and kubernetes/terraform.tfstate
    key = "${path_relative_to_include()}/terraform.tfstate"

    region         = local.common.locals.state_region
    encrypt        = true
    dynamodb_table = local.common.locals.state_lock_table
  }
}

# Both stacks declare `region`; everything else is set by the unit that needs it.
inputs = {
  region = local.common.locals.region
}
