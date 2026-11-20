# The full customer deployment against Xosphere's hosted TokenIQ plane
# (Tier 3): collector, enricher, data service and gateway in this account;
# turn metadata exported to Xosphere over PrivateLink; gateway config
# authored in the TokenIQ console or CLI and delivered as signed bundles.
# Turn content never leaves this account.
#
# Everything a first install usually has to build around the module is
# here too: the two ACM certificates (DNS-validated in a public Route 53
# zone) and the Secrets Manager secrets. The module itself creates the
# collector and gateway DNS records, the PrivateLink interface endpoint and
# all IAM.
#
# Order of a first install (README.md has the commands):
#   1. Xosphere enables TokenIQ for your account and allow-lists this AWS
#      account on its ingest endpoint service.
#   2. terraform apply -target=aws_secretsmanager_secret.tenant_key -target=aws_secretsmanager_secret.anthropic_api_key
#   3. Put the secret VALUES with the AWS CLI (never in Terraform state).
#   4. terraform apply

provider "aws" {
  region = var.region
}

# --- Certificates ------------------------------------------------------------
#
# Both load balancers are internal, but ACM still validates through public
# DNS, so the validation records go in a public zone you control. The
# certificates' names can live in that zone or in a private zone
# (record_zone_id).

data "aws_route53_zone" "public" {
  name         = var.public_zone_name
  private_zone = false
}

locals {
  record_zone_id = var.record_zone_id != "" ? var.record_zone_id : data.aws_route53_zone.public.zone_id
  hostnames = {
    collector = var.collector_dns_name
    gateway   = var.gateway_dns_name
  }
}

resource "aws_acm_certificate" "this" {
  for_each = local.hostnames

  domain_name       = each.value
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "validation" {
  for_each = local.hostnames

  zone_id         = data.aws_route53_zone.public.zone_id
  name            = one(aws_acm_certificate.this[each.key].domain_validation_options).resource_record_name
  type            = one(aws_acm_certificate.this[each.key].domain_validation_options).resource_record_type
  records         = [one(aws_acm_certificate.this[each.key].domain_validation_options).resource_record_value]
  ttl             = 300
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  for_each = local.hostnames

  certificate_arn         = aws_acm_certificate.this[each.key].arn
  validation_record_fqdns = [aws_route53_record.validation[each.key].fqdn]
}

# --- Secrets -----------------------------------------------------------------
#
# Terraform creates the secrets; you put their values with the AWS CLI so
# they never land in Terraform state:
#
#   read -s TENANT_KEY && aws secretsmanager put-secret-value --secret-id tokeniq/hosted-tenant-key --secret-string "$TENANT_KEY"; unset TENANT_KEY
#   read -s ANTHROPIC_KEY && aws secretsmanager put-secret-value --secret-id tokeniq/anthropic-api-key --secret-string "$ANTHROPIC_KEY"; unset ANTHROPIC_KEY
#
# Both use the default aws/secretsmanager key, which the module's roles can
# decrypt.

# The tenant key Xosphere gives you: signs the metadata export and
# authenticates the gateway's bundle downloads.
resource "aws_secretsmanager_secret" "tenant_key" {
  name        = "tokeniq/hosted-tenant-key"
  description = "TokenIQ hosted-plane tenant key (from Xosphere)"
}

resource "aws_secretsmanager_secret" "anthropic_api_key" {
  name        = "tokeniq/anthropic-api-key"
  description = "Anthropic API key the TokenIQ gateway calls Anthropic with"
}

# --- TokenIQ -----------------------------------------------------------------

module "tokeniq" {
  source = "../.."

  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids

  # Your Xosphere account's tenant ID, exactly as Xosphere gives it.
  tenant_id      = var.tenant_id
  image_registry = var.image_registry
  image_tag      = var.image_tag

  # Collector ingress: internal NLB with ACM TLS (required with the gateway).
  tls_mode            = "acm"
  acm_certificate_arn = aws_acm_certificate_validation.this["collector"].certificate_arn
  route53_zone_id     = local.record_zone_id
  dns_name            = var.collector_dns_name

  # Metadata export to the hosted plane over PrivateLink. The module creates
  # the interface endpoint with private DNS, so the ingest hostname resolves
  # to it inside this VPC.
  export_endpoint                 = "https://tokeniq-ingest.xosphere.io:8080"
  export_tenant_key_secret_arn    = aws_secretsmanager_secret.tenant_key.arn
  export_privatelink_service_name = var.ingest_endpoint_service_name
  export_identity_user_mode       = var.identity_mode
  export_identity_team_mode       = var.identity_mode
  price_book_url                  = "https://xosphere-tokeniq-pricebook-143723790106.s3.us-west-2.amazonaws.com/v1/price-book.json"

  # Gateway, configured by signed bundles from the hosted plane.
  gateway_enabled                      = true
  gateway_image_tag                    = var.gateway_image_tag
  gateway_certificate_arn              = aws_acm_certificate_validation.this["gateway"].certificate_arn
  gateway_dns_name                     = var.gateway_dns_name
  gateway_allowed_ingress_cidrs        = var.gateway_allowed_ingress_cidrs
  gateway_bundle_url                   = "https://tokeniq-bundles.xosphere.io"
  gateway_bundle_tenant_key_secret_arn = aws_secretsmanager_secret.tenant_key.arn
  gateway_bundle_public_key            = var.gateway_bundle_public_key

  # Provider keys stay in this account; bundles refer to them by name.
  gateway_extra_secrets = {
    TOKENIQ_ANTHROPIC_API_KEY = aws_secretsmanager_secret.anthropic_api_key.arn
  }
}
