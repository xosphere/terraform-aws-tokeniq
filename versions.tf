# Write-only secret arguments (secret_string_wo) require Terraform >= 1.11
# and AWS provider >= 5.83; ephemeral random_password requires random >= 3.7.
terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.83"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.7"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
  }
}
