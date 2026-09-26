output "bucket_id" {
  description = "The name of the bucket"
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "The ARN of the bucket"
  value       = aws_s3_bucket.this.arn
}

output "bucket_regional_domain_name" {
  description = "The bucket region-specific domain name"
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "website_endpoint" {
  description = "The website endpoint, if the bucket is configured with a website"
  value       = try(aws_s3_bucket_website_configuration.this[0].website_endpoint, "")
}

output "bucket_domain_name" {
  description = "The bucket domain name"
  value       = aws_s3_bucket.this.bucket_domain_name
}
