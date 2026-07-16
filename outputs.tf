output "kiro_tenant_key_secret_arn" {
  description = "Secrets Manager ARN holding the Kiro sweep tenant key. Read the value out-of-band (aws secretsmanager get-secret-value) and hand it to developers via a secret channel — Terraform never exposes it."
  value       = module.core.kiro_tenant_key_secret_arn
}

output "wal_bucket" {
  description = "Name of the WAL S3 bucket (raw ingest payloads; fully private)."
  value       = module.core.wal_bucket
}

output "collector_internal_endpoint" {
  description = "In-VPC collector base URL via service discovery (stable across redeploys)."
  value       = module.core.collector_internal_endpoint
}

output "collector_security_group_id" {
  description = "Collector task security group ID (the ingress module adds its rules here)."
  value       = module.services.collector_security_group_id
}

output "collector_execution_role_arn" {
  description = "Collector ECS execution role ARN. When export is enabled, grant this role read on the vendor-hosted export tenant-key secret."
  value       = module.services.collector_execution_role_arn
}

output "enricher_execution_role_arn" {
  description = "Enricher ECS execution role ARN. When export is enabled, grant this role read on the vendor-hosted export tenant-key secret."
  value       = module.services.enricher_execution_role_arn
}
