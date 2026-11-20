# terraform-aws-tokeniq

Terraform module for the TokenIQ **customer data plane**: the in-account
collector, enrichers, data service, messaging fabric, and network ingress
that keep LLM turn content inside the customer's AWS environment. Only
content-free metadata ever leaves it — and only when export is explicitly
enabled.

> Status: under construction. The module surface (inputs/outputs) is not
> yet stable; do not pin to `main`.

## What it deploys

- **Collector** (ECS Fargate) — authenticated HTTPS ingest for `tokeniq sync`
  (Kiro/Claude Code sweeps), gateway turns, git webhooks, and the optional
  intakes below. Writes every payload to the WAL bucket and fans out over SNS.
- **Enricher** (ECS Fargate) — attribution, pattern engine, session indexing,
  optional git backfills and session analyzer.
- **Data service** (ECS on EC2, single node) — owns the SQLite store on a
  persistent, AZ-pinned EBS volume; serves REST sync reads and applies
  SQS batch upserts.
- **Messaging + storage** — SNS topics, per-enricher SQS queues with DLQs,
  private WAL S3 bucket, Cloud Map private DNS namespace, Secrets Manager
  secrets (tenant keys, TLS material, service auth tokens).
- **Ingress** — optional NLB in front of the collector with two TLS modes and
  an explicit internet-facing opt-in (see below).

## Layout

Root module composes internal submodules (the `terraform-aws-eks` pattern —
customers instantiate only the root):

| Path | Purpose |
|---|---|
| `modules/core` | Messaging (SNS/SQS), WAL bucket, secrets, service discovery |
| `modules/services` | Collector + enricher (Fargate), data service (EC2 + EBS) |
| `modules/ingress` | NLB, TLS modes (ACM / self-signed), DNS, internet-facing opt-in |
| `modules/intake-litellm` | Optional LiteLLM log intake (EventBridge → SQS) |
| `modules/intake-codecommit` | Optional CodeCommit live push intake |
| `modules/export` | Optional PrivateLink endpoint to the hosted plane |
| `modules/gateway` | Optional TokenIQ Gateway (ALB + ECS, signed-bundle config, telemetry push) |
| `examples/` | Complete, deployable example configurations |

## Quick start

```hcl
module "tokeniq" {
  source = "xosphere/tokeniq/aws"

  vpc_id             = "vpc-..."
  private_subnet_ids = ["subnet-...", "subnet-..."]

  tenant_id      = "acme"
  image_registry = "123456789012.dkr.ecr.us-west-2.amazonaws.com"

  # Internal NLB + ACM TLS (recommended): developers connect over your VPN
  # with zero TLS configuration.
  acm_certificate_arn = "arn:aws:acm:us-west-2:...:certificate/..."
  dns_name            = "tokeniq.example.com"
  route53_zone_id     = "Z..."
}
```

Requirements: Terraform >= 1.11, AWS provider >= 5.83.

## Choosing an ingress mode

Two independent choices — reachability and TLS:

| | `tls_mode = "acm"` (default) | `tls_mode = "self_signed"` |
|---|---|---|
| **Internal NLB** (default) | Recommended. Needs a VPN/DirectConnect route, an ACM cert, and a DNS name. Developers need zero TLS config. | Needs a VPN route, no domain. Developers trust `collector_ca_pem` via `--collector-ca`. |
| **`internet_facing = true`** | No VPN needed. Requires `public_subnet_ids` + tightly scoped `allowed_ingress_cidrs`. | No VPN, no domain. Same CIDR requirements, plus `--collector-ca`. |

- **`"acm"`** terminates client TLS at the NLB with your ACM certificate and
  re-encrypts to the task. Requires `acm_certificate_arn` + `dns_name`.
- **`"self_signed"`** passes TCP through the NLB; clients handshake directly
  with the collector's module-generated certificate. Distribute the
  `collector_ca_pem` output to developers.
- **Internet-facing is an explicit opt-in.** The collector authenticates every
  request, but keeping the NLB internal removes the exposed surface entirely —
  prefer a VPN. When you do go internet-facing, `allowed_ingress_cidrs` is
  required and must never be `0.0.0.0/0`.
- `create_load_balancer = false` skips the NLB: in-VPC clients call the
  collector via Cloud Map DNS (`collector.tokeniq.local`).

## Gateway (optional)

Set `gateway_enabled = true` to deploy the TokenIQ Gateway next to the
data plane: an ALB + Fargate service proxying LLM traffic (OpenAI-compatible
and native Anthropic surfaces, including the Claude Code gateway protocol)
with signed-bundle configuration — virtual keys, routing, budgets,
policies. Requirements and wiring:

- **Ingress must run `tls_mode = "acm"`.** The gateway pushes each turn's
  telemetry to the collector endpoint over authenticated HTTP and its
  client trusts system roots only; a `check` block flags self-signed
  configurations. The shared HMAC key is provisioned by `modules/core`
  and injected into both services automatically.
- **Trust anchor + first bundle.** Run `tokeniq gateway init` locally, set
  `gateway_bundle_public_key` to the printed public key, and point
  `gateway_bundle_seed_path` at the signed artifact — the module creates a
  versioned public-read bundle bucket (Tier 2), seeds it on first apply,
  and never overwrites later out-of-band publishes. For the hosted
  control plane (Tier 3), set `gateway_bundle_url` to the distributor,
  `https://tokeniq-bundles.xosphere.io`, plus
  `gateway_bundle_tenant_key_secret_arn`, and set
  `gateway_bundle_public_key` to your tenant's key from
  `tokeniq gateway config signing-key --quiet` (it exists once the tenant
  authors configuration in the console); migration between tiers is just
  those variables.
- **Provider API keys stay in your account.** Create Secrets Manager
  secrets and map them via `gateway_extra_secrets`
  (`{ TOKENIQ_ANTHROPIC_API_KEY = "arn:..." }`). They never ride in
  bundles or reach the hosted plane. Bedrock needs no key at all:
  `gateway_bedrock_served_models` grants the task role invoke access.
- Point developers' `ANTHROPIC_BASE_URL` (or OpenAI-compatible clients)
  at the `gateway_endpoint` output; the admin console token lives in the
  `gateway_admin_token_secret_arn` secret.

See `examples/with-gateway` for a complete configuration and the
`tokeniq` CLI's `docs/deploy-aws.md` for the worked walkthrough.

## Enrolling developers

1. Apply the module, then collect the enrollment materials:

   ```sh
   terraform output developer_onboarding_command
   aws secretsmanager get-secret-value --secret-id "$(terraform output -raw kiro_tenant_key_secret_arn)" --query SecretString --output text
   ```

   Share the tenant key over a secure channel — it is deliberately absent
   from the onboarding command and from every Terraform output.

   In self-signed mode also save the CA next to where developers run the
   command: `terraform output -raw collector_ca_pem > collector-ca.pem`

2. Each developer runs the onboarding command, e.g.:

   ```sh
   tokeniq sync configure --collector-url https://tokeniq.example.com --tenant-id acme
   ```

   pastes the tenant key at the prompt, and schedules `tokeniq sync`.

To rotate the tenant key, bump `kiro_tenant_key_version` and re-apply; every
enrolled machine must then re-run `tokeniq sync configure --force` with the
new key.

## Optional features

All off by default; each turns on with a flag plus its settings (see
`variables.tf` for the full contract):

- **LiteLLM intake** — `litellm_intake_enabled` + `litellm_events_bucket`.
  You own the bucket and must enable EventBridge notifications on it; the
  module only creates the rule, queue, and read grant.
- **CodeCommit live intake** — `git_codecommit_intake_enabled` +
  `codecommit_repos`. Cross-account: set `codecommit_account_id` and forward
  events onto the bus in `codecommit_cross_account_event_bus_arn`.
- **Git backfills** — `git_github_backfill_enabled` /
  `git_gitlab_backfill_enabled` / `git_codecommit_backfill_enabled`.
  GitHub/GitLab credentials are yours, supplied by Secrets Manager ARN — the
  module never owns a PAT or App key.
- **Session analyzer** — `session_analyzer_enabled` + an in-account
  OpenAI-compatible LLM endpoint and key secret.
- **Metadata export to the hosted plane** — `export_endpoint` +
  `export_tenant_key_secret_arn` (both vendor-supplied at onboarding);
  optionally `export_privatelink_service_name` for a private route. Only
  content-free metadata egresses; identity fields are plaintext or
  HMAC-pseudonymized per `export_identity_user_mode` / `export_identity_team_mode`.

## Key outputs

| Output | Purpose |
|---|---|
| `collector_endpoint` | Base URL developers point `tokeniq sync` at |
| `developer_onboarding_command` | Paste-ready `tokeniq sync configure` one-liner (key excluded) |
| `kiro_tenant_key_secret_arn` | Where the tenant key lives — read out-of-band |
| `collector_ca_pem` | CA to distribute in self-signed mode (sensitive) |
| `nlb_dns_name` | Raw NLB DNS name (stable across redeploys) |

## Operational notes

- **The data service is a single writer by design.** Its ASG must stay at
  1/1/1 and its EBS volume is AZ-pinned and `prevent_destroy`. Deploys
  overlap two tasks on the same host briefly — the default `t3.large`
  accommodates that; don't shrink it below two concurrent tasks.
- **Secrets never transit Terraform outputs.** The tenant key is written to
  Secrets Manager with a write-only argument and never lands in state. The
  self-signed TLS private key *does* live in state (Terraform `tls` provider
  semantics) — protect your state backend accordingly.
- Services may crashloop briefly on first apply until the ingress module
  writes the TLS secret versions; they recover within the same apply.

## Development

CI runs `terraform fmt -check -recursive` and `terraform validate` on the
root and every example. Run both locally before pushing.
