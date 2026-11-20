# Cross-plane PrivateLink — consumer side.
#
# The customer data plane reaches the vendor-hosted plane's ingest service ONLY
# through this interface endpoint — never via VPC peering (the two planes stay
# unpeered). The vendor owns the endpoint service and publishes its service
# name out-of-band during onboarding; this module consumes that name as an
# input variable. The endpoint service publishes a verified private DNS name,
# so enabling private DNS makes the export_endpoint hostname resolve to these
# endpoint ENIs inside the VPC — the exporters dial it over TLS against the
# vendor's public-CA cert (no ServerName pin, no CA PEM).
#
# Only content-free metadata crosses this link — LLM turn content never leaves
# the customer account.

data "aws_vpc" "this" {
  id = var.vpc_id
}

resource "aws_security_group" "export_endpoint" {
  name_prefix = "${var.name_prefix}-export-endpoint-"
  description = "TokenIQ hosted-plane export interface endpoint"
  vpc_id      = var.vpc_id

  ingress {
    description = "Hosted-plane ingest from within the VPC (the exporters). Port must match the port in export_endpoint."
    from_port   = var.ingest_port
    to_port     = var.ingest_port
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.this.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_region" "current" {}

locals {
  # The service's own region: explicit, else parsed from its name.
  service_region = var.service_region != "" ? var.service_region : try(regex("^com\\.amazonaws\\.vpce\\.([a-z0-9-]+)\\.vpce-svc-", var.endpoint_service_name)[0], "")
  # TIQ-395: a service in another region is reached through cross-region PrivateLink. AWS
  # doesn't support cross-region endpoint ENIs in some AZs (for example use1-az3); avoid
  # those subnets. The deploying principal needs vpce:AllowMultiRegion.
  cross_region = local.service_region != "" && local.service_region != data.aws_region.current.name
}

resource "aws_vpc_endpoint" "ingest" {
  vpc_id            = var.vpc_id
  service_name      = var.endpoint_service_name
  service_region    = local.cross_region ? local.service_region : null
  vpc_endpoint_type = "Interface"
  subnet_ids        = var.subnet_ids

  security_group_ids = [aws_security_group.export_endpoint.id]

  private_dns_enabled = true

  tags = {
    Name = "${var.name_prefix}-hosted-ingest"
  }
}
