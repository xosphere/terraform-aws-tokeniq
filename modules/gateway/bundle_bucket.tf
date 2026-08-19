# --- Tier 2 bundle hosting ---
#
# The signed config bundle is served from S3 over the REST endpoint so the
# gateway can long-poll it without AWS auth. The bundle carries only key
# HASHES and routing/policy config — no credentials — and the gateway
# verifies every artifact against the pinned public key, so public read
# is safe. Skipped entirely when bundle_url points at another source
# (Tier 3 hosted distributor, or a bucket the customer manages).

resource "aws_s3_bucket" "bundle" {
  count = var.bundle_url == "" ? 1 : 0

  bucket = "${var.name_prefix}-gateway-bundle-${data.aws_caller_identity.current.account_id}"
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket_public_access_block" "bundle" {
  count = var.bundle_url == "" ? 1 : 0

  bucket = aws_s3_bucket.bundle[0].id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "bundle" {
  count = var.bundle_url == "" ? 1 : 0

  bucket     = aws_s3_bucket.bundle[0].id
  depends_on = [aws_s3_bucket_public_access_block.bundle]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadBundle"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.bundle[0].arn}/*"
      }
    ]
  })
}

# Versioning is the recovery path when a bad artifact is published: roll
# back by restoring the previous object version.
resource "aws_s3_bucket_versioning" "bundle" {
  count = var.bundle_url == "" ? 1 : 0

  bucket = aws_s3_bucket.bundle[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

# Optional bootstrap seed: point bundle_seed_path at the signed artifact
# `tokeniq gateway init` produced and the first apply publishes it. Bundle
# content is thereafter published out-of-band (CI per the GitOps guide),
# so changes to the local file are deliberately ignored — without this
# guard, every apply would overwrite the live bundle with the stale
# on-disk copy.
resource "aws_s3_object" "bundle_seed" {
  count = var.bundle_url == "" && var.bundle_seed_path != "" ? 1 : 0

  bucket       = aws_s3_bucket.bundle[0].id
  key          = "v1/bundles/latest"
  content_type = "application/json"
  source       = var.bundle_seed_path
  etag         = filemd5(var.bundle_seed_path)

  lifecycle {
    ignore_changes = [source, etag]
  }
}
