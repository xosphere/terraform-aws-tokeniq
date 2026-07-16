# Recommended production topology: internal NLB reached over VPN/DirectConnect,
# TLS terminated with an ACM certificate — developers need zero TLS config
# (system roots), and nothing is exposed to the internet.

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

  tenant_id      = var.tenant_id
  image_registry = var.image_registry

  # Internal NLB (the default). Developers reach it over the VPN; the empty
  # allowed_ingress_cidrs default admits the whole VPC CIDR, which covers
  # VPN/peering ranges routed into it.
  tls_mode            = "acm"
  acm_certificate_arn = var.acm_certificate_arn
  dns_name            = var.dns_name
  route53_zone_id     = var.route53_zone_id
}
