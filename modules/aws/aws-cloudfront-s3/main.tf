resource "aws_s3_bucket" "buckets" {
  for_each = { for b in var.aws_buckets_list : b.name => b }
  bucket   = each.value.name

  dynamic "cors_rule" {
    for_each = each.value.cors != null ? each.value.cors : []
    content {
      allowed_headers = cors_rule.value.allowed_headers
      allowed_methods = cors_rule.value.allowed_methods
      allowed_origins = cors_rule.value.allowed_origins
      expose_headers  = cors_rule.value.exposed_headers
      max_age_seconds = cors_rule.value.max_age_seconds
    }
  }

  dynamic "website" {
    for_each = each.value.public ? [each.value] : []
    content {
      index_document = "index.html"
      error_document = "404.html"
    }
  }
}

resource "aws_s3_bucket_policy" "public" {
  for_each = { for b in var.aws_buckets_list : b.name => b if b.public && b.cloudfront != true }
  bucket   = aws_s3_bucket.buckets[each.key].id

  depends_on = [
    aws_s3_bucket_public_access_block.block,
  ]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.buckets[each.key].arn}/*"
      },
    ]
  })
}

resource "aws_s3_bucket_public_access_block" "block" {
  for_each                = { for b in var.aws_buckets_list : b.name => b }
  bucket                  = aws_s3_bucket.buckets[each.key].id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = !each.value.public
  restrict_public_buckets = !each.value.public
}

resource "aws_s3_bucket_versioning" "versioning" {
  for_each = { for b in var.aws_buckets_list : b.name => b if lookup(b, "enable_versioning", false) }
  bucket   = aws_s3_bucket.buckets[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  for_each = {
    for b in var.aws_buckets_list : b.name => b
    if b.soft_delete_days != null || b.retention_days != null || b.glacier_transition_days != null
  }

  bucket = aws_s3_bucket.buckets[each.key].id

  dynamic "rule" {
    for_each = each.value.soft_delete_days != null ? [each.value.soft_delete_days] : []
    content {
      id     = "soft-delete"
      status = "Enabled"
      noncurrent_version_expiration {
        noncurrent_days = rule.value
      }
    }
  }

  dynamic "rule" {
    for_each = each.value.retention_days != null ? [each.value.retention_days] : []
    content {
      id     = "retention"
      status = "Enabled"
      expiration {
        days = rule.value
      }
      abort_incomplete_multipart_upload {
        days_after_initiation = 7
      }
    }
  }

  dynamic "rule" {
    for_each = each.value.glacier_transition_days != null ? [each.value] : []
    content {
      id     = "glacier-transition"
      status = "Enabled"
      transition {
        days          = rule.value.glacier_transition_days
        storage_class = upper(coalesce(rule.value.glacier_storage_class, "GLACIER"))
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.versioning]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = { for b in var.aws_buckets_list : b.name => b }

  bucket = aws_s3_bucket.buckets[each.key].bucket

  rule {
    bucket_key_enabled = (
      each.value.kms_key_arn != null || lookup(each.value, "kms_key_create", false)
    ) ? lookup(each.value, "bucket_key_enabled", true) : false

    apply_server_side_encryption_by_default {
      sse_algorithm     = (each.value.kms_key_arn != null || lookup(each.value, "kms_key_create", false)) ? "aws:kms" : "AES256"
      kms_master_key_id = each.value.kms_key_arn != null ? each.value.kms_key_arn : try(aws_kms_key.this[each.key].arn, null)
    }
  }
}

resource "aws_cloudfront_origin_access_control" "s3_oac" {
  for_each                          = { for b in var.aws_buckets_list : b.name => b if b.public && b.cloudfront == true }
  name                              = "${each.key}-oac"
  description                       = "Origin Access Control for ${each.key}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

locals {
  default_cloudfront_viewer_request_function_code = <<-EOT
    function handler(event) {
      var req = event.request;
      var uri = req.uri;

      if (uri.endsWith('/')) {
        req.uri += 'index.html';
      } else if (!uri.includes('.')) {
        req.uri += '.html';
      }

      return req;
    }
  EOT

  cloudfront_aliases_by_bucket = {
    for bucket in var.aws_buckets_list : bucket.name => distinct(concat(
      try(bucket.dns_name, null) != null ? [bucket.dns_name] : [],
      try(bucket.dns_names, [])
    ))
    if bucket.public && bucket.cloudfront == true
  }

  cloudfront_primary_alias_by_bucket = {
    for bucket in var.aws_buckets_list : bucket.name => coalesce(
      try(bucket.dns_name, null),
      try(bucket.dns_names[0], null)
    )
    if bucket.public && bucket.cloudfront == true && length(local.cloudfront_aliases_by_bucket[bucket.name]) > 0
  }

  cloudfront_additional_dns_records = {
    for entry in flatten([
      for bucket in var.aws_buckets_list : [
        for alias in try(local.cloudfront_aliases_by_bucket[bucket.name], []) : {
          key      = "${bucket.name}:${alias}"
          bucket   = bucket.name
          dns_name = alias
          zone_id  = bucket.zone_id
        }
        if alias != local.cloudfront_primary_alias_by_bucket[bucket.name]
      ]
      if bucket.public && bucket.cloudfront == true
    ]) : entry.key => entry
  }
}

resource "aws_cloudfront_function" "viewer_request" {
  for_each = {
    for b in var.aws_buckets_list : b.name => b
    if b.public && b.cloudfront == true && lookup(b, "cloudfront_viewer_request_function_enabled", false)
  }

  name = format(
    "%s-%s",
    substr(replace(each.key, "/[^a-zA-Z0-9-_]/", "-"), 0, 55),
    substr(md5(each.key), 0, 8)
  )
  runtime = "cloudfront-js-1.0"
  comment = "Viewer request function for ${each.key}"
  publish = true

  code = coalesce(
    try(each.value.cloudfront_viewer_request_function_code, null),
    local.default_cloudfront_viewer_request_function_code
  )
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  for_each = { for b in var.aws_buckets_list : b.name => b if b.public && b.cloudfront == true }

  lifecycle {
    precondition {
      condition = (
        length(local.cloudfront_aliases_by_bucket[each.key]) == 0 ||
        coalesce(try(each.value.ssl_certificate_arn, null), var.SSL_CERTIFICATE_ARN) != null
      )
      error_message = "When aws_buckets_list[*].dns_name or aws_buckets_list[*].dns_names is set (aliases enabled), you must set either aws_buckets_list[*].ssl_certificate_arn or module input SSL_CERTIFICATE_ARN."
    }
  }

  origin {
    domain_name              = aws_s3_bucket.buckets[each.key].bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.s3_oac[each.key].id
    origin_id                = "S3-${each.key}"
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront distribution for ${each.key}"
  default_root_object = "index.html"
  aliases             = local.cloudfront_aliases_by_bucket[each.key]

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${each.key}"
    dynamic "function_association" {
      for_each = try([aws_cloudfront_function.viewer_request[each.key].arn], [])
      content {
        event_type   = "viewer-request"
        function_arn = function_association.value
      }
    }
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
      headers = ["Origin"]
    }
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name = "${each.key}-cloudfront"
  }

  viewer_certificate {
    acm_certificate_arn            = length(local.cloudfront_aliases_by_bucket[each.key]) > 0 ? coalesce(try(each.value.ssl_certificate_arn, null), var.SSL_CERTIFICATE_ARN) : null
    ssl_support_method             = length(local.cloudfront_aliases_by_bucket[each.key]) > 0 ? "sni-only" : null
    minimum_protocol_version       = length(local.cloudfront_aliases_by_bucket[each.key]) > 0 ? "TLSv1.2_2021" : null
    cloudfront_default_certificate = length(local.cloudfront_aliases_by_bucket[each.key]) == 0 ? true : false
  }
}

resource "aws_s3_bucket_policy" "cloudfront_policy" {
  for_each = { for b in var.aws_buckets_list : b.name => b if b.public && b.cloudfront == true }
  bucket   = aws_s3_bucket.buckets[each.key].id

  depends_on = [
    aws_s3_bucket_public_access_block.block,
  ]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.buckets[each.key].arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.s3_distribution[each.key].arn
          }
        }
      }
    ]
  })
}

resource "cloudflare_dns_record" "cloudfront_website" {
  for_each = { for b in var.aws_buckets_list : b.name => b if try(local.cloudfront_primary_alias_by_bucket[b.name], null) != null }
  zone_id  = each.value.zone_id != "" ? each.value.zone_id : var.CLOUDFLARE_ZONE_ID
  name     = local.cloudfront_primary_alias_by_bucket[each.key]
  type     = "CNAME"
  ttl      = 1
  proxied  = false
  comment  = "Managed by Terraform - CloudFront distribution"
  content  = aws_cloudfront_distribution.s3_distribution[each.key].domain_name
}

resource "cloudflare_dns_record" "cloudfront_aliases" {
  for_each = local.cloudfront_additional_dns_records
  zone_id  = each.value.zone_id != "" ? each.value.zone_id : var.CLOUDFLARE_ZONE_ID
  name     = each.value.dns_name
  type     = "CNAME"
  ttl      = 1
  proxied  = false
  comment  = "Managed by Terraform - CloudFront distribution"
  content  = aws_cloudfront_distribution.s3_distribution[each.value.bucket].domain_name
}

resource "cloudflare_dns_record" "s3_website" {
  for_each = { for b in var.aws_buckets_list : b.name => b if b.public && b.dns_name != null && b.cloudfront != true }
  zone_id  = each.value.zone_id != "" ? each.value.zone_id : var.CLOUDFLARE_ZONE_ID
  name     = each.value.dns_name
  type     = "CNAME"
  ttl      = 1
  proxied  = true
  comment  = "Managed by Terraform - S3 website endpoint"
  content  = aws_s3_bucket.buckets[each.key].website_endpoint
}

locals {
  s3_ssl_off_rules = { for b in var.aws_buckets_list : b.name => b if b.public && b.dns_name != null && b.cloudfront != true }
}

resource "cloudflare_page_rule" "s3_ssl_off" {
  for_each = local.s3_ssl_off_rules
  zone_id  = each.value.zone_id != "" ? each.value.zone_id : var.CLOUDFLARE_ZONE_ID
  target   = "${each.value.dns_name}/*"
  priority = 100 + index(sort(keys(local.s3_ssl_off_rules)), each.key)
  status   = "active"
  actions = {
    ssl = "off"
  }
}

locals {
  bucket_arns                  = { for k, b in aws_s3_bucket.buckets : k => b.arn }
  cloudfront_distribution_arns = { for k, d in aws_cloudfront_distribution.s3_distribution : k => d.arn }
  read_write_allow_delete      = { for b in var.aws_buckets_list : b.name => try(b.read_write_allow_delete, false) }
}

resource "aws_iam_user" "bucket_admin" {
  for_each = { for b in var.aws_buckets_list : b.name => b if b.create_admin }
  name     = "${var.project_name}_s3_${each.key}_admin"
}

resource "aws_iam_user" "bucket_read_write" {
  for_each = { for b in var.aws_buckets_list : b.name => b if b.create_read_write }
  name     = "${var.project_name}_s3_${each.key}_read_write"
}

resource "aws_iam_user_policy" "bucket_admin_policy" {
  for_each = aws_iam_user.bucket_admin
  name     = "${each.key}-admin-policy"
  user     = each.value.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect = "Allow"
          Action = "s3:*"
          Resource = [
            local.bucket_arns[each.key],
            "${local.bucket_arns[each.key]}/*",
          ]
        },
      ],
      try(local.cloudfront_distribution_arns[each.key], null) != null ? [
        {
          Effect = "Allow"
          Action = [
            "cloudfront:ListDistributions",
          ]
          Resource = "*"
        },
        {
          Effect = "Allow"
          Action = [
            "cloudfront:CreateInvalidation",
            "cloudfront:GetDistribution",
            "cloudfront:GetInvalidation",
            "cloudfront:ListInvalidations",
          ]
          Resource = local.cloudfront_distribution_arns[each.key]
        }
      ] : []
    )
  })
}

resource "aws_iam_user_policy" "bucket_read_write_policy" {
  for_each = aws_iam_user.bucket_read_write
  name     = "${each.key}-rw-policy"
  user     = each.value.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect   = "Allow"
          Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
          Resource = local.bucket_arns[each.key]
        },
        {
          Effect   = "Allow"
          Action   = concat(["s3:GetObject", "s3:PutObject"], lookup(local.read_write_allow_delete, each.key, false) ? ["s3:DeleteObject"] : [])
          Resource = "${local.bucket_arns[each.key]}/*"
        },
      ],
      try(local.cloudfront_distribution_arns[each.key], null) != null ? [
        {
          Effect = "Allow"
          Action = [
            "cloudfront:ListDistributions",
          ]
          Resource = "*"
        },
        {
          Effect = "Allow"
          Action = [
            "cloudfront:CreateInvalidation",
            "cloudfront:GetDistribution",
            "cloudfront:GetInvalidation",
            "cloudfront:ListInvalidations",
          ]
          Resource = local.cloudfront_distribution_arns[each.key]
        }
      ] : []
    )
  })
}

locals {
  kms_buckets = { for b in var.aws_buckets_list : b.name => b if lookup(b, "kms_key_create", false) }

  named_iam_users = {
    for entry in flatten([
      for b in var.aws_buckets_list : [
        for user in try(b.iam_users, []) : {
          key      = "${b.name}:${user.name}"
          bucket   = b.name
          username = user.name
          role     = replace(lower(user.role), "+", "")
        }
      ]
    ]) : entry.key => entry
  }

  bucket_kms_arn_map = {
    for b in var.aws_buckets_list :
    b.name => (
      b.kms_key_arn != null ? b.kms_key_arn :
      lookup(b, "kms_key_create", false) ? aws_kms_key.this[b.name].arn : null
    )
    if b.kms_key_arn != null || lookup(b, "kms_key_create", false)
  }

  kms_actions_by_role = {
    read = ["kms:Decrypt", "kms:DescribeKey"]
    write = [
      "kms:DescribeKey", "kms:Encrypt",
      "kms:GenerateDataKey", "kms:GenerateDataKeyWithoutPlaintext", "kms:ReEncrypt*"
    ]
    readwrite = [
      "kms:Decrypt", "kms:DescribeKey", "kms:Encrypt",
      "kms:GenerateDataKey", "kms:GenerateDataKeyWithoutPlaintext", "kms:ReEncrypt*"
    ]
    admin = [
      "kms:Decrypt", "kms:DescribeKey", "kms:Encrypt",
      "kms:GenerateDataKey", "kms:GenerateDataKeyWithoutPlaintext", "kms:ReEncrypt*"
    ]
  }
}

resource "aws_kms_key" "this" {
  for_each = local.kms_buckets

  description             = coalesce(each.value.kms_key_description, "S3 bucket ${each.key} encryption key")
  deletion_window_in_days = each.value.kms_key_deletion_window_days
  enable_key_rotation     = lookup(each.value, "kms_key_rotation", true)
  policy                  = null
}

resource "aws_kms_alias" "this" {
  for_each = local.kms_buckets

  name          = coalesce(each.value.kms_key_alias, "alias/s3-${each.key}")
  target_key_id = aws_kms_key.this[each.key].key_id
}

resource "aws_iam_user" "named" {
  for_each = local.named_iam_users
  name     = each.value.username
}

resource "aws_iam_user_policy" "named" {
  for_each = local.named_iam_users

  name = "${each.value.bucket}-${each.value.username}-policy"
  user = aws_iam_user.named[each.key].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      each.value.role == "admin" ? [{
        Effect = "Allow"
        Action = "s3:*"
        Resource = [
          local.bucket_arns[each.value.bucket],
          "${local.bucket_arns[each.value.bucket]}/*"
        ]
      }] : [],
      each.value.role == "read" ? [
        {
          Effect   = "Allow"
          Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
          Resource = local.bucket_arns[each.value.bucket]
        },
        {
          Effect   = "Allow"
          Action   = ["s3:GetObject"]
          Resource = "${local.bucket_arns[each.value.bucket]}/*"
        }
      ] : [],
      each.value.role == "write" ? [
        {
          Effect   = "Allow"
          Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
          Resource = local.bucket_arns[each.value.bucket]
        },
        {
          Effect   = "Allow"
          Action   = ["s3:PutObject"]
          Resource = "${local.bucket_arns[each.value.bucket]}/*"
        }
      ] : [],
      each.value.role == "readwrite" ? [
        {
          Effect   = "Allow"
          Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
          Resource = local.bucket_arns[each.value.bucket]
        },
        {
          Effect   = "Allow"
          Action   = concat(["s3:GetObject", "s3:PutObject"], lookup(local.read_write_allow_delete, each.value.bucket, false) ? ["s3:DeleteObject"] : [])
          Resource = "${local.bucket_arns[each.value.bucket]}/*"
        }
      ] : [],
      (
        try(local.bucket_kms_arn_map[each.value.bucket], null) != null &&
        length(lookup(local.kms_actions_by_role, each.value.role, [])) > 0
        ) ? [
        {
          Effect   = "Allow"
          Action   = lookup(local.kms_actions_by_role, each.value.role, [])
          Resource = local.bucket_kms_arn_map[each.value.bucket]
        }
      ] : []
    )
  })
}