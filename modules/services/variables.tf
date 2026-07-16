# --- Placement ---

variable "name_prefix" {
  description = "Prefix for all named resources."
  type        = string
}

variable "vpc_id" {
  description = "VPC the services run in. Its CIDR scopes the VPC-internal security-group ingress rules."
  type        = string
}

variable "cluster_arn" {
  description = "ECS cluster ARN the stateless Fargate services (collector, enricher) run on. The data-service creates its own EC2 cluster (it owns a host-mounted EBS volume and must run EC2 launch type)."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for the collector and enricher Fargate tasks."
  type        = list(string)
}

variable "data_service_subnet_id" {
  description = "Single private subnet for the data-service. The service is single-node and AZ-pinned: its persistent EBS volume lives in this subnet's AZ."
  type        = string
}

variable "tenant_id" {
  description = "TOKENIQ_TENANT_ID stamped on all telemetry."
  type        = string
}

# --- Images ---

variable "collector_image" {
  description = "Full collector container image URI (registry/repo:tag)."
  type        = string
}

variable "enricher_image" {
  description = "Full enricher container image URI (registry/repo:tag)."
  type        = string
}

variable "data_service_image" {
  description = "Full data-service container image URI (registry/repo:tag)."
  type        = string
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
  description = "data-service EC2 instance type. Must fit TWO concurrent data_service_container_memory_mib tasks during a same-host overlap deploy, plus 2 task ENIs for the awsvpc surge. t3.large (~7.8 GiB to ECS, 3 ENIs) holds two 3072-MiB tasks; t3.medium (~3924 MiB, 3 ENIs) cannot."
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
  description = "CloudWatch log retention for all three services' log groups."
  type        = number
  default     = 30
}

# --- Core wiring (outputs of modules/core) ---

variable "wal_bucket" {
  description = "Name of the WAL S3 bucket."
  type        = string
}

variable "wal_bucket_arn" {
  description = "ARN of the WAL S3 bucket."
  type        = string
}

variable "enrich_topic_arn" {
  description = "SNS topic the collector publishes one enrich event per turn to."
  type        = string
}

variable "work_enrich_topic_arn" {
  description = "SNS topic the collector git-webhook ingest and enricher backfill publish WorkEvents to."
  type        = string
}

variable "enricher_queue_urls" {
  description = "Per-enricher SQS queue URLs, keyed by enricher name."
  type        = map(string)
}

variable "enricher_queue_arns" {
  description = "Per-enricher SQS queue ARNs, keyed by enricher name."
  type        = map(string)
}

variable "work_queue_url" {
  description = "SQS queue the enricher's WorkSQSRunner long-polls for WorkEvents."
  type        = string
}

variable "work_queue_arn" {
  description = "ARN of the work queue."
  type        = string
}

variable "store_apply_queue_url" {
  description = "SQS queue the enrichers and collector publish upsert batches to; drained by the data-service."
  type        = string
}

variable "store_apply_queue_arn" {
  description = "ARN of the store-apply queue."
  type        = string
}

variable "collector_service_discovery_arn" {
  description = "Cloud Map service ARN the collector ECS service registers into."
  type        = string
}

variable "data_service_service_discovery_arn" {
  description = "Cloud Map service ARN the data-service ECS service registers into."
  type        = string
}

variable "data_service_url" {
  description = "In-VPC data-service base URL (via service discovery) the collector and enricher call."
  type        = string
}

variable "gateway_tenant_key_secret_arn" {
  description = "Secrets Manager ARN of the gateway tenant key."
  type        = string
}

variable "kiro_tenant_key_secret_arn" {
  description = "Secrets Manager ARN of the Kiro sweep tenant key."
  type        = string
}

variable "git_github_webhook_secret_arn" {
  description = "Secrets Manager ARN of the GitHub webhook secret."
  type        = string
}

variable "git_gitlab_webhook_token_secret_arn" {
  description = "Secrets Manager ARN of the GitLab webhook token."
  type        = string
}

variable "collector_auth_token_secret_arn" {
  description = "Secrets Manager ARN of the collector bearer token."
  type        = string
}

variable "collector_tls_cert_secret_arn" {
  description = "Secrets Manager ARN of the collector TLS certificate (version written by the ingress module)."
  type        = string
}

variable "collector_tls_key_secret_arn" {
  description = "Secrets Manager ARN of the collector TLS private key (version written by the ingress module)."
  type        = string
}

variable "data_service_auth_token_secret_arn" {
  description = "Secrets Manager ARN of the data-service bearer token."
  type        = string
}

variable "data_service_tls_cert_secret_arn" {
  description = "Secrets Manager ARN of the data-service TLS certificate (doubles as the client CA bundle)."
  type        = string
}

variable "data_service_tls_key_secret_arn" {
  description = "Secrets Manager ARN of the data-service TLS private key."
  type        = string
}

# --- Ingress wiring (set by the root when the ingress module is enabled) ---

variable "collector_target_group_arn" {
  description = "NLB target group the collector ECS service registers into. Empty = no load balancer (in-VPC service-discovery access only)."
  type        = string
  default     = ""
}

# --- Pricing-at-ingest ---

variable "price_book_url" {
  description = "Hosted price-book object URL the collector fills cost_usd for gateway turns from. Empty disables pricing-at-ingest."
  type        = string
  default     = ""
}

# --- Optional intakes (wired by the root when the intake submodules are enabled) ---

variable "litellm_intake_queue_url" {
  description = "LiteLLM intake SQS queue URL (from modules/intake-litellm). Empty disables the LiteLLM intake on the collector."
  type        = string
  default     = ""
}

variable "litellm_intake_queue_arn" {
  description = "LiteLLM intake SQS queue ARN. Required when litellm_intake_queue_url is set."
  type        = string
  default     = ""
}

variable "litellm_events_bucket" {
  description = "Name of the customer's existing LiteLLM raw-events S3 bucket the collector reads announced objects from. Required when litellm_intake_queue_url is set."
  type        = string
  default     = ""
}

variable "codecommit_intake_queue_url" {
  description = "CodeCommit intake SQS queue URL (from modules/intake-codecommit). Empty disables the live CodeCommit intake on the collector."
  type        = string
  default     = ""
}

variable "codecommit_intake_queue_arn" {
  description = "CodeCommit intake SQS queue ARN. Required when codecommit_intake_queue_url is set."
  type        = string
  default     = ""
}

# --- Git REST backfill (opt-in per provider) ---
# Each provider's credential is customer-supplied by secret ARN: the module
# never owns a PAT or App key. Keep a provider OFF until its secret carries a
# value — ECS cannot resolve a secret with no AWSCURRENT version, so injecting
# an empty one crashloops the task.

variable "git_github_backfill_enabled" {
  description = "Enable the GitHub App backfill: inject the App ID + private key into the collector poller and enricher backfill loop. Requires git_github_app_id and git_github_app_private_key_secret_arn."
  type        = bool
  default     = false

  validation {
    condition     = !var.git_github_backfill_enabled || (var.git_github_app_id != "" && var.git_github_app_private_key_secret_arn != "")
    error_message = "git_github_backfill_enabled requires git_github_app_id and git_github_app_private_key_secret_arn."
  }
}

variable "git_github_app_id" {
  description = "GitHub App ID for the backfill (non-sensitive identifier, plain env value)."
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
  description = "Enable the AWS CodeCommit backfill: grant the enricher task role read on codecommit_repos and turn on the backfill loop for provider=codecommit. Auth is the in-account task role (no secret)."
  type        = bool
  default     = false
}

variable "codecommit_repos" {
  description = "CodeCommit repository names the enricher backfill may read. Scopes the task-role grant to these repos' ARNs; empty grants nothing."
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
  description = "Enable the session analyzer: inject the LLM endpoint/model/key into the enricher (the binary enables the analyzer on endpoint presence). Requires session_analyzer_llm_endpoint and session_analyzer_llm_api_key_secret_arn."
  type        = bool
  default     = false

  validation {
    condition     = !var.session_analyzer_enabled || (var.session_analyzer_llm_endpoint != "" && var.session_analyzer_llm_api_key_secret_arn != "")
    error_message = "session_analyzer_enabled requires session_analyzer_llm_endpoint and session_analyzer_llm_api_key_secret_arn."
  }
}

variable "session_analyzer_llm_endpoint" {
  description = "OpenAI-compatible in-account LLM endpoint the session analyzer calls. The binary rejects direct SaaS provider hosts (api.anthropic.com etc.) — point this at an in-account proxy."
  type        = string
  default     = ""
}

variable "session_analyzer_llm_model" {
  description = "Model name the session analyzer requests, as exposed by the in-account proxy's model list. Batch mode routes via the Anthropic passthrough, so it must also be a model ID/alias the Anthropic API itself accepts."
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
# tenant-key secret ARN are set. Only content-free metadata ever egresses.

variable "export_endpoint" {
  description = "HTTPS ingest endpoint of the hosted plane the collector and enricher export content-free metadata to (via the export module's PrivateLink endpoint). Empty disables export."
  type        = string
  default     = ""
}

variable "export_tenant_key_secret_arn" {
  description = "ARN of this tenant's vendor-hosted HMAC key secret the exporters sign with. Empty disables export."
  type        = string
  default     = ""
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
