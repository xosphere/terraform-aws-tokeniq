output "kiro_tenant_key_secret_arn" {
  description = "Secrets Manager ARN holding the Kiro sweep tenant key. Read the value out-of-band (aws secretsmanager get-secret-value) and hand it to developers via a secret channel — Terraform never exposes it."
  value       = module.core.kiro_tenant_key_secret_arn
}

output "wal_bucket" {
  description = "Name of the WAL S3 bucket (raw ingest payloads; fully private)."
  value       = module.core.wal_bucket
}

output "collector_endpoint" {
  description = "Base URL developers point tokeniq sync at: the custom DNS name when set, else the NLB DNS name (stable across redeploys), else the in-VPC Cloud Map name."
  value       = module.ingress.collector_endpoint
}

output "nlb_dns_name" {
  description = "DNS name of the collector NLB. Empty when create_load_balancer = false."
  value       = module.ingress.nlb_dns_name
}

output "collector_ca_pem" {
  description = "PEM certificate developers must trust (tls_mode = \"self_signed\" or no load balancer); empty in \"acm\" mode. Save it with: terraform output -raw collector_ca_pem > collector-ca.pem"
  value       = module.ingress.collector_ca_pem
  sensitive   = true
}

output "developer_onboarding_command" {
  description = "Paste-ready enrollment command to hand developers. The tenant key is deliberately NOT embedded — developers paste it at the prompt; read it out of the kiro_tenant_key_secret_arn secret and share it over a secure channel. In self-signed mode, first save collector_ca_pem next to where developers run this."
  value = join(" ", compact([
    "tokeniq sync configure",
    "--collector-url ${module.ingress.collector_endpoint}",
    "--tenant-id ${var.tenant_id}",
    module.ingress.client_ca_required ? "--collector-ca ./collector-ca.pem" : "",
  ]))
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

output "codecommit_cross_account_event_bus_arn" {
  description = "ARN of the custom event bus the CodeCommit repo account must forward its events onto (create an EventBridge rule there targeting this ARN). Empty unless the cross-account CodeCommit intake is enabled."
  value       = var.git_codecommit_intake_enabled && var.codecommit_account_id != "" ? module.intake_codecommit[0].cross_account_event_bus_arn : ""
}

output "enricher_execution_role_arn" {
  description = "Enricher ECS execution role ARN. When export is enabled, grant this role read on the vendor-hosted export tenant-key secret."
  value       = module.services.enricher_execution_role_arn
}
