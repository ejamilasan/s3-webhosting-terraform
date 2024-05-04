terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_acm_certificate" "issued_cert" {
  domain   = var.domain_name
  statuses = ["ISSUED"]
}

data "aws_route53_zone" "main" {
  name = var.domain_name
}

resource "aws_s3_bucket" "s3" {
  bucket = var.domain_name
  tags   = var.tags
}

resource "aws_s3_bucket_ownership_controls" "s3_ownership" {
  bucket = aws_s3_bucket.s3.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "s3_access" {
  bucket = aws_s3_bucket.s3.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_identity" "cloudfront_oai" {}

resource "aws_cloudfront_distribution" "cloudfront" {

  origin {
    domain_name = aws_s3_bucket.s3.bucket_regional_domain_name
    origin_id   = "${var.domain_name}-origin"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.cloudfront_oai.cloudfront_access_identity_path
    }
  }

  aliases = [var.domain_name, "*.${var.domain_name}"]

  default_cache_behavior {
    target_origin_id = "${var.domain_name}-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD", "OPTIONS"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl                = 1
    default_ttl            = 86400
    max_ttl                = 31536000
  }

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US", "CA", "GB", "DE"]
    }
  }

  viewer_certificate {
    acm_certificate_arn = data.aws_acm_certificate.issued_cert.arn
    ssl_support_method  = "sni-only"
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  tags = var.tags
}

resource "aws_s3_bucket_policy" "s3_policy" {
  bucket = aws_s3_bucket.s3.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = {
        AWS = aws_cloudfront_origin_access_identity.cloudfront_oai.iam_arn
      },
      Action    = "s3:GetObject",
      Resource  = "${aws_s3_bucket.s3.arn}/*"
    }]
  })
}


resource "aws_route53_record" "cloudfront_dns" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.cloudfront.domain_name
    zone_id                = aws_cloudfront_distribution.cloudfront.hosted_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "cloudfront_dns_www_redirect" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "www.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300

  records = [var.domain_name]
}
