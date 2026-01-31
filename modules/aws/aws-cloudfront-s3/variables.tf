variable "project_name" {
  type        = string
  description = "Project name used to name IAM users."
}

variable "CLOUDFLARE_ZONE_ID" {
  type        = string
  description = "Default Cloudflare Zone ID used when aws_buckets_list[*].zone_id is empty."
}

variable "SSL_CERTIFICATE_ARN" {
  description = "ARN of the SSL certificate for CloudFront distributions (ACM cert must be in us-east-1)."
  type        = string
  default     = null
}

variable "aws_buckets_list" {
  type = list(object({
    name             = string
    public           = bool
    soft_delete_days = optional(number)
    dns_name         = optional(string)
    zone_id          = optional(string, "")
    cloudfront       = optional(bool, false)
    retention_days   = optional(number)
    cors = optional(list(object({
      allowed_origins = list(string)
      allowed_methods = list(string)
      allowed_headers = optional(list(string))
      exposed_headers = optional(list(string))
      max_age_seconds = optional(number)
    })))
    create_admin            = optional(bool, false)
    create_read_write       = optional(bool, false)
    read_write_allow_delete = optional(bool, false)
    create_write            = optional(bool, false)
    create_read             = optional(bool, false)
    enable_versioning       = optional(bool, false)
  }))

  description = "List of buckets to create/manage. When public=true and cloudfront=false, the module creates an S3 website and a public-read bucket policy."
  default     = []
}
