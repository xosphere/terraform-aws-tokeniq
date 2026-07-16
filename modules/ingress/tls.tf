# --- Collector TLS material ---
# The collector binary is fail-closed TLS: it refuses to boot without a
# cert/key, in BOTH modes. In "acm" mode the NLB terminates client TLS with
# the ACM cert and opens a fresh TLS connection to the task — NLBs do not
# validate target certificates, so the task's self-signed cert is fine behind
# it. In "self_signed" mode this cert IS what clients verify, so its SANs must
# cover every name they might dial: the custom dns_name, the NLB's DNS name,
# and the in-VPC Cloud Map name.
#
# Trade-off: generating the keypair with the tls provider puts the private key
# in Terraform state (same call as the core module's data-service cert). The
# alternative — customers minting PEMs out-of-band per apply — is the burden
# this module exists to remove. Protect the state backend accordingly.

resource "tls_private_key" "collector" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "collector" {
  private_key_pem = tls_private_key.collector.private_key_pem

  subject {
    common_name = var.dns_name != "" ? var.dns_name : "collector.${var.discovery_namespace}"
  }

  dns_names = compact([
    "collector.${var.discovery_namespace}",
    var.dns_name,
    var.create_load_balancer ? aws_lb.collector[0].dns_name : "",
  ])

  validity_period_hours = 87600 # 10 years — rotation is a taint + redeploy.
  allowed_uses          = ["key_encipherment", "digital_signature", "server_auth"]
}

# Write the versions into the containers modules/core owns. Core owning the
# containers keeps the secret ARNs stable for the services module's IAM and
# task definitions; this module owns the values because the SANs depend on
# the NLB it creates.
resource "aws_secretsmanager_secret_version" "collector_tls_cert" {
  secret_id     = var.collector_tls_cert_secret_id
  secret_string = tls_self_signed_cert.collector.cert_pem
}

resource "aws_secretsmanager_secret_version" "collector_tls_key" {
  secret_id     = var.collector_tls_key_secret_id
  secret_string = tls_private_key.collector.private_key_pem
}
