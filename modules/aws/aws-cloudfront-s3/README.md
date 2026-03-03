# aws-cloudfront-s3

Creates S3 buckets and (optionally) CloudFront distributions in front of them.
Also creates Cloudflare DNS records for the bucket hostname (and a Page Rule to disable origin SSL when using S3 Website endpoints).

Key behavior:

- If `aws_buckets_list[*].cloudfront == true`, the module creates a CloudFront distribution and an S3 bucket policy that allows CloudFront to read objects.
- If `aws_buckets_list[*].public == true` and `cloudfront != true`, the module configures S3 Website hosting and attaches a public-read bucket policy.
  - This can fail if S3 Block Public Access (account-level or org/SCP) prevents public policies.
- If a bucket item does not specify `zone_id` (or it is an empty string), the module uses `CLOUDFLARE_ZONE_ID`.
- The module always configures default bucket encryption:
  - `AES256` when no KMS key is configured.
  - `aws:kms` when `kms_key_arn` is set or `kms_key_create = true`.
- Optional KMS key and alias can be created per bucket.
- Lifecycle supports soft-delete, retention expiration, and Glacier/Deep Archive transitions.
- You can manage named IAM users via `iam_users` with roles: `read`, `write`, `read+write`, `admin`.
- Legacy `create_*` IAM user flags are removed; use `iam_users` only.


## Usage

```hcl
variable "SSL_CERTIFICATE_ARN" {
  description = "ARN of the SSL certificate for CloudFront distributions"
  type        = string
  default     = null
}
module "aws_cloudfront_s3" {
  source = "git::https://github.com/BestianCode/terraform.git//modules/aws/aws-cloudfront-s3?ref=1.3.0"

  project_name        = var.project_name
  CLOUDFLARE_ZONE_ID  = var.CLOUDFLARE_ZONE_ID
  SSL_CERTIFICATE_ARN = var.SSL_CERTIFICATE_ARN

  aws_buckets_list = [
    {
      name       = "media.example.com"
      public     = true
      cloudfront = true
      dns_name   = "media.example.com"
      # zone_id  = "" # optional per-bucket override

      # Optional per-bucket override (if omitted, module-level SSL_CERTIFICATE_ARN is used)
      # ssl_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

      read_write_allow_delete = true

      kms_key_create     = true
      kms_key_alias      = "alias/s3-media-example-com"
      bucket_key_enabled = true

      glacier_transition_days = 30
      glacier_storage_class   = "DEEP_ARCHIVE"
      retention_days          = 365

      iam_users = [
        {
          name = "media-sync"
          role = "read+write"
        },
        {
          name = "media-admin"
          role = "admin"
        }
      ]

      cors = [
        {
          allowed_origins = ["https://example.com"]
          allowed_methods = ["GET", "HEAD"]
          max_age_seconds = 3600
        }
      ]
    }
  ]
}
```

## Inputs

- `project_name` (string, required): Used to name IAM users.
- `CLOUDFLARE_ZONE_ID` (string, required): Default Cloudflare Zone ID.
- `SSL_CERTIFICATE_ARN` (string, optional): ACM cert ARN (must be in `us-east-1` for CloudFront).
- `aws_buckets_list` (list(object), optional): Buckets to create.
  - `name` (string)
  - `public` (bool)
  - `dns_name` (string, optional): If set, creates Cloudflare DNS record.
  - `zone_id` (string, optional): Per-bucket Cloudflare zone override.
  - `cloudfront` (bool, optional): If true, creates a CloudFront distribution.
  - `ssl_certificate_arn` (string, optional): Per-bucket ACM cert ARN for CloudFront (us-east-1). If omitted, falls back to module input `SSL_CERTIFICATE_ARN`.
  - `soft_delete_days` (number, optional): Noncurrent version expiration.
  - `retention_days` (number, optional): Delete objects after N days.
  - `glacier_transition_days` (number, optional): Transition objects to Glacier storage class after N days.
  - `glacier_storage_class` (string, optional): `GLACIER`, `GLACIER_IR`, or `DEEP_ARCHIVE`.
  - `cors` (list(object), optional)
  - `read_write_allow_delete` (bool, optional): Enables `s3:DeleteObject` for users with `iam_users.role = "read+write"`.
  - `enable_versioning` (bool, optional)
  - `kms_key_arn` (string, optional): Existing KMS key ARN for bucket encryption.
  - `kms_key_create` (bool, optional): Create a dedicated KMS key for this bucket.
  - `kms_key_alias` (string, optional): Alias for created KMS key.
  - `kms_key_rotation` (bool, optional): Enable KMS key rotation.
  - `kms_key_description` (string, optional): Description for created KMS key.
  - `kms_key_deletion_window_days` (number, optional): KMS deletion window in days.
  - `bucket_key_enabled` (bool, optional): Enable S3 Bucket Keys when using SSE-KMS.
  - `iam_users` (list(object), optional): Named IAM users with roles (`read`, `write`, `read+write`, `admin`).

## Notes

- Configure AWS and Cloudflare providers (credentials, regions, tokens) in the calling root module, not inside this module.
- For CloudFront with aliases (`dns_name`), either set per-bucket `ssl_certificate_arn` or module-level `SSL_CERTIFICATE_ARN`.
