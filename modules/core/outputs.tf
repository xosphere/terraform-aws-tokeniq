# --- Messaging ---
output "enrich_topic_arn" {
  description = "SNS topic the collector publishes one enrich event per turn to."
  value       = aws_sns_topic.enrich.arn
}

output "enricher_queue_urls" {
  description = "Per-enricher SQS queue URLs, keyed by enricher name."
  value       = { for k, q in aws_sqs_queue.enricher : k => q.url }
}

output "enricher_queue_arns" {
  description = "Per-enricher SQS queue ARNs, keyed by enricher name."
  value       = { for k, q in aws_sqs_queue.enricher : k => q.arn }
}

output "store_apply_queue_url" {
  description = "SQS queue the enrichers publish upsert batches to; drained by the store-writer."
  value       = aws_sqs_queue.store_apply.url
}

output "store_apply_queue_arn" {
  description = "ARN of the store-apply queue."
  value       = aws_sqs_queue.store_apply.arn
}

output "work_enrich_topic_arn" {
  description = "SNS topic the collector git-webhook ingest and enricher backfill publish WorkEvents to."
  value       = aws_sns_topic.work_enrich.arn
}

output "work_queue_url" {
  description = "SQS queue the pattern engine's WorkSQSRunner long-polls for WorkEvents."
  value       = aws_sqs_queue.work.url
}

output "work_queue_arn" {
  description = "ARN of the work queue."
  value       = aws_sqs_queue.work.arn
}

# --- WAL bucket ---
output "wal_bucket" {
  description = "Name of the WAL S3 bucket."
  value       = aws_s3_bucket.wal.bucket
}

output "wal_bucket_arn" {
  description = "ARN of the WAL S3 bucket."
  value       = aws_s3_bucket.wal.arn
}

# --- Secrets (ARNs only — values never leave Secrets Manager) ---
output "kiro_tenant_key_secret_arn" {
  description = "Secrets Manager ARN of the Kiro sweep tenant key."
  value       = aws_secretsmanager_secret.kiro_tenant_key.arn
}

output "gateway_tenant_key_secret_arn" {
  description = "Secrets Manager ARN of the gateway tenant key."
  value       = aws_secretsmanager_secret.gateway_tenant_key.arn
}

output "git_github_webhook_secret_arn" {
  description = "Secrets Manager ARN of the GitHub webhook secret."
  value       = aws_secretsmanager_secret.git_github_webhook_secret.arn
}

output "git_gitlab_webhook_token_secret_arn" {
  description = "Secrets Manager ARN of the GitLab webhook token."
  value       = aws_secretsmanager_secret.git_gitlab_webhook_token.arn
}

output "collector_auth_token_secret_arn" {
  description = "Secrets Manager ARN of the collector bearer token."
  value       = aws_secretsmanager_secret.collector_auth_token.arn
}

output "collector_tls_cert_secret_arn" {
  description = "Secrets Manager ARN of the collector TLS certificate (container; version written by the ingress module)."
  value       = aws_secretsmanager_secret.collector_tls_cert.arn
}

output "collector_tls_cert_secret_id" {
  description = "Secrets Manager ID of the collector TLS certificate container (the ingress module writes its version)."
  value       = aws_secretsmanager_secret.collector_tls_cert.id
}

output "collector_tls_key_secret_arn" {
  description = "Secrets Manager ARN of the collector TLS private key (container; version written by the ingress module)."
  value       = aws_secretsmanager_secret.collector_tls_key.arn
}

output "collector_tls_key_secret_id" {
  description = "Secrets Manager ID of the collector TLS key container (the ingress module writes its version)."
  value       = aws_secretsmanager_secret.collector_tls_key.id
}

output "data_service_auth_token_secret_arn" {
  description = "Secrets Manager ARN of the data-service bearer token."
  value       = aws_secretsmanager_secret.data_service_auth_token.arn
}

output "data_service_tls_cert_secret_arn" {
  description = "Secrets Manager ARN of the data-service TLS certificate (doubles as the client CA bundle)."
  value       = aws_secretsmanager_secret.data_service_tls_cert.arn
}

output "data_service_tls_key_secret_arn" {
  description = "Secrets Manager ARN of the data-service TLS private key."
  value       = aws_secretsmanager_secret.data_service_tls_key.arn
}

# --- Service discovery ---
output "service_discovery_namespace_id" {
  description = "Cloud Map private DNS namespace ID."
  value       = aws_service_discovery_private_dns_namespace.this.id
}

output "service_discovery_namespace_name" {
  description = "Cloud Map private DNS namespace name."
  value       = aws_service_discovery_private_dns_namespace.this.name
}

output "collector_service_discovery_arn" {
  description = "Cloud Map service ARN the collector ECS service registers into."
  value       = aws_service_discovery_service.collector.arn
}

output "data_service_service_discovery_arn" {
  description = "Cloud Map service ARN the data-service ECS service registers into."
  value       = aws_service_discovery_service.data_service.arn
}

output "collector_internal_endpoint" {
  description = "In-VPC collector base URL via service discovery."
  value       = "https://collector.${var.discovery_namespace}:8080"
}

output "data_service_internal_endpoint" {
  description = "In-VPC data-service base URL via service discovery."
  value       = "https://data-service.${var.discovery_namespace}:8080"
}
