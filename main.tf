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
