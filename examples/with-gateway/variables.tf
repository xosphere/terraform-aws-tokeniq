variable "region" {
  description = "AWS region to deploy into."
  type        = string
}

variable "vpc_id" {
  description = "VPC for the data plane and gateway."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets (two or more AZs recommended)."
  type        = list(string)
}

variable "tenant_id" {
  description = "TokenIQ tenant identifier."
  type        = string
}

variable "image_registry" {
  description = "Registry holding the TokenIQ images (your ECR mirror, or docker.io/xosphere)."
  type        = string
}

variable "image_tag" {
  description = "Released tag for the three data-plane service images."
  type        = string
}

variable "gateway_image_tag" {
  description = "Released tag for the gateway image."
  type        = string
}

variable "collector_certificate_arn" {
  description = "ACM certificate covering collector_dns_name."
  type        = string
}

variable "collector_dns_name" {
  description = "Hostname for the collector NLB."
  type        = string
}

variable "gateway_certificate_arn" {
  description = "ACM certificate covering gateway_dns_name."
  type        = string
}

variable "gateway_dns_name" {
  description = "Hostname for the gateway ALB."
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 zone for both hostnames."
  type        = string
}

variable "gateway_allowed_ingress_cidrs" {
  description = "CIDRs allowed to reach the gateway (developer/VPN ranges; include the VPC CIDR if the session analyzer targets the gateway)."
  type        = list(string)
}

variable "gateway_bundle_public_key" {
  description = "Hex Ed25519 public key from `tokeniq gateway init`."
  type        = string
}

variable "gateway_bundle_seed_path" {
  description = "Path to cache/bundle.signed.json from `tokeniq gateway init` (seeds the bundle bucket on first apply)."
  type        = string
  default     = ""
}

variable "gateway_bedrock_served_models" {
  description = "Bedrock models the gateway may serve (empty disables the adapter)."
  type        = list(string)
  default     = []
}

variable "gateway_provider_key_secret_arns" {
  description = "Provider API keys as env-name => Secrets Manager ARN (e.g. { TOKENIQ_ANTHROPIC_API_KEY = \"arn:aws:secretsmanager:...\" })."
  type        = map(string)
  default     = {}
}
