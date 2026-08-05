terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.54"
    }
  }
}

# Please provide your AWS credentials in the environment variables.

provider "aws" {
  region = var.region
}


