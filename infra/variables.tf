variable "region" {
  default = "us-east-1"
}

variable "name" {
  default = "portfolio-two-tier"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,24}$", var.name))
    error_message = "Use 3-25 lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "availability_zones" {
  default = ["us-east-1a", "us-east-1b"]
}

variable "instance_type" {
  default = "t3.micro"
}

variable "db_instance_class" {
  default = "db.t3.micro"
}

variable "db_multi_az" {
  default = false
}

variable "domain_name" {
  default = ""
  validation {
    condition     = var.domain_name == "" || (var.hosted_zone_id != "" && var.cloudfront_certificate_arn != "")
    error_message = "Custom viewer DNS requires an existing hosted zone and validated ACM certificate in us-east-1."
  }
}

variable "hosted_zone_id" {
  default = ""
}

variable "cloudfront_certificate_arn" {
  default = ""
}

variable "alb_certificate_arn" {
  default = ""
}

variable "origin_domain_name" {
  default = ""
  validation {
    condition     = (var.alb_certificate_arn == "") == (var.origin_domain_name == "") && (var.origin_domain_name == "" || var.hosted_zone_id != "")
    error_message = "Origin HTTPS requires both a matching regional ACM certificate and origin DNS name in an existing hosted zone."
  }
}

variable "deletion_protection" {
  default = false
}

variable "skip_final_snapshot" {
  default = true
}

variable "final_snapshot_identifier" {
  default = null
  type    = string
}
