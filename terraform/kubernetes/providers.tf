terraform {
  required_version = ">= 1.3"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "=2.10.0"
    }
    kubectl = {
      source                = "gavinbunney/kubectl"
      version               = ">= 1.7.0"
      configuration_aliases = [kubectl.this]
    }
    helm = {
      source  = "hashicorp/helm"
      version = "=2.10.1"
    }
    # modules/monitoring reads the current region, and the DNS records below are
    # managed here.
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.54"
    }
    # Used by modules/istio and modules/monitoring for the basic-auth and
    # Grafana admin credentials.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    # modules/jaeger pulls the tracing manifests from the istio release.
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

# Credentials come from the environment, as in the aws stack.
provider "aws" {
  region = var.region
}

# The three Kubernetes providers all authenticate the same way: the cluster
# coordinates come from the aws stack, and the token is minted at apply time by
# the AWS CLI so it cannot go stale mid-run.
provider "kubernetes" {
  host                   = var.cluster_endpoint
  cluster_ca_certificate = base64decode(var.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.region]
  }
}

provider "helm" {
  kubernetes {
    host                   = var.cluster_endpoint
    cluster_ca_certificate = base64decode(var.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.region]
    }
  }
}

# Every module takes this one through its kubectl.this configuration alias.
provider "kubectl" {
  alias = "this"

  host                   = var.cluster_endpoint
  cluster_ca_certificate = base64decode(var.cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.region]
  }
}
