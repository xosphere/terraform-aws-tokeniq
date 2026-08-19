variable "name_prefix" {
  description = "Prefix for every named resource, inherited from the root module."
  type        = string
}

variable "vpc_id" {
  description = "VPC the gateway deploys into."
  type        = string
}

variable "private_subnet_ids" {
  description = "Subnets for the gateway ECS tasks."
  type        = list(string)
}

variable "alb_subnet_ids" {
  description = "Subnets for the gateway ALB (private for an internal ALB, public when internal = false)."
  type        = list(string)
}

variable "internal" {
  description = "Whether the gateway ALB is internal. Internet-facing is an explicit opt-in; the gateway authenticates every request, but keeping the ALB internal removes the exposed surface entirely."
  type        = bool
  default     = true
}

variable "allowed_ingress_cidrs" {
  description = "CIDR blocks allowed to reach the gateway ALB on 443. Include developer/VPN ranges and, when the session analyzer targets the gateway, the VPC CIDR."
  type        = list(string)
}

variable "certificate_arn" {
  description = "ACM certificate for the gateway ALB HTTPS listener."
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 zone for the gateway alias record. Leave empty (with dns_name) to skip DNS."
  type        = string
  default     = ""
}

variable "dns_name" {
  description = "Hostname for the gateway alias record (must be covered by certificate_arn)."
  type        = string
  default     = ""
}

variable "cluster_arn" {
  description = "ECS cluster to run the gateway service on."
  type        = string
}

variable "image" {
  description = "Full gateway image reference (registry/repository:tag)."
  type        = string
}

variable "cpu" {
  description = "Fargate CPU units for the gateway task."
  type        = number
  default     = 512
}

variable "memory" {
  description = "Fargate memory (MiB) for the gateway task."
  type        = number
  default     = 1024
}

variable "cpu_architecture" {
  description = "Task CPU architecture. The published images are multi-arch."
  type        = string
  default     = "ARM64"

  validation {
    condition     = contains(["ARM64", "X86_64"], var.cpu_architecture)
    error_message = "cpu_architecture must be ARM64 or X86_64."
  }
}

variable "desired_count" {
  description = "Number of gateway tasks. The gateway is stateless; scale freely."
  type        = number
  default     = 1
}

variable "tenant_id" {
  description = "TokenIQ tenant identifier, presented on the authenticated bundle poll and stamped on telemetry."
  type        = string
}

variable "bundle_public_key" {
  description = "Hex-encoded Ed25519 public key the gateway verifies every bundle against (from `tokeniq gateway init`, or the hosted console in Tier 3). The trust anchor — deliberately delivered out of band from the bundles it authenticates."
  type        = string
}

variable "bundle_url" {
  description = "Bundle-source base URL. Empty (default) creates a module-owned public-read S3 bucket (Tier 2). Set to the hosted config-distributor URL for Tier 3, together with bundle_tenant_key_secret_arn."
  type        = string
  default     = ""
}

variable "bundle_seed_path" {
  description = "Local path to a signed bundle used to seed the Tier 2 bucket on first apply (the cache/bundle.signed.json from `tokeniq gateway init`). Subsequent publishes happen out-of-band; the object ignores later changes to this file."
  type        = string
  default     = ""
}

variable "bundle_tenant_key_secret_arn" {
  description = "Secrets Manager ARN of the tenant resolver key, presented as the bundle-poll Bearer. Required for (and only used with) a Tier 3 distributor bundle_url."
  type        = string
  default     = ""
}

variable "collector_endpoint" {
  description = "Collector base URL the gateway pushes turn telemetry to (the root module wires the ingress collector_endpoint). Must present a certificate the gateway trusts — ingress tls_mode \"acm\"."
  type        = string
}

variable "telemetry_tenant_key_secret_arn" {
  description = "Secrets Manager ARN of the shared gateway/collector HMAC key (modules/core gateway_tenant_key)."
  type        = string
}

variable "bedrock_enabled" {
  description = "Register the Bedrock serving adapter; the task role carries the invoke grant."
  type        = bool
  default     = false
}

variable "bedrock_served_models" {
  description = "Bedrock models the gateway may invoke: bare on-demand foundation-model IDs or full ARNs (inference profiles, provisioned throughput)."
  type        = list(string)
  default     = []
}

variable "alb_idle_timeout" {
  description = "ALB idle timeout in seconds. Must exceed write_timeout (timeout ladder: upstream attempt < write timeout < ALB idle)."
  type        = number
  default     = 360
}

variable "write_timeout" {
  description = "Gateway HTTP write timeout (Go duration). Keep under alb_idle_timeout and above upstream_total_timeout."
  type        = string
  default     = "330s"
}

variable "upstream_total_timeout" {
  description = "Per-attempt upstream budget (Go duration). Each of the retry loop's attempts gets a fresh one."
  type        = string
  default     = "280s"
}

variable "alb_deletion_protection" {
  description = "Enable ALB deletion protection."
  type        = bool
  default     = true
}

variable "admin_token_rotation_version" {
  description = "Bump to rotate the admin console token, then redeploy the gateway."
  type        = number
  default     = 1
}

variable "log_retention_days" {
  description = "CloudWatch log retention for the gateway log group."
  type        = number
  default     = 30
}

variable "extra_environment" {
  description = "Additional TOKENIQ_* environment variables (provider base URLs, feature toggles). Never put credentials here — use extra_secrets."
  type        = map(string)
  default     = {}
}

variable "extra_secrets" {
  description = "Additional container secrets as env-name => Secrets Manager ARN (provider API keys such as TOKENIQ_ANTHROPIC_API_KEY, SSO client credentials). Provider keys stay in the customer account by design — they never ride in bundles."
  type        = map(string)
  default     = {}
}
