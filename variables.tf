variable "version" {
  description = "TokenIQ version"
  type        = string
  default     = "0.1.0"
}

variable "retention_days" {
  description = "Number of days to retain raw turn data in S3"
  type        = number
  default     = 365
}

variable "lambda_memory_size" {
  description = "Memory size (MB) for the ingest Lambda"
  type        = number
  default     = 256
}

variable "lambda_timeout" {
  description = "Timeout (seconds) for the ingest Lambda"
  type        = number
  default     = 60
}

variable "anthropic_api_key" {
  description = "Anthropic API key for plan time estimation. When provided, the plan-analyzer Lambda is deployed."
  type        = string
  default     = ""
  sensitive   = true
}

variable "grafana_enabled" {
  description = "Enable Grafana dashboard infrastructure (API Gateway + query Lambda + optional AMG workspace)"
  type        = bool
  default     = false
}

variable "grafana_auth_provider" {
  description = "Authentication provider for Amazon Managed Grafana workspace"
  type        = string
  default     = "AWS_SSO"
  validation {
    condition     = contains(["AWS_SSO", "SAML"], var.grafana_auth_provider)
    error_message = "Must be AWS_SSO or SAML."
  }
}
