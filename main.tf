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
