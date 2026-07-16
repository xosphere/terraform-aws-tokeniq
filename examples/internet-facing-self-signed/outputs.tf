output "collector_endpoint" {
  description = "Base URL developers point tokeniq sync at (the NLB DNS name)."
  value       = module.tokeniq.collector_endpoint
}

output "collector_ca_pem" {
  description = "PEM certificate developers must trust. Save with: terraform output -raw collector_ca_pem > collector-ca.pem"
  value       = module.tokeniq.collector_ca_pem
  sensitive   = true
}

output "developer_onboarding_command" {
  description = "Paste-ready enrollment command to hand developers, alongside collector-ca.pem (they paste the tenant key at the prompt)."
  value       = module.tokeniq.developer_onboarding_command
}

output "kiro_tenant_key_secret_arn" {
  description = "Secrets Manager ARN of the tenant key. Read it out-of-band and share it with developers over a secure channel."
  value       = module.tokeniq.kiro_tenant_key_secret_arn
}
