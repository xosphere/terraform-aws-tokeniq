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

variable "anthropic_api_url" {
  description = "Anthropic API endpoint. Override to route through LiteLLM or another proxy (e.g. http://litellm:4000/v1/messages)."
  type        = string
  default     = "https://api.anthropic.com/v1/messages"
}

variable "plan_analyzer_vpc_subnet_ids" {
  description = "Subnet IDs for the plan-analyzer Lambda VPC config. Required when the Anthropic API endpoint is in a private VPC (e.g. internal LiteLLM)."
  type        = list(string)
  default     = []
}

variable "plan_analyzer_vpc_security_group_ids" {
  description = "Security group IDs for the plan-analyzer Lambda VPC config."
  type        = list(string)
  default     = []
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
