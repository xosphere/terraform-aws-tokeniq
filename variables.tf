variable "vpc_id" {
  description = "VPC the data plane deploys into. Cloud Map private DNS is VPC-wide, so every consumer must live in (or peer with) this VPC."
  type        = string
}

variable "name_prefix" {
  description = "Prefix for every named resource (topics, queues, buckets, secrets, DNS namespace records). Change it to run multiple instances of the module in one account."
  type        = string
  default     = "tokeniq"
}

variable "discovery_namespace" {
  description = "Cloud Map private DNS namespace for in-VPC service discovery (collector.<namespace>, data-service.<namespace>)."
  type        = string
  default     = "tokeniq.local"
}

variable "wal_bucket_name" {
  description = "Name for the WAL S3 bucket. Empty string derives \"<name_prefix>-wal-<account_id>\"."
  type        = string
  default     = ""
}

variable "create_kiro_tenant_key" {
  description = "Generate the Kiro sweep tenant key inside the module (recommended). Set false to supply your own via kiro_tenant_key. Either way the plaintext never lands in Terraform state — it is written to Secrets Manager with a write-only argument."
  type        = bool
  default     = true
}

variable "kiro_tenant_key" {
  description = "Externally supplied Kiro sweep HMAC tenant key. Only read when create_kiro_tenant_key is false. Ephemeral: supply it at apply time; it is never persisted to state or plan."
  type        = string
  default     = null
  ephemeral   = true
}

variable "kiro_tenant_key_version" {
  description = "Bump to rotate the Kiro tenant key (rewrites the secret version). After rotating, every enrolled developer machine must re-run `tokeniq sync configure --force` with the new key."
  type        = number
  default     = 1
}
