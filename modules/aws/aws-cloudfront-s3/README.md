# aws-cloudfront-s3

Creates S3 buckets and (optionally) CloudFront distributions in front of them.
Also creates Cloudflare DNS records for the bucket hostname (and a Page Rule to disable origin SSL when using S3 Website endpoints).

Key behavior:

- If `aws_buckets_list[*].cloudfront == true`, the module creates a CloudFront distribution and an S3 bucket policy that allows CloudFront to read objects.
- If `aws_buckets_list[*].public == true` and `cloudfront != true`, the module configures S3 Website hosting and attaches a public-read bucket policy.
  - This can fail if S3 Block Public Access (account-level or org/SCP) prevents public policies.
- If a bucket item does not specify `zone_id` (or it is an empty string), the module uses `CLOUDFLARE_ZONE_ID`.


## Usage

```hcl
variable "SSL_CERTIFICATE_ARN" {
  description = "ARN of the SSL certificate for CloudFront distributions"
  type        = string
  default     = null
}
module "aws_cloudfront_s3" {
  source = "git::https://github.com/BestianCode/terraform.git//modules/aws/aws-cloudfront-s3?ref=1.2.0"

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

      create_read_write = true
      read_write_allow_delete = true

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
  - `soft_delete_days` (number, optional): Noncurrent version expiration.
  - `retention_days` (number, optional): Delete objects after N days.
  - `cors` (list(object), optional)
  - `create_admin` / `create_read_write` / `create_write` / `create_read` (bool, optional)
  - `read_write_allow_delete` (bool, optional)
  - `enable_versioning` (bool, optional)

## Notes

- Configure AWS and Cloudflare providers (credentials, regions, tokens) in the calling root module, not inside this module.
