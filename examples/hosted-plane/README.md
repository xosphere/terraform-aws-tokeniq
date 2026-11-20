# Hosted plane example

A complete customer deployment against Xosphere's hosted TokenIQ plane:
collector, enricher, data service and gateway in your account; turn metadata
(never content) exported to Xosphere over PrivateLink; gateway config authored
in the TokenIQ console and delivered as signed bundles.

Besides the module, it creates what a first install needs around it: ACM
certificates for the collector and gateway (DNS-validated in a public Route 53
zone) and the Secrets Manager secrets for your tenant key and Anthropic key.

## Before you start

From Xosphere:

- your **tenant ID** (`tenant_id`): your Xosphere account ID, shown in the console;
- your **tenant key**, sent over a secure channel;
- confirmation that your AWS account is **allow-listed** on the ingest endpoint service;
- your **bundle-signing public key** (`gateway_bundle_public_key`), from the TokenIQ console or `tokeniq gateway config signing-key --quiet`.

In your account (**us-west-2**):

- a VPC with two or more private subnets with NAT egress, in AZ IDs `usw2-az1`, `usw2-az2` or `usw2-az3`;
- a public Route 53 zone for certificate validation (optionally a private zone for the records: `record_zone_id`);
- network reach (VPN or Direct Connect) from developer machines to the VPC;
- an Anthropic API key.

## Install

```sh
cp terraform.tfvars.example terraform.tfvars   # fill it in
terraform init
terraform apply -target=aws_secretsmanager_secret.tenant_key -target=aws_secretsmanager_secret.anthropic_api_key
read -s TENANT_KEY && aws secretsmanager put-secret-value --secret-id tokeniq/hosted-tenant-key --secret-string "$TENANT_KEY"; unset TENANT_KEY
read -s ANTHROPIC_KEY && aws secretsmanager put-secret-value --secret-id tokeniq/anthropic-api-key --secret-string "$ANTHROPIC_KEY"; unset ANTHROPIC_KEY
terraform apply
```

Services can restart for a few minutes on the first apply while their TLS
material is created.

## Point Claude Code at the gateway

Each developer, with the virtual key Xosphere's console issues them:

```sh
export ANTHROPIC_BASE_URL="$(terraform output -raw gateway_endpoint)"
export ANTHROPIC_AUTH_TOKEN="<virtual key>"
claude -p "say hi"
```

To require the gateway organization-wide, use Claude Code managed settings:
`{"allowedProviders":["customEndpoint"],"env":{"ANTHROPIC_BASE_URL":"https://<gateway_dns_name>"}}`
(the URL must match exactly).

## Identity

User emails and team names are exported as-is (`identity_mode = "plaintext"`,
the default). Customers with strict privacy requirements can set
`"pseudonymous"`: identities are HMAC'd with a key that never leaves this
account.
