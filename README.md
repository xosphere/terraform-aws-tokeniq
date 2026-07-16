# terraform-aws-tokeniq

Terraform module for the TokenIQ **customer data plane**: the in-account
collector, enrichers, data service, messaging fabric, and network ingress
that keep LLM turn content inside the customer's AWS environment. Only
content-free metadata ever leaves it.

> Status: under construction. The module surface (inputs/outputs) is not
> yet stable; do not pin to `main`.

## Layout

Root module composes internal submodules (the `terraform-aws-eks` pattern —
customers instantiate only the root):

| Path | Purpose |
|---|---|
| `modules/core` | Messaging (SNS/SQS), WAL bucket, secrets, service discovery, shared IAM |
| `modules/services` | Collector + enricher (Fargate), data service (EC2 ASG + EBS) |
| `modules/ingress` | NLB, TLS modes (ACM / self-signed), DNS, internet-facing opt-in |
| `modules/intake-litellm` | Optional LiteLLM log intake |
| `modules/intake-codecommit` | Optional CodeCommit live intake |
| `modules/export` | Optional PrivateLink export to the hosted plane |
| `examples/` | Complete, deployable example configurations |

## Development

CI runs `terraform fmt -check -recursive` and `terraform validate` on the
root and every example. Run both locally before pushing.
