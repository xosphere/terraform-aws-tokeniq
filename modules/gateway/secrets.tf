# Bearer for the gateway's admin API (TOKENIQ_ADMIN_TOKEN). Operators read
# it from Secrets Manager and paste it into the console at
# https://<gateway>/admin/. Terraform owns the value via a write-only
# argument: the ephemeral random_password feeds the secret but is never
# persisted, so the plaintext stays out of state. Bump
# admin_token_rotation_version to rotate, then redeploy the gateway.
resource "aws_secretsmanager_secret" "admin_token" {
  name = "${var.name_prefix}/gateway-admin-token"
}

ephemeral "random_password" "admin_token" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret_version" "admin_token" {
  secret_id                = aws_secretsmanager_secret.admin_token.id
  secret_string_wo         = ephemeral.random_password.admin_token.result
  secret_string_wo_version = var.admin_token_rotation_version
}
