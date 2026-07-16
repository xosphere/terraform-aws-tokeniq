# --- S3 WAL bucket ---
# The collector writes raw ingest payloads here before processing. This holds
# turn content, so it is fully private (block all public access) and the
# content never leaves the account.

resource "aws_s3_bucket" "wal" {
  bucket = local.wal_bucket_name
}

resource "aws_s3_bucket_public_access_block" "wal" {
  bucket = aws_s3_bucket.wal.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# The session analyzer's map-pass chunk cache lives under analysis-cache/
# beside the wal/ objects. Entries are keyed by chunk hash, so stale keys are
# simply never read again; this expiry is the cache's only eviction. Scoped to
# the prefix — wal/ objects are untouched.
resource "aws_s3_bucket_lifecycle_configuration" "wal" {
  bucket = aws_s3_bucket.wal.id

  rule {
    id     = "expire-analysis-cache"
    status = "Enabled"

    filter {
      prefix = "analysis-cache/"
    }

    expiration {
      days = 30
    }
  }
}
