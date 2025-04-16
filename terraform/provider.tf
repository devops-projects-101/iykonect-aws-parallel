terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    bucket = "iykonect-aws-parallel"
    key    = "terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  #region = "eu-west-1"
  default_tags {
    tags = {
      ManagedBy = "terraform"
      Project   = "parallel"
    }
  }
}
