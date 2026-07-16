data "aws_caller_identity" "current" {}

locals {
  wal_bucket_name = var.wal_bucket_name != "" ? var.wal_bucket_name : "${var.name_prefix}-wal-${data.aws_caller_identity.current.account_id}"
}
