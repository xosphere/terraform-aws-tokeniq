# Data plane + gateway: the full TokenIQ customer deployment. The
# collector ingress runs in "acm" mode — a requirement when the gateway
# is enabled, because the gateway pushes turn telemetry to the collector
# endpoint and its client trusts system roots only.
#
# Before the first apply, generate the gateway's trust anchor and starter
# bundle locally:
#
#   tokeniq gateway init --provider anthropic --dir ./tokeniq-quickstart
#
# then point bundle_public_key at the printed public key and
# gateway_bundle_seed_path at ./tokeniq-quickstart/cache/bundle.signed.json.

terraform {
  required_version = ">= 1.11"
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
  image_tag      = var.image_tag

  # Collector ingress: internal NLB, ACM TLS (required for the gateway's
  # telemetry push).
  tls_mode            = "acm"
  acm_certificate_arn = var.collector_certificate_arn
  route53_zone_id     = var.route53_zone_id
  dns_name            = var.collector_dns_name

  # Gateway.
  gateway_enabled               = true
  gateway_image_tag             = var.gateway_image_tag
  gateway_allowed_ingress_cidrs = var.gateway_allowed_ingress_cidrs
  gateway_certificate_arn       = var.gateway_certificate_arn
  gateway_dns_name              = var.gateway_dns_name
  gateway_bundle_public_key     = var.gateway_bundle_public_key
  gateway_bundle_seed_path      = var.gateway_bundle_seed_path

  # Optional: let the gateway serve Bedrock models with the task role as
  # the credential.
  gateway_bedrock_enabled       = length(var.gateway_bedrock_served_models) > 0
  gateway_bedrock_served_models = var.gateway_bedrock_served_models

  # Provider API keys stay in the customer account: create the secrets
  # out-of-band and reference them here. They never ride in bundles or
  # reach the hosted plane.
  gateway_extra_secrets = var.gateway_provider_key_secret_arns
}
