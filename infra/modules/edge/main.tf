terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

variable "name" {
  type = string
}

variable "origin_domain" {
  type = string
}

variable "origin_token" {
  type      = string
  sensitive = true
}

variable "origin_https" {
  type = bool
}

variable "domain_name" {
  type = string
}

variable "certificate_arn" {
  type = string
}

resource "aws_wafv2_web_acl" "this" {
  name  = var.name
  scope = "CLOUDFRONT"
  default_action {
    allow {
    }
  }

  rule {
    name     = "common"
    priority = 1
    override_action {
      none {
      }
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "common"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "rate-limit"
    priority = 2
    action {
      block {
      }
    }

    statement {
      rate_based_statement {
        limit              = 1000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = var.name
    sampled_requests_enabled   = true
  }
}

resource "aws_cloudfront_distribution" "this" {
  enabled     = true
  comment     = var.name
  price_class = "PriceClass_100"
  web_acl_id  = aws_wafv2_web_acl.this.arn
  aliases     = var.domain_name != "" ? [var.domain_name] : []
  origin {
    domain_name = var.origin_domain
    origin_id   = "alb"
    custom_header {
      name  = "X-Origin-Verify"
      value = var.origin_token
    }

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = var.origin_https ? "https-only" : "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "alb"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    compress               = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = var.domain_name == ""
    acm_certificate_arn            = var.domain_name != "" ? var.certificate_arn : null
    ssl_support_method             = var.domain_name != "" ? "sni-only" : null
    minimum_protocol_version       = var.domain_name != "" ? "TLSv1.2_2021" : "TLSv1"
  }
}

output "domain_name" {
  value = aws_cloudfront_distribution.this.domain_name
}

output "hosted_zone_id" {
  value = aws_cloudfront_distribution.this.hosted_zone_id
}

output "distribution_id" {
  value = aws_cloudfront_distribution.this.id
}
