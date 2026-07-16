variable "name_prefix" {
  description = "Prefix for the intake queue and EventBridge rule names."
  type        = string
}

variable "litellm_events_bucket" {
  description = "Name of the customer's existing LiteLLM raw-events S3 bucket. This module never creates or modifies the bucket — the customer must enable EventBridge notifications on it themselves (aws_s3_bucket_notification eventbridge = true, or the console equivalent)."
  type        = string
}

variable "litellm_events_prefix" {
  description = "Optional S3 key prefix (LiteLLM s3_path) to scope intake to LiteLLM objects when the bucket is shared. Empty ingests every Object Created event on the bucket."
  type        = string
  default     = ""
}
