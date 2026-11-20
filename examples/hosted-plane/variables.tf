variable "region" {
  description = "Region to deploy in. The hosted plane's ingest endpoint service is in us-west-2, and PrivateLink is regional."
  type        = string
  default     = "us-west-2"
}

variable "vpc_id" {
  description = "VPC to deploy into."
  type        = string
}

variable "private_subnet_ids" {
  description = "Two or more private subnets with NAT egress, in the ingest endpoint service's AZs: usw2-az1, usw2-az2 or usw2-az3 (AZ IDs, not names)."
  type        = list(string)
}

variable "tenant_id" {
  description = "Your TokenIQ tenant ID, from Xosphere (your Xosphere account ID, a 26-character ULID)."
  type        = string

  validation {
    condition     = can(regex("^[0-9A-HJKMNP-TV-Z]{26}$", var.tenant_id))
    error_message = "tenant_id must be the 26-character ID Xosphere gave you."
  }
}

variable "hosted_tenant_key_secret_arn" {
  description = "Your tenant key's secret ARN in Xosphere's account, shown in the TokenIQ console after you connect this AWS account (Configure TokenIQ → Connect your AWS account). Read cross-account; no copy is made. Empty (fallback only): create a local tokeniq/hosted-tenant-key secret and put the key Xosphere sends you into it."
  type        = string
  default     = ""

  validation {
    condition     = var.hosted_tenant_key_secret_arn == "" || can(regex("^arn:aws:secretsmanager:us-west-2:[0-9]{12}:secret:tokeniq/tenant/[0-9A-HJKMNP-TV-Z]{26}/hmac-key-[A-Za-z0-9]{6}$", var.hosted_tenant_key_secret_arn))
    error_message = "hosted_tenant_key_secret_arn must be the full secret ARN the TokenIQ console shows (arn:aws:secretsmanager:us-west-2:<account>:secret:tokeniq/tenant/<tenant ID>/hmac-key-XXXXXX), or empty."
  }
}

variable "public_zone_name" {
  description = "Public Route 53 zone used for ACM DNS validation (e.g. example.com)."
  type        = string
}

variable "record_zone_id" {
  description = "Route 53 zone for the collector and gateway records. Empty: the public zone. Use a private zone to keep the internal names out of public DNS."
  type        = string
  default     = ""
}

variable "collector_dns_name" {
  description = "Hostname for the collector (e.g. tokeniq-collector.example.com)."
  type        = string
}

variable "gateway_dns_name" {
  description = "Hostname developers point Claude Code at (e.g. tokeniq-gateway.example.com)."
  type        = string
}

variable "gateway_allowed_ingress_cidrs" {
  description = "CIDRs allowed to reach the gateway: your VPN or office ranges, plus the VPC CIDR."
  type        = list(string)
}

variable "gateway_bundle_public_key" {
  description = "Your tenant's bundle-signing public key (64 hex characters), from `tokeniq gateway config signing-key --quiet` or the TokenIQ console."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{64}$", var.gateway_bundle_public_key))
    error_message = "gateway_bundle_public_key must be 64 lowercase hex characters, with no newline."
  }
}

variable "ingest_endpoint_service_name" {
  description = "The hosted plane's ingest PrivateLink service."
  type        = string
  default     = "com.amazonaws.vpce.us-west-2.vpce-svc-05310106e56ed7eb9"
}

variable "identity_mode" {
  description = "How user and team identities are exported: \"plaintext\" (emails, team names) or \"pseudonymous\" (HMAC'd with a key that never leaves this account)."
  type        = string
  default     = "plaintext"

  validation {
    condition     = contains(["plaintext", "pseudonymous"], var.identity_mode)
    error_message = "identity_mode must be \"plaintext\" or \"pseudonymous\"."
  }
}

variable "image_registry" {
  description = "Registry the TokenIQ images are pulled from."
  type        = string
  default     = "docker.io/xosphere"
}

variable "image_tag" {
  description = "Collector, enricher and data service image tag."
  type        = string
  default     = "0.1.0"
}

variable "gateway_image_tag" {
  description = "Gateway image tag."
  type        = string
  default     = "0.2.0"
}

variable "gateway_redis_mode" {
  description = "Shared Redis for the gateway: \"bundled\" (recommended; a two-node ElastiCache Valkey replication group reachable only from the gateway, about $37/month) or \"none\" (per-task rate limits, budgets off, no response cache)."
  type        = string
  default     = "bundled"
}
