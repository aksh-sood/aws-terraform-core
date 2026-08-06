# Root configuration, included by every unit. It owns the state layout and the
# inputs both stacks share; everything environment-specific lives in common.hcl.
#
# Named root.hcl rather than terragrunt.hcl on purpose: run-all and
# graph-dependencies treat every terragrunt.hcl they find as a unit to run, and
# this file is only ever included.

locals {
  common = read_terragrunt_config(find_in_parent_folders("common.hcl"))
}

# Both stacks ship a commented-out backend.tf, so the real block is generated
# here and written into each unit's working copy. That keeps the state layout in
# one place and gives every unit its own key under one bucket.
#
# The bucket and the lock table are created on the first run if they do not
# already exist: terragrunt does that itself, enabling versioning, server-side
# encryption, public access blocking and enforced TLS on anything it creates. The
# skip_bucket_* keys would opt out of those, so none are set here. Interactive
# runs prompt before creating; pass --terragrunt-non-interactive in CI.
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

    # Applied only to resources terragrunt creates itself.
    s3_bucket_tags                 = local.common.locals.tags
    dynamodb_table_tags            = local.common.locals.tags
    enable_lock_table_ssencryption = true
  }
}

# Both stacks declare `region`; everything else is set by the unit that needs it.
inputs = {
  region = local.common.locals.region
}
