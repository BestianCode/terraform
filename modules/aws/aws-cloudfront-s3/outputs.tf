output "s3_bucket_ids" {
  description = "S3 bucket IDs keyed by bucket name."
  value       = { for k, b in aws_s3_bucket.buckets : k => b.id }
}

output "s3_bucket_arns" {
  description = "S3 bucket ARNs keyed by bucket name."
  value       = { for k, b in aws_s3_bucket.buckets : k => b.arn }
}

output "cloudfront_distribution_domain_names" {
  description = "CloudFront distribution domain names keyed by bucket name (only for buckets with cloudfront=true)."
  value       = { for k, d in aws_cloudfront_distribution.s3_distribution : k => d.domain_name }
}
