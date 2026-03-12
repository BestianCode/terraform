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
    name                                       = string
    public                                     = bool
    soft_delete_days                           = optional(number)
    retention_days                             = optional(number)
    dns_name                                   = optional(string)
    zone_id                                    = optional(string, "")
    cloudfront                                 = optional(bool, false)
    ssl_certificate_arn                        = optional(string)
    cloudfront_viewer_request_function_enabled = optional(bool, false)
    cloudfront_viewer_request_function_code    = optional(string)
    cors = optional(list(object({
      allowed_origins = list(string)
      allowed_methods = list(string)
      allowed_headers = optional(list(string))
      exposed_headers = optional(list(string))
      max_age_seconds = optional(number)
    })))
    create_admin                 = optional(bool, false)
    create_read_write            = optional(bool, false)
    read_write_allow_delete      = optional(bool, false)
    enable_versioning            = optional(bool, false)
    kms_key_arn                  = optional(string)
    bucket_key_enabled           = optional(bool, true)
    kms_key_create               = optional(bool, false)
    kms_key_alias                = optional(string)
    kms_key_rotation             = optional(bool, true)
    kms_key_description          = optional(string)
    kms_key_deletion_window_days = optional(number, 30)
    iam_users = optional(list(object({
      name = string
      role = string
    })), [])
    glacier_transition_days = optional(number)
    glacier_storage_class   = optional(string, "GLACIER")
  }))

  validation {
    condition = alltrue([
      for bucket in var.aws_buckets_list : alltrue([
        for user in try(bucket.iam_users, []) : contains(["read", "write", "readwrite", "admin"], replace(lower(user.role), "+", ""))
      ])
    ])
    error_message = "iam_users role must be one of: read, write, read+write, or admin."
  }

  validation {
    condition = alltrue([
      for bucket in var.aws_buckets_list :
      bucket.glacier_storage_class == null ? true :
      contains(["GLACIER", "GLACIER_IR", "DEEP_ARCHIVE"], upper(bucket.glacier_storage_class))
    ])
    error_message = "glacier_storage_class must be one of: GLACIER, GLACIER_IR, DEEP_ARCHIVE."
  }

  description = "List of buckets to create/manage. When public=true and cloudfront=false, the module creates an S3 website and a public-read bucket policy."
  default     = []
}
