# Load balancer controller add on
resource "helm_release" "lbc_addon" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = var.lbc_addon_version
  set {
    name  = "clusterName"
    value = var.cluster_name
  }

}

