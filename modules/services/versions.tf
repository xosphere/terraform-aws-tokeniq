terraform {
  # >= 1.11 matches the root: write-only arguments and ephemeral values are used
  # by sibling modules, and cross-variable validation (used here) needs >= 1.9.
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.83"
    }
  }
}
