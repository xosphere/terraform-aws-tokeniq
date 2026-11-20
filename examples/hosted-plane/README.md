# Hosted plane example

A complete customer deployment against Xosphere's hosted TokenIQ plane:
collector, enricher, data service and gateway in your account; turn metadata
(never content) exported to Xosphere over PrivateLink; gateway config authored
in the TokenIQ console and delivered as signed bundles.

Besides the module, it creates what a first install needs around it: ACM
certificates for the collector and gateway (DNS-validated in a public Route 53
zone) and the Secrets Manager secret for your Anthropic key.

Your **tenant key never leaves Xosphere**. Connecting your AWS account in the
TokenIQ console grants that account read access to your tenant key secret in
Xosphere's account; this deployment reads it cross-account by ARN
(`hosted_tenant_key_secret_arn`), and the module grants its roles the
`kms:Decrypt` (via Secrets Manager) that needs.

## Before you start

In the TokenIQ console, **Configure TokenIQ → Connect your AWS account** and
enter the ID of the AWS account you're deploying into. That grants the account
read access to your tenant key and allow-lists it on the ingest endpoint
service. Then, from the console:

- your **tenant ID** (`tenant_id`): your Xosphere account ID;
- your **tenant key ARN** (`hosted_tenant_key_secret_arn`), shown after you connect your AWS account; copy it exactly, including the 6-character suffix;
- your **bundle-signing public key** (`gateway_bundle_public_key`), also from `tokeniq gateway config signing-key --quiet`.

In your account (**us-west-2**):

- a VPC with two or more private subnets with NAT egress, in AZ IDs `usw2-az1`, `usw2-az2` or `usw2-az3`;
- a public Route 53 zone for certificate validation (optionally a private zone for the records: `record_zone_id`);
- network reach (VPN or Direct Connect) from developer machines to the VPC;
- an Anthropic API key.

## Install

```sh
cp terraform.tfvars.example terraform.tfvars   # fill it in
terraform init
terraform apply -target=aws_secretsmanager_secret.anthropic_api_key
read -s ANTHROPIC_KEY && aws secretsmanager put-secret-value --secret-id tokeniq/anthropic-api-key --secret-string "$ANTHROPIC_KEY"; unset ANTHROPIC_KEY
terraform apply
```

Services can restart for a few minutes on the first apply while their TLS
material is created.

Fallback, only if Xosphere asks you to: leave `hosted_tenant_key_secret_arn`
empty and the example creates a local `tokeniq/hosted-tenant-key` secret
instead. Create it with `-target=aws_secretsmanager_secret.tenant_key` in the
first apply and put the tenant key Xosphere sends you into it with
`aws secretsmanager put-secret-value`, the same way as the Anthropic key.

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

## Gateway Redis

The example deploys the gateway with bundled Redis
(`gateway_redis_mode = "bundled"`, the recommended setting): a primary and
a replica `cache.t4g.small` ElastiCache Valkey node in your private subnets,
reachable only from the gateway tasks, about $37/month on-demand. It gives
the gateway distributed rate limits, budgets, a shared response cache, and
SSO `/login` across more than one gateway task. The first apply takes
10–15 minutes longer while ElastiCache creates the nodes. Set
`gateway_redis_mode = "none"` to run without Redis (per-task rate limits,
budgets off, no response cache). See "Gateway Redis" in the module README
for the security model.

## Identity

User emails and team names are exported as-is (`identity_mode = "plaintext"`,
the default). Customers with strict privacy requirements can set
`"pseudonymous"`: identities are HMAC'd with a key that never leaves this
account.
