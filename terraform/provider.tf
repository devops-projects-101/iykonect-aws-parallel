terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    bucket = "iykonect-aws-parallel-3793"
    key    = "terraform.tfstate"
    #region = "us-east-1"
  }
}

# provider "aws" {
#   region = "us-east-1"
# }
