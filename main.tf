locals {
  cluster_arn            = var.cluster_arn != "" ? var.cluster_arn : aws_ecs_cluster.this[0].arn
  data_service_subnet_id = var.data_service_subnet_id != "" ? var.data_service_subnet_id : var.private_subnet_ids[0]

  collector_image    = "${var.image_registry}/tokeniq-collector:${var.image_tag}"
  enricher_image     = "${var.image_registry}/tokeniq-enricher:${var.image_tag}"
  data_service_image = "${var.image_registry}/tokeniq-data-service:${var.image_tag}"
}

# Fargate cluster for the collector and enricher, created only when the
# customer doesn't bring their own. The data-service always creates its own
# EC2 cluster inside the services module.
resource "aws_ecs_cluster" "this" {
  count = var.cluster_arn == "" ? 1 : 0

  name = var.name_prefix
}

module "core" {
  source = "./modules/core"

  name_prefix         = var.name_prefix
  vpc_id              = var.vpc_id
  discovery_namespace = var.discovery_namespace
  wal_bucket_name     = var.wal_bucket_name

  create_kiro_tenant_key  = var.create_kiro_tenant_key
  kiro_tenant_key         = var.kiro_tenant_key
  kiro_tenant_key_version = var.kiro_tenant_key_version
}

module "ingress" {
  source = "./modules/ingress"

  name_prefix         = var.name_prefix
  vpc_id              = var.vpc_id
  subnet_ids          = var.internet_facing ? var.public_subnet_ids : var.private_subnet_ids
  discovery_namespace = var.discovery_namespace

  create_load_balancer  = var.create_load_balancer
  internet_facing       = var.internet_facing
  allowed_ingress_cidrs = var.allowed_ingress_cidrs
  tls_mode              = var.tls_mode
  acm_certificate_arn   = var.acm_certificate_arn
  route53_zone_id       = var.route53_zone_id
  dns_name              = var.dns_name

  collector_tls_cert_secret_id = module.core.collector_tls_cert_secret_id
  collector_tls_key_secret_id  = module.core.collector_tls_key_secret_id
}

module "intake_litellm" {
  count  = var.litellm_intake_enabled ? 1 : 0
  source = "./modules/intake-litellm"

  name_prefix           = var.name_prefix
  litellm_events_bucket = var.litellm_events_bucket
  litellm_events_prefix = var.litellm_events_prefix
}

module "intake_codecommit" {
  count  = var.git_codecommit_intake_enabled ? 1 : 0
  source = "./modules/intake-codecommit"

  name_prefix           = var.name_prefix
  codecommit_repos      = var.codecommit_repos
  codecommit_account_id = var.codecommit_account_id
}

module "export" {
  count  = var.export_privatelink_service_name != "" ? 1 : 0
  source = "./modules/export"

  name_prefix           = var.name_prefix
  vpc_id                = var.vpc_id
  subnet_ids            = var.private_subnet_ids
  endpoint_service_name = var.export_privatelink_service_name
  ingest_port           = var.export_privatelink_ingest_port
}

module "services" {
  source = "./modules/services"

  name_prefix            = var.name_prefix
  vpc_id                 = var.vpc_id
  cluster_arn            = local.cluster_arn
  private_subnet_ids     = var.private_subnet_ids
  data_service_subnet_id = local.data_service_subnet_id
  tenant_id              = var.tenant_id

  collector_image    = local.collector_image
  enricher_image     = local.enricher_image
  data_service_image = local.data_service_image

  collector_cpu                     = var.collector_cpu
  collector_memory                  = var.collector_memory
  enricher_cpu                      = var.enricher_cpu
  enricher_memory                   = var.enricher_memory
  data_service_instance_type        = var.data_service_instance_type
  data_service_data_volume_gib      = var.data_service_data_volume_gib
  data_service_container_memory_mib = var.data_service_container_memory_mib
  log_retention_days                = var.log_retention_days

  # --- Core wiring ---
  wal_bucket            = module.core.wal_bucket
  wal_bucket_arn        = module.core.wal_bucket_arn
  enrich_topic_arn      = module.core.enrich_topic_arn
  work_enrich_topic_arn = module.core.work_enrich_topic_arn
  enricher_queue_urls   = module.core.enricher_queue_urls
  enricher_queue_arns   = module.core.enricher_queue_arns
  work_queue_url        = module.core.work_queue_url
  work_queue_arn        = module.core.work_queue_arn
  store_apply_queue_url = module.core.store_apply_queue_url
  store_apply_queue_arn = module.core.store_apply_queue_arn

  collector_service_discovery_arn    = module.core.collector_service_discovery_arn
  data_service_service_discovery_arn = module.core.data_service_service_discovery_arn
  data_service_url                   = module.core.data_service_internal_endpoint

  gateway_tenant_key_secret_arn       = module.core.gateway_tenant_key_secret_arn
  kiro_tenant_key_secret_arn          = module.core.kiro_tenant_key_secret_arn
  git_github_webhook_secret_arn       = module.core.git_github_webhook_secret_arn
  git_gitlab_webhook_token_secret_arn = module.core.git_gitlab_webhook_token_secret_arn
  collector_auth_token_secret_arn     = module.core.collector_auth_token_secret_arn
  collector_tls_cert_secret_arn       = module.core.collector_tls_cert_secret_arn
  collector_tls_key_secret_arn        = module.core.collector_tls_key_secret_arn
  data_service_auth_token_secret_arn  = module.core.data_service_auth_token_secret_arn
  data_service_tls_cert_secret_arn    = module.core.data_service_tls_cert_secret_arn
  data_service_tls_key_secret_arn     = module.core.data_service_tls_key_secret_arn

  # --- Ingress wiring ---
  collector_target_group_arn = module.ingress.target_group_arn

  # --- Optional features ---
  price_book_url = var.price_book_url

  litellm_intake_queue_url = var.litellm_intake_enabled ? module.intake_litellm[0].queue_url : ""
  litellm_intake_queue_arn = var.litellm_intake_enabled ? module.intake_litellm[0].queue_arn : ""
  litellm_events_bucket    = var.litellm_events_bucket

  codecommit_intake_queue_url = var.git_codecommit_intake_enabled ? module.intake_codecommit[0].queue_url : ""
  codecommit_intake_queue_arn = var.git_codecommit_intake_enabled ? module.intake_codecommit[0].queue_arn : ""

  git_github_backfill_enabled           = var.git_github_backfill_enabled
  git_github_app_id                     = var.git_github_app_id
  git_github_app_private_key_secret_arn = var.git_github_app_private_key_secret_arn
  git_poll_interval                     = var.git_poll_interval
  git_gitlab_backfill_enabled           = var.git_gitlab_backfill_enabled
  git_gitlab_backfill_token_secret_arn  = var.git_gitlab_backfill_token_secret_arn
  git_codecommit_backfill_enabled       = var.git_codecommit_backfill_enabled
  codecommit_repos                      = var.codecommit_repos
  codecommit_account_id                 = var.codecommit_account_id
  codecommit_read_role_arn              = var.codecommit_read_role_arn

  session_analyzer_enabled                = var.session_analyzer_enabled
  session_analyzer_llm_endpoint           = var.session_analyzer_llm_endpoint
  session_analyzer_llm_model              = var.session_analyzer_llm_model
  session_analyzer_llm_api_key_secret_arn = var.session_analyzer_llm_api_key_secret_arn

  export_endpoint              = var.export_endpoint
  export_tenant_key_secret_arn = var.export_tenant_key_secret_arn
  export_identity_user_mode    = var.export_identity_user_mode
  export_identity_team_mode    = var.export_identity_team_mode
}

module "gateway" {
  count  = var.gateway_enabled ? 1 : 0
  source = "./modules/gateway"

  name_prefix        = var.name_prefix
  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids
  alb_subnet_ids     = length(var.gateway_alb_subnet_ids) > 0 ? var.gateway_alb_subnet_ids : var.private_subnet_ids
  internal           = var.gateway_internal
  cluster_arn        = local.cluster_arn

  allowed_ingress_cidrs = var.gateway_allowed_ingress_cidrs
  certificate_arn       = var.gateway_certificate_arn
  route53_zone_id       = var.route53_zone_id
  dns_name              = var.gateway_dns_name

  image            = var.gateway_image != "" ? var.gateway_image : "${var.image_registry}/tokeniq-gateway:${var.gateway_image_tag}"
  cpu              = var.gateway_cpu
  memory           = var.gateway_memory
  desired_count    = var.gateway_desired_count
  cpu_architecture = "ARM64"

  tenant_id                    = var.tenant_id
  bundle_public_key            = var.gateway_bundle_public_key
  bundle_url                   = var.gateway_bundle_url
  bundle_seed_path             = var.gateway_bundle_seed_path
  bundle_tenant_key_secret_arn = var.gateway_bundle_tenant_key_secret_arn

  # Turn telemetry pushes to the collector's authenticated HTTP intake with
  # the shared HMAC key both services read from modules/core. Requires the
  # collector endpoint to present an ACM certificate (tls_mode = "acm") —
  # the gateway's telemetry client trusts system roots only.
  collector_endpoint              = module.ingress.collector_endpoint
  telemetry_tenant_key_secret_arn = module.core.gateway_tenant_key_secret_arn

  bedrock_enabled       = var.gateway_bedrock_enabled
  bedrock_served_models = var.gateway_bedrock_served_models

  # Shared state for the gateway tasks (rate limits, budgets, response
  # cache). "bundled" creates an ElastiCache replication group reachable
  # only from the gateway tasks; see modules/gateway/redis.tf.
  redis_mode           = var.gateway_redis_mode
  redis_node_type      = var.gateway_redis_node_type
  redis_engine         = var.gateway_redis_engine
  redis_engine_version = var.gateway_redis_engine_version

  log_retention_days = var.log_retention_days

  extra_environment = var.gateway_extra_environment
  extra_secrets     = var.gateway_extra_secrets
}

# The gateway's telemetry client verifies the collector's certificate
# against system roots; a self-signed collector endpoint would fail every
# telemetry push (turns would drop, requests would still serve).
check "gateway_telemetry_tls" {
  assert {
    condition     = !var.gateway_enabled || !module.ingress.client_ca_required
    error_message = "gateway_enabled requires ingress tls_mode = \"acm\" with a load balancer: the gateway's telemetry client cannot trust the self-signed collector certificate."
  }
}

# With bundled Redis the module owns TOKENIQ_REDIS_ADDR; a second value in
# gateway_extra_environment would duplicate the container env var.
check "gateway_redis_addr_owned" {
  assert {
    condition     = var.gateway_redis_mode != "bundled" || !contains(keys(var.gateway_extra_environment), "TOKENIQ_REDIS_ADDR")
    error_message = "gateway_redis_mode = \"bundled\" sets TOKENIQ_REDIS_ADDR itself; remove it from gateway_extra_environment."
  }
}
