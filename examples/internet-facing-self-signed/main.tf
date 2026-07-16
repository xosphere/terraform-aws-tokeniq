# No-domain topology: internet-facing NLB with TCP passthrough to the
# collector's self-signed certificate. No ACM certificate, no Route 53 zone,
# no VPN — but the NLB is exposed to the CIDRs you list, so scope
# allowed_ingress_cidrs tightly to your developers' egress IPs (never
# 0.0.0.0/0), and prefer the internal-acm topology when a VPN is available.
#
# Developers must trust the collector CA:
#   terraform output -raw collector_ca_pem > collector-ca.pem
# and pass it to tokeniq sync configure --collector-ca (the
# developer_onboarding_command output includes the flag).

terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.83"
    }
  }
}

provider "aws" {
  region = var.region
}

module "tokeniq" {
  source = "../.."

  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids
  public_subnet_ids  = var.public_subnet_ids

  tenant_id      = var.tenant_id
  image_registry = var.image_registry

  internet_facing       = true
  allowed_ingress_cidrs = var.developer_egress_cidrs
  tls_mode              = "self_signed"
}
