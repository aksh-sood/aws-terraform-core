# terragrunt

Runs the two Terraform stacks as one ordered pipeline: remote state configured in
one place, the handover between them automatic, and a single file holding
everything that changes per environment.

The stacks under [../terraform](../terraform/README.md) stay usable on their own.
This directory wraps them; it does not replace them.

```
root.hcl      remote state layout, included by every unit
common.hcl    the values that change per environment
aws/          unit → ../terraform/aws
kubernetes/   unit → ../terraform/kubernetes, depends on aws
```

## What it removes

Applied directly, the two stacks need three things done by hand: a backend block
per stack, a `terraform output -json | jq` step between the applies, and the same
prerequisite values entered into two `.tfvars` files.

| Done by hand | Done here |
| --- | --- |
| `backend.tf` per stack | `remote_state` in [root.hcl](root.hcl), generated into each unit with its own key |
| `terraform output -json \| jq … > aws.auto.tfvars.json` | `dependency "aws"` in [kubernetes/terragrunt.hcl](kubernetes/terragrunt.hcl) |
| `region`, `cluster_name` and the network in two tfvars files | Once in [common.hcl](common.hcl) |
| Applying `aws` before `kubernetes` | The dependency graph, so `run-all` orders them |

## Running it

Fill in every `REPLACE_ME` in [common.hcl](common.hcl) first — the state bucket
and lock table, the VPC and subnets, the domain, certificate and the two ALB
security groups. The bucket and table must already exist; nothing here creates
them.

```bash
cd terragrunt

terragrunt run-all plan            # both units, aws first
terragrunt run-all apply

# or one at a time
cd aws        && terragrunt apply
cd ../kubernetes && terragrunt apply
```

`run-all destroy` walks the graph in reverse, tearing down `kubernetes` before
`aws`.

## How the handover works

`terraform/aws` names every output after the variable of the same name in
`terraform/kubernetes`, which is what makes this a single line:

```hcl
inputs = merge(dependency.aws.outputs, { … })
```

Five values land — `region`, `cluster_name`, `cluster_endpoint`,
`cluster_certificate_authority_data`, `grafana_role_arn`. The rest of the aws
stack's outputs have no matching variable and are ignored: terragrunt passes
inputs as `TF_VAR_` environment variables, and Terraform silently skips ones it
has no variable for. That is why merging the whole output map is safe rather than
noisy.

**Renaming an output on one side means renaming the variable on the other.** The
merge is the only thing holding the two names together, and nothing will fail
loudly if they drift — the variable just falls back to its default, or the plan
asks for a value that should have been supplied.

### Mock outputs

The `kubernetes` unit can `plan` before the cluster exists, using the placeholder
endpoint and CA in its `dependency` block. `apply` and `destroy` are deliberately
absent from `mock_outputs_allowed_terraform_commands`, so those always run against
real outputs and can never build against a fake endpoint.

## Things worth knowing

- **`root.hcl`, not `terragrunt.hcl`.** `run-all` and `graph-dependencies` treat
  every `terragrunt.hcl` they find as a unit to execute. Naming the shared file
  `root.hcl` keeps it include-only, so the root directory is not itself run.
- **The generated `backend.tf` overwrites the stack's own.** Both stacks ship a
  commented-out backend stub; `if_exists = "overwrite"` replaces it inside
  `.terragrunt-cache`, leaving the file in `terraform/` untouched. Running the
  stacks directly still uses local state.
- **`helm_chart_path` is passed explicitly.** Terragrunt runs Terraform against a
  copy of the source under `.terragrunt-cache`, from where the chart's default
  module-relative path cannot reach the repository root. The `kubernetes` unit
  passes an absolute path instead.
- **The private API endpoint applies here too.** `endpoint_public_access` defaults
  to `false`, so whatever runs `terragrunt apply` on the `kubernetes` unit has to
  be inside the VPC — see
  [reaching a private cluster](../terraform/kubernetes/README.md#reaching-a-private-cluster).
- **State locking uses `dynamodb_table`**, which needs the table to exist.
  Terraform 1.11+ and AWS provider 6.x support S3-native locking (`use_lockfile`)
  instead, which needs no table at all.
- **One environment today.** `common.hcl` holds a single set of values. A second
  environment means a directory per environment, each with its own `common.hcl`
  and `aws`/`kubernetes` units — the structure already supports it, nothing is
  hardcoded to `lucidity-test` outside that file.
