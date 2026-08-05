terraform {
  # terraform_data, used for the network preconditions in validations.tf
  required_version = ">= 1.4"

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


