terraform {
  required_version = ">= 1.6.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.33"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Local state is used intentionally for the sandbox (see ADR-006).
  # To migrate to a remote S3 + DynamoDB backend:
  #   1. Create the bucket and DynamoDB table out-of-band (bootstrap).
  #   2. Uncomment the block below and set the bucket/table names.
  #   3. Run: terraform init -migrate-state
  #
  # backend "s3" {
  #   bucket         = "platform-foundation-tfstate-<account-id>"
  #   key            = "platform-sandbox/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "platform-foundation-tf-locks"
  #   encrypt        = true
  # }
}
