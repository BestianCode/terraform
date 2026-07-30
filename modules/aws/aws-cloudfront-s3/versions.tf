terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.57"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 5.0.0"
    }
  }
}
