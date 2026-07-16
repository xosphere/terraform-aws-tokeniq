# --- Secrets Manager ---
#
# Every auto-generated value uses the write-only pattern: an ephemeral
# random_password feeds secret_string_wo, so the plaintext lands in Secrets
# Manager but never in Terraform state or plan. The value is (re)written only
# when secret_string_wo_version changes — bump it to deliberately rotate.

# --- Kiro sweep tenant key ---
# Shared HMAC key for the `tokeniq sync` Kiro local-store sweep: the collector
# verifies inbound POST /v1/ingest/kiro batches with it, and each developer's
# sweep signs with the same value (read out of Secrets Manager at onboarding).
# Create-or-accept: generated in-module by default, or supplied via
# var.kiro_tenant_key (ephemeral — still never lands in state). Bump
# var.kiro_tenant_key_version to rotate, then re-distribute to swept machines
# (`tokeniq sync configure --force`).
resource "aws_secretsmanager_secret" "kiro_tenant_key" {
  name = "${var.name_prefix}/kiro-tenant-key"
}

ephemeral "random_password" "kiro_tenant_key" {
  count = var.create_kiro_tenant_key ? 1 : 0

  length  = 64
  special = false
}

resource "aws_secretsmanager_secret_version" "kiro_tenant_key" {
  secret_id                = aws_secretsmanager_secret.kiro_tenant_key.id
  secret_string_wo         = var.create_kiro_tenant_key ? ephemeral.random_password.kiro_tenant_key[0].result : var.kiro_tenant_key
  secret_string_wo_version = var.kiro_tenant_key_version
}

# --- Gateway tenant key ---
# Shared HMAC key for inbound gateway metadata batches. The collector reads it
# fail-closed at boot, so the secret must exist even when no gateway is
# deployed. Deliberately distinct from the Kiro key so either credential can
# rotate without touching the other's clients.
resource "aws_secretsmanager_secret" "gateway_tenant_key" {
  name = "${var.name_prefix}/gateway-tenant-key"
}

ephemeral "random_password" "gateway_tenant_key" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret_version" "gateway_tenant_key" {
  secret_id                = aws_secretsmanager_secret.gateway_tenant_key.id
  secret_string_wo         = ephemeral.random_password.gateway_tenant_key.result
  secret_string_wo_version = 1
}

# --- Git webhook secrets ---
# The collector verifies inbound git pushes on POST /v1/ingest/git: GitHub
# HMAC-signs the body with the webhook secret (X-Hub-Signature-256), GitLab
# presents a shared token (X-Gitlab-Token). After apply, read the generated
# value out of Secrets Manager and configure the webhook with the matching
# secret so both sides agree.
resource "aws_secretsmanager_secret" "git_github_webhook_secret" {
  name = "${var.name_prefix}/git-github-webhook-secret"
}

ephemeral "random_password" "git_github_webhook_secret" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret_version" "git_github_webhook_secret" {
  secret_id                = aws_secretsmanager_secret.git_github_webhook_secret.id
  secret_string_wo         = ephemeral.random_password.git_github_webhook_secret.result
  secret_string_wo_version = 1
}

resource "aws_secretsmanager_secret" "git_gitlab_webhook_token" {
  name = "${var.name_prefix}/git-gitlab-webhook-token"
}

ephemeral "random_password" "git_gitlab_webhook_token" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret_version" "git_gitlab_webhook_token" {
  secret_id                = aws_secretsmanager_secret.git_gitlab_webhook_token.id
  secret_string_wo         = ephemeral.random_password.git_gitlab_webhook_token.result
  secret_string_wo_version = 1
}

# --- data-service auth token + TLS material ---
# Defense-in-depth for the data-service REST surface (the SG already scopes it
# VPC-internal): a shared bearer token gates every request, and the service
# serves HTTPS so the enricher verifies the cert (no InsecureSkipVerify). Both
# the data-service (server) and the enricher (client) read THESE secrets.
resource "aws_secretsmanager_secret" "data_service_auth_token" {
  name = "${var.name_prefix}/data-service-auth-token"
}

ephemeral "random_password" "data_service_auth_token" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret_version" "data_service_auth_token" {
  secret_id                = aws_secretsmanager_secret.data_service_auth_token.id
  secret_string_wo         = ephemeral.random_password.data_service_auth_token.result
  secret_string_wo_version = 1
}

# Self-signed server cert + key for data-service.<namespace>. There is no load
# balancer on this task-to-task path (awsvpc via Cloud Map), so ACM does not
# fit — its certs only attach to ALB/NLB/CloudFront and the SAN is a private
# Cloud Map name. The cert is self-signed and serves as its own trust anchor
# (the enricher trusts it directly — no separate CA artifact).
#
# Trade-off: generating the keypair with the tls provider puts the private key
# in Terraform state. This is a VPC-internal, defense-in-depth cert (the SG is
# the primary control), and the alternative — every customer minting PEMs
# out-of-band and threading ephemeral variables through applies — is the kind
# of operational burden this module exists to remove. Protect the state
# backend accordingly.
resource "tls_private_key" "data_service" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "data_service" {
  private_key_pem = tls_private_key.data_service.private_key_pem

  subject {
    common_name = "data-service.${var.discovery_namespace}"
  }

  dns_names = ["data-service.${var.discovery_namespace}"]

  validity_period_hours = 87600 # 10 years — rotation is a taint + redeploy.
  allowed_uses          = ["key_encipherment", "digital_signature", "server_auth"]
}

resource "aws_secretsmanager_secret" "data_service_tls_cert" {
  name = "${var.name_prefix}/data-service-tls-cert"
}

resource "aws_secretsmanager_secret_version" "data_service_tls_cert" {
  secret_id     = aws_secretsmanager_secret.data_service_tls_cert.id
  secret_string = tls_self_signed_cert.data_service.cert_pem
}

resource "aws_secretsmanager_secret" "data_service_tls_key" {
  name = "${var.name_prefix}/data-service-tls-key"
}

resource "aws_secretsmanager_secret_version" "data_service_tls_key" {
  secret_id     = aws_secretsmanager_secret.data_service_tls_key.id
  secret_string = tls_private_key.data_service.private_key_pem
}

# --- collector auth token + TLS containers ---
# The collector's bearer-gated routes and its TLS listener are fail-closed in
# the binary, so the token and cert/key MUST exist or the task refuses to boot.
resource "aws_secretsmanager_secret" "collector_auth_token" {
  name = "${var.name_prefix}/collector-auth-token"
}

ephemeral "random_password" "collector_auth_token" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret_version" "collector_auth_token" {
  secret_id                = aws_secretsmanager_secret.collector_auth_token.id
  secret_string_wo         = ephemeral.random_password.collector_auth_token.result
  secret_string_wo_version = 1
}

# Collector TLS cert/key: CONTAINERS only. The cert's SANs must include the
# NLB DNS name, which does not exist until the ingress module builds it — so
# ingress generates the cert (or records the ACM handoff) and writes the
# secret VERSIONS into these containers. Core owning the containers keeps the
# secret ARNs stable for the services module's IAM and task definitions.
resource "aws_secretsmanager_secret" "collector_tls_cert" {
  name = "${var.name_prefix}/collector-tls-cert"
}

resource "aws_secretsmanager_secret" "collector_tls_key" {
  name = "${var.name_prefix}/collector-tls-key"
}
