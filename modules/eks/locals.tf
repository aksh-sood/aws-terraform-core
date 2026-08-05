locals {
  # Injected into every node group so callers only describe the shape of the
  # group, not the wiring. Any key here can still be overridden per group.
  node_groups = {
    for name, group in var.node_groups : name => merge({
      # Node role is managed by the iam module
      create_iam_role = false
      iam_role_arn    = var.node_role_arn

      # Nodes reach the control plane through the primary security group EKS
      # creates for the cluster.
      attach_cluster_primary_security_group = true
    }, group)
  }
}