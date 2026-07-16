output "collector_endpoint" {
  description = "Base URL developers point tokeniq sync at."
  value       = module.tokeniq.collector_endpoint
}

output "developer_onboarding_command" {
  description = "Paste-ready enrollment command to hand developers (they paste the tenant key at the prompt)."
  value       = module.tokeniq.developer_onboarding_command
}

output "kiro_tenant_key_secret_arn" {
  description = "Secrets Manager ARN of the tenant key. Read it out-of-band and share it with developers over a secure channel."
  value       = module.tokeniq.kiro_tenant_key_secret_arn
}
