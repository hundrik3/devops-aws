mock_provider "aws" {
  mock_resource "aws_launch_template" { defaults = { id = "lt-12345678901234567" } }
  mock_resource "aws_lb" { defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/test/1234567890123456" } }
  mock_resource "aws_lb_listener" { defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/test/1234567890123456/1234567890123456" } }
  mock_resource "aws_lb_target_group" { defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/test/1234567890123456" } }
  mock_resource "aws_iam_instance_profile" { defaults = { arn = "arn:aws:iam::123456789012:instance-profile/test" } }
  mock_resource "aws_route_table" { defaults = { route = [] } }
  mock_resource "aws_db_instance" { defaults = { master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:local-test", kms_key_id = "test", secret_status = "active" }] } }

  mock_data "aws_ec2_managed_prefix_list" {
    defaults = {
      id = "pl-12345678"
    }
  }

  mock_data "aws_ami" {
    defaults = {
      id = "ami-12345678901234567"
    }
  }
}

mock_provider "aws" {
  alias = "edge"
}

mock_provider "random" {
}

run "network_security" {
  command = apply
  module {
    source = "./modules/network"
  }

  variables {
    name               = "test-lab"
    availability_zones = ["us-east-1a", "us-east-1b"]
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.web.referenced_security_group_id == aws_security_group.alb.id && aws_vpc_security_group_ingress_rule.web.from_port == 8080
    error_message = "Only ALB may reach the web tier."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.database.referenced_security_group_id == aws_security_group.web.id && aws_vpc_security_group_ingress_rule.database.from_port == 3306
    error_message = "Only the web tier may reach MySQL."
  }

  assert {
    condition     = length(aws_route_table.private.route) == 0 && alltrue([for s in aws_subnet.private : !s.map_public_ip_on_launch])
    error_message = "Database subnets must have no Internet route or public IP."
  }
}

run "database_security" {
  command = apply
  module {
    source = "./modules/database"
  }

  variables {
    name                      = "test-lab"
    subnet_ids                = ["subnet-11111111", "subnet-22222222"]
    security_group_id         = "sg-12345678"
    instance_class            = "db.t3.micro"
    multi_az                  = false
    deletion_protection       = false
    skip_final_snapshot       = true
    final_snapshot_identifier = null
  }

  assert {
    condition     = aws_db_instance.this.storage_encrypted && !aws_db_instance.this.publicly_accessible && aws_db_instance.this.manage_master_user_password
    error_message = "RDS must be private, encrypted and use a managed secret."
  }

  assert {
    condition     = one(aws_db_parameter_group.this.parameter).value == "ON"
    error_message = "Database transport encryption must be required."
  }
}

run "full_stack" {
  command = apply
  assert {
    condition     = module.compute.asg_name == var.name
    error_message = "Full-stack module wiring failed."
  }
}

run "compute_security" {
  command = apply
  module { source = "./modules/compute" }
  variables {
    name            = "test-lab"
    vpc_id          = "vpc-12345678"
    subnet_ids      = ["subnet-11111111", "subnet-22222222"]
    alb_sg_id       = "sg-11111111"
    web_sg_id       = "sg-22222222"
    instance_type   = "t3.micro"
    db_host         = "test.example"
    db_secret_arn   = "arn:aws:secretsmanager:us-east-1:123456789012:secret:test"
    origin_token    = "test-only-origin-token"
    region          = "us-east-1"
    certificate_arn = ""
  }
  assert {
    condition     = aws_launch_template.this.metadata_options[0].http_tokens == "required" && aws_launch_template.this.block_device_mappings[0].ebs[0].encrypted
    error_message = "IMDSv2 and encrypted root volumes are required."
  }
  assert {
    condition     = aws_autoscaling_group.this.min_size == 2 && aws_autoscaling_group.this.max_size == 3 && aws_autoscaling_group.this.health_check_type == "ELB"
    error_message = "The web tier requires bounded scaling and ALB health checks."
  }
  assert {
    condition     = aws_lb_listener.this.default_action[0].fixed_response[0].status_code == "403" && one(aws_lb_listener_rule.origin.condition).http_header[0].http_header_name == "X-Origin-Verify"
    error_message = "The ALB must reject requests without the private origin header."
  }
  assert {
    condition     = jsondecode(aws_iam_role_policy.secret.policy).Statement[0].Resource == var.db_secret_arn
    error_message = "The application role must be scoped to its database secret."
  }
}
run "edge_security" {
  command = apply
  module { source = "./modules/edge" }
  variables {
    name            = "test-lab"
    origin_domain   = "alb.example.com"
    origin_token    = "test-only-origin-token"
    origin_https    = false
    domain_name     = ""
    certificate_arn = ""
  }
  assert {
    condition     = aws_cloudfront_distribution.this.default_cache_behavior[0].viewer_protocol_policy == "redirect-to-https" && aws_cloudfront_distribution.this.web_acl_id == aws_wafv2_web_acl.this.arn
    error_message = "CloudFront must enforce HTTPS and attach WAF."
  }
  assert {
    condition     = aws_cloudfront_distribution.this.default_cache_behavior[0].cache_policy_id == "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" && length(aws_wafv2_web_acl.this.rule) == 2
    error_message = "Dynamic responses must not be cached; managed/rate-limit WAF rules are required."
  }
}
run "invalid_zones" {
  command = plan
  module { source = "./modules/network" }
  variables {
    name               = "test-lab"
    availability_zones = ["us-east-1a", "us-east-1a"]
  }
  expect_failures = [var.availability_zones]
}
