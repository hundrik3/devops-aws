variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "alb_sg_id" {
  type = string
}

variable "web_sg_id" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "db_host" {
  type = string
}

variable "db_secret_arn" {
  type = string
}

variable "origin_token" {
  type      = string
  sensitive = true
}

variable "region" {
  type = string
}

variable "certificate_arn" {
  type = string
}

data "aws_ami" "this" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_iam_role" "this" {
  name_prefix = "${var.name}-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }

      Action = "sts:AssumeRole"
      }
    ]
    }
  )
}

resource "aws_iam_role_policy" "secret" {
  role = aws_iam_role.this.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = var.db_secret_arn
      }
    ]
    }
  )
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "this" {
  name_prefix = "${var.name}-"
  role        = aws_iam_role.this.name
}

resource "aws_lb" "this" {
  name                       = var.name
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [var.alb_sg_id]
  subnets                    = var.subnet_ids
  drop_invalid_header_fields = true
}

resource "aws_lb_target_group" "this" {
  name     = var.name
  port     = 8080
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  health_check {
    path    = "/health"
    matcher = "200"
  }
}

resource "aws_lb_listener" "this" {
  load_balancer_arn = aws_lb.this.arn
  port              = var.certificate_arn != "" ? 443 : 80
  protocol          = var.certificate_arn != "" ? "HTTPS" : "HTTP"
  certificate_arn   = var.certificate_arn != "" ? var.certificate_arn : null
  ssl_policy        = var.certificate_arn != "" ? "ELBSecurityPolicy-TLS13-1-2-2021-06" : null
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }
}

resource "aws_lb_listener_rule" "origin" {
  listener_arn = aws_lb_listener.this.arn
  priority     = 1
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  condition {
    http_header {
      http_header_name = "X-Origin-Verify"
      values           = [var.origin_token]
    }
  }
}

resource "aws_launch_template" "this" {
  name_prefix            = "${var.name}-"
  image_id               = data.aws_ami.this.id
  instance_type          = var.instance_type
  update_default_version = true
  iam_instance_profile {
    arn = aws_iam_instance_profile.this.arn
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [var.web_sg_id]
  }

  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 8
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/bootstrap.sh.tftpl", {
    runtime_lock  = file("${path.module}/../../../requirements-runtime.lock")
    app           = file("${path.module}/../../../app/server.py")
    db_host       = var.db_host
    db_secret_arn = var.db_secret_arn
    region        = var.region
    }
  ))
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = var.name, Project = var.name
    }
  }
}

resource "aws_autoscaling_group" "this" {
  name                      = var.name
  min_size                  = 2
  desired_capacity          = 2
  max_size                  = 3
  vpc_zone_identifier       = var.subnet_ids
  target_group_arns         = [aws_lb_target_group.this.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300
  launch_template {
    id      = aws_launch_template.this.id
    version = aws_launch_template.this.latest_version
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  lifecycle {
    ignore_changes = [desired_capacity]
  }

  depends_on = [aws_iam_role_policy.secret, aws_iam_role_policy_attachment.ssm, aws_lb_listener_rule.origin]
}

resource "aws_autoscaling_policy" "cpu" {
  name                   = "${var.name}-cpu"
  autoscaling_group_name = aws_autoscaling_group.this.name
  policy_type            = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 60
  }
}

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "alb_zone_id" {
  value = aws_lb.this.zone_id
}

output "asg_name" {
  value = aws_autoscaling_group.this.name
}

output "target_group_arn" {
  value = aws_lb_target_group.this.arn
}
