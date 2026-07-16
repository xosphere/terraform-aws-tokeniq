variable "name_prefix" {
  description = "Prefix for every named resource."
  type        = string
}

variable "vpc_id" {
  description = "VPC the Cloud Map private DNS namespace attaches to."
  type        = string
}

variable "discovery_namespace" {
  description = "Cloud Map private DNS namespace name."
  type        = string
}

variable "wal_bucket_name" {
  description = "WAL bucket name; empty string derives \"<name_prefix>-wal-<account_id>\"."
  type        = string
}

variable "create_kiro_tenant_key" {
  description = "Generate the Kiro sweep tenant key inside the module; false accepts var.kiro_tenant_key instead."
  type        = bool
}

variable "kiro_tenant_key" {
  description = "Externally supplied Kiro tenant key (only read when create_kiro_tenant_key is false)."
  type        = string
  default     = null
  ephemeral   = true
}

variable "kiro_tenant_key_version" {
  description = "Bump to rotate the Kiro tenant key secret version."
  type        = number
}
