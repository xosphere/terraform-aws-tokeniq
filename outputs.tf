output "kiro_tenant_key_secret_arn" {
  description = "Secrets Manager ARN holding the Kiro sweep tenant key. Read the value out-of-band (aws secretsmanager get-secret-value) and hand it to developers via a secret channel — Terraform never exposes it."
  value       = module.core.kiro_tenant_key_secret_arn
}

output "wal_bucket" {
  description = "Name of the WAL S3 bucket (raw ingest payloads; fully private)."
  value       = module.core.wal_bucket
}
