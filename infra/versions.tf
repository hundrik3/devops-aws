terraform {
  required_version = "~> 1.13.0"
  required_providers {
    aws = {
      source = "hashicorp/aws", version = "~> 6.0"
    }

    random = {
      source = "hashicorp/random", version = "~> 3.7"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project = var.name, ManagedBy = "Terraform", Purpose = "PortfolioLab"
    }
  }
}

provider "aws" {
  alias  = "edge"
  region = "us-east-1"
  default_tags {
    tags = {
      Project = var.name, ManagedBy = "Terraform"
    }
  }
}
