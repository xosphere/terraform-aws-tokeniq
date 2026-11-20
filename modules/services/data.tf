data "aws_region" "current" {}

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

data "aws_vpc" "this" {
  id = var.vpc_id
}

# AZ-pins the data-service EBS volume and ASG.
data "aws_subnet" "data_service" {
  id = var.data_service_subnet_id
}

# Latest ECS-optimized AL2023 AMI for the data-service host.
data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}

locals {
  region     = data.aws_region.current.name
  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id

  # --- Feature gates ---
  export_enabled            = var.export_endpoint != "" && var.export_tenant_key_secret_arn != ""
  litellm_intake_enabled    = var.litellm_intake_queue_url != ""
  codecommit_intake_enabled = var.codecommit_intake_queue_url != ""
  git_backfill_enabled      = var.git_github_backfill_enabled || var.git_gitlab_backfill_enabled || var.git_codecommit_backfill_enabled

  # The export tenant key can be a vendor-hosted secret read cross-account
  # (and possibly cross-region) by full ARN, encrypted under the vendor's
  # CMK. Its kms:ViaService is Secrets Manager in the SECRET's region, which
  # need not be this deployment's region.
  export_kms_via_services = distinct([
    "secretsmanager.${local.region}.amazonaws.com",
    "secretsmanager.${try(split(":", var.export_tenant_key_secret_arn)[3], local.region)}.amazonaws.com",
  ])

  codecommit_account = var.codecommit_account_id != "" ? var.codecommit_account_id : local.account_id

  # --- data-service storage layout ---
  data_service_mount_dir   = "/var/lib/tokeniq-data-service"
  data_service_sqlite_path = "${local.data_service_mount_dir}/tokeniq.db"
}
