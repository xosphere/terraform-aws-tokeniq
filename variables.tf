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
