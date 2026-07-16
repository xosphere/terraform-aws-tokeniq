variable "vpc_id" {
  description = "VPC the data plane deploys into. Cloud Map private DNS is VPC-wide, so every consumer must live in (or peer with) this VPC."
  type        = string
}

variable "name_prefix" {
  description = "Prefix for every named resource (topics, queues, buckets, secrets, DNS namespace records). Change it to run multiple instances of the module in one account."
  type        = string
  default     = "tokeniq"
}

variable "discovery_namespace" {
  description = "Cloud Map private DNS namespace for in-VPC service discovery (collector.<namespace>, data-service.<namespace>)."
  type        = string
  default     = "tokeniq.local"
}

variable "wal_bucket_name" {
  description = "Name for the WAL S3 bucket. Empty string derives \"<name_prefix>-wal-<account_id>\"."
  type        = string
  default     = ""
}

variable "private_subnet_ids" {
  description = "Private subnets the collector and enricher Fargate tasks run in."
  type        = list(string)
}

variable "data_service_subnet_id" {
  description = "Single private subnet for the data-service (single-node, AZ-pinned: its persistent EBS volume lives in this subnet's AZ). Empty string uses the first entry of private_subnet_ids."
  type        = string
  default     = ""
}

variable "cluster_arn" {
  description = "Existing ECS cluster ARN for the collector and enricher Fargate services. Empty string creates a cluster named after name_prefix. The data-service always runs on its own EC2 cluster either way."
  type        = string
  default     = ""
}

variable "tenant_id" {
  description = "Tenant identifier stamped on all telemetry (TOKENIQ_TENANT_ID)."
  type        = string
}

variable "image_registry" {
  description = "Container registry holding the TokenIQ images (e.g. an ECR registry URL). Image URIs are composed as <image_registry>/tokeniq-<service>:<image_tag>."
  type        = string
}

variable "image_tag" {
  description = "Tag for all three TokenIQ service images."
  type        = string
  default     = "latest"
}

# --- Sizing ---

variable "collector_cpu" {
  description = "Collector Fargate task CPU units."
  type        = number
  default     = 512
}

variable "collector_memory" {
  description = "Collector Fargate task memory (MiB)."
  type        = number
  default     = 1024
}

variable "enricher_cpu" {
  description = "Enricher Fargate task CPU units."
  type        = number
  default     = 512
}

variable "enricher_memory" {
  description = "Enricher Fargate task memory (MiB). GOMEMLIMIT is derived at ~90% of this."
  type        = number
  default     = 2048
}

variable "data_service_instance_type" {
  description = "data-service EC2 instance type. Must fit TWO concurrent data_service_container_memory_mib tasks during a same-host overlap deploy, plus 2 task ENIs. t3.large holds two 3072-MiB tasks; t3.medium cannot."
  type        = string
  default     = "t3.large"
}

variable "data_service_data_volume_gib" {
  description = "data-service persistent EBS data volume size (GiB) for the SQLite file."
  type        = number
  default     = 50
}

variable "data_service_container_memory_mib" {
  description = "Hard memory limit for the data-service container. Leave headroom for the ECS agent + OS on the chosen instance type."
  type        = number
  default     = 3072
}

variable "log_retention_days" {
  description = "CloudWatch log retention for all service log groups."
  type        = number
  default     = 30
}

variable "create_kiro_tenant_key" {
  description = "Generate the Kiro sweep tenant key inside the module (recommended). Set false to supply your own via kiro_tenant_key. Either way the plaintext never lands in Terraform state — it is written to Secrets Manager with a write-only argument."
  type        = bool
  default     = true
}

variable "kiro_tenant_key" {
  description = "Externally supplied Kiro sweep HMAC tenant key. Only read when create_kiro_tenant_key is false. Ephemeral: supply it at apply time; it is never persisted to state or plan."
  type        = string
  default     = null
  ephemeral   = true
}

variable "kiro_tenant_key_version" {
  description = "Bump to rotate the Kiro tenant key (rewrites the secret version). After rotating, every enrolled developer machine must re-run `tokeniq sync configure --force` with the new key."
  type        = number
  default     = 1
}

# --- Ingress ---

variable "create_load_balancer" {
  description = "Create an NLB in front of the collector. false = in-VPC service-discovery access only (clients must resolve Cloud Map private DNS)."
  type        = bool
  default     = true
}

variable "internet_facing" {
  description = "Make the collector NLB internet-facing. STRONGLY consider keeping this false and reaching the collector over a VPN/DirectConnect instead: the collector authenticates every request, but an internal NLB removes the exposed surface entirely. true requires allowed_ingress_cidrs and public_subnet_ids."
  type        = bool
  default     = false

  validation {
    condition     = !var.internet_facing || length(var.public_subnet_ids) > 0
    error_message = "internet_facing requires public_subnet_ids for the NLB."
  }
}

variable "public_subnet_ids" {
  description = "Public subnets for the NLB when internet_facing. Unused otherwise."
  type        = list(string)
  default     = []
}

variable "allowed_ingress_cidrs" {
  description = "CIDRs allowed to reach the collector NLB on 443. REQUIRED when internet_facing — scope to your developers' egress CIDRs, never 0.0.0.0/0. For an internal NLB, empty defaults to the VPC CIDR."
  type        = list(string)
  default     = []
}

variable "tls_mode" {
  description = "\"acm\" (default): NLB TLS listener terminates with an ACM certificate — clients trust system roots, zero client TLS config (requires acm_certificate_arn + dns_name). \"self_signed\": no domain needed — NLB passes TCP through to the collector's generated self-signed cert; distribute the collector_ca_pem output to developers."
  type        = string
  default     = "acm"
}

variable "acm_certificate_arn" {
  description = "ACM certificate for the NLB TLS listener (tls_mode = \"acm\"). Must cover dns_name."
  type        = string
  default     = ""
}

variable "route53_zone_id" {
  description = "Route 53 hosted zone to create the collector alias record in. Empty skips DNS."
  type        = string
  default     = ""
}

variable "dns_name" {
  description = "Fully qualified DNS name clients call the collector by (e.g. tokeniq.example.com)."
  type        = string
  default     = ""
}

# --- Pricing-at-ingest ---

variable "price_book_url" {
  description = "Hosted price-book object URL the collector fills cost_usd for gateway turns from. Empty disables pricing-at-ingest."
  type        = string
  default     = ""
}

# --- LiteLLM landing-zone intake (opt-in) ---

variable "litellm_intake_enabled" {
  description = "Create the LiteLLM collector intake (intake SQS queue, EventBridge rule, collector env + bucket read grant). Requires litellm_events_bucket. The customer's LiteLLM bucket itself is never created or modified — enable EventBridge notifications on it yourself."
  type        = bool
  default     = false

  validation {
    condition     = !var.litellm_intake_enabled || var.litellm_events_bucket != ""
    error_message = "litellm_intake_enabled requires litellm_events_bucket."
  }
}

variable "litellm_events_bucket" {
  description = "Name of your existing LiteLLM raw-events S3 bucket the collector reads announced objects from."
  type        = string
  default     = ""
}

variable "litellm_events_prefix" {
  description = "Optional S3 key prefix (LiteLLM s3_path) to scope intake to LiteLLM objects when the bucket is shared. Empty ingests every Object Created event on the bucket."
  type        = string
  default     = ""
}

# --- CodeCommit live intake (opt-in) ---

variable "git_codecommit_intake_enabled" {
  description = "Enable the live CodeCommit push intake: an EventBridge rule (scoped to codecommit_repos) → SQS queue the collector consumes, recording a git push per branch push straight from the event. Requires a non-empty codecommit_repos."
  type        = bool
  default     = false

  validation {
    condition     = !var.git_codecommit_intake_enabled || length(var.codecommit_repos) > 0
    error_message = "git_codecommit_intake_enabled requires at least one repository in codecommit_repos."
  }
}

# --- Git REST backfill (opt-in per provider) ---
# Credentials are customer-supplied by secret ARN: the module never owns a PAT
# or App key. Keep a provider OFF until its secret carries a value — ECS cannot
# resolve a secret with no AWSCURRENT version, so injecting an empty one
# crashloops the task.

variable "git_github_backfill_enabled" {
  description = "Enable the GitHub App backfill. Requires git_github_app_id and git_github_app_private_key_secret_arn."
  type        = bool
  default     = false

  validation {
    condition     = !var.git_github_backfill_enabled || (var.git_github_app_id != "" && var.git_github_app_private_key_secret_arn != "")
    error_message = "git_github_backfill_enabled requires git_github_app_id and git_github_app_private_key_secret_arn."
  }
}

variable "git_github_app_id" {
  description = "GitHub App ID for the backfill (non-sensitive identifier)."
  type        = string
  default     = ""
}

variable "git_github_app_private_key_secret_arn" {
  description = "Secrets Manager ARN of the GitHub App private key PEM, created and populated by the customer."
  type        = string
  default     = ""
}

variable "git_poll_interval" {
  description = "Base sweep cadence for the collector's outbound GitHub Events poller. The collector enforces a 60s floor and honors per-repo X-Poll-Interval."
  type        = string
  default     = "60s"
}

variable "git_gitlab_backfill_enabled" {
  description = "Enable the GitLab backfill. Requires git_gitlab_backfill_token_secret_arn."
  type        = bool
  default     = false

  validation {
    condition     = !var.git_gitlab_backfill_enabled || var.git_gitlab_backfill_token_secret_arn != ""
    error_message = "git_gitlab_backfill_enabled requires git_gitlab_backfill_token_secret_arn."
  }
}

variable "git_gitlab_backfill_token_secret_arn" {
  description = "Secrets Manager ARN of the GitLab backfill token, created and populated by the customer."
  type        = string
  default     = ""
}

variable "git_codecommit_backfill_enabled" {
  description = "Enable the AWS CodeCommit backfill. Auth is the in-account enricher task role (no secret)."
  type        = bool
  default     = false
}

variable "codecommit_repos" {
  description = "CodeCommit repository names the enricher backfill may read. Scopes the task-role grant; empty grants nothing."
  type        = list(string)
  default     = []
}

variable "codecommit_account_id" {
  description = "AWS account that owns the CodeCommit repos, when different from this account. Empty = same-account topology."
  type        = string
  default     = ""
}

variable "codecommit_read_role_arn" {
  description = "Role ARN (in codecommit_account_id) the enricher assumes to read CodeCommit cross-account. Empty = in-account task-role read."
  type        = string
  default     = ""
}

# --- Session analyzer ---

variable "session_analyzer_enabled" {
  description = "Enable the session analyzer. Requires session_analyzer_llm_endpoint and session_analyzer_llm_api_key_secret_arn."
  type        = bool
  default     = false

  validation {
    condition     = !var.session_analyzer_enabled || (var.session_analyzer_llm_endpoint != "" && var.session_analyzer_llm_api_key_secret_arn != "")
    error_message = "session_analyzer_enabled requires session_analyzer_llm_endpoint and session_analyzer_llm_api_key_secret_arn."
  }
}

variable "session_analyzer_llm_endpoint" {
  description = "OpenAI-compatible in-account LLM endpoint the session analyzer calls. The binary rejects direct SaaS provider hosts — point this at an in-account proxy."
  type        = string
  default     = ""
}

variable "session_analyzer_llm_model" {
  description = "Model name the session analyzer requests, as exposed by the in-account proxy's model list."
  type        = string
  default     = "claude-haiku-4-5"
}

variable "session_analyzer_llm_api_key_secret_arn" {
  description = "Secrets Manager ARN of the analyzer's LLM API key, created and populated by the customer."
  type        = string
  default     = ""
}

# --- Metadata export to the hosted plane ---
# Export turns on only when BOTH the ingest endpoint and the vendor-delegated
# tenant-key secret ARN are set. Only content-free metadata ever egresses —
# LLM turn content NEVER leaves this account.

variable "export_endpoint" {
  description = "HTTPS ingest endpoint of the hosted plane the collector and enricher export content-free metadata to. Empty disables export."
  type        = string
  default     = ""
}

variable "export_tenant_key_secret_arn" {
  description = "ARN of this tenant's vendor-hosted HMAC key secret the exporters sign with. Empty disables export."
  type        = string
  default     = ""
}

variable "export_privatelink_service_name" {
  description = "Vendor-published PrivateLink endpoint-service name (vpce-svc-...) for the hosted-plane ingest, shared during onboarding. Set to create the interface endpoint that makes export_endpoint resolve privately in-VPC. Empty skips PrivateLink (export then needs another route to the endpoint, e.g. NAT egress)."
  type        = string
  default     = ""
}

variable "export_privatelink_ingest_port" {
  description = "Port the hosted-plane ingest listens on behind the PrivateLink endpoint. Must match the port in export_endpoint."
  type        = number
  default     = 8080
}

variable "export_identity_user_mode" {
  description = "Per-tenant user identity export mode: \"plaintext\" exports the friendly user email in user_id, \"pseudonymous\" HMAC-pseudonymizes the raw ID with the non-egressing key."
  type        = string
  default     = "plaintext"

  validation {
    condition     = contains(["plaintext", "pseudonymous"], var.export_identity_user_mode)
    error_message = "export_identity_user_mode must be \"plaintext\" or \"pseudonymous\"."
  }
}

variable "export_identity_team_mode" {
  description = "Per-tenant team identity export mode: \"plaintext\" exports the friendly team name in team_id, \"pseudonymous\" HMAC-pseudonymizes the raw ID with the non-egressing key."
  type        = string
  default     = "plaintext"

  validation {
    condition     = contains(["plaintext", "pseudonymous"], var.export_identity_team_mode)
    error_message = "export_identity_team_mode must be \"plaintext\" or \"pseudonymous\"."
  }
}
