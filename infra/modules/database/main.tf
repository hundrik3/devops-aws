variable "name" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "security_group_id" {
  type = string
}

variable "instance_class" {
  type = string
}

variable "multi_az" {
  type = bool
}

variable "deletion_protection" {
  type = bool
}

variable "skip_final_snapshot" {
  type = bool
}

variable "final_snapshot_identifier" {
  type     = string
  nullable = true
}

resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.subnet_ids
}

resource "aws_db_parameter_group" "this" {
  name_prefix = "${var.name}-"
  family      = "mysql8.4"
  parameter {
    name  = "require_secure_transport"
    value = "ON"
  }
}

resource "aws_db_instance" "this" {
  identifier                      = var.name
  engine                          = "mysql"
  engine_version                  = "8.4"
  instance_class                  = var.instance_class
  allocated_storage               = 20
  storage_type                    = "gp3"
  storage_encrypted               = true
  db_name                         = "portfolio"
  username                        = "portfolio_admin"
  manage_master_user_password     = true
  db_subnet_group_name            = aws_db_subnet_group.this.name
  parameter_group_name            = aws_db_parameter_group.this.name
  vpc_security_group_ids          = [var.security_group_id]
  publicly_accessible             = false
  multi_az                        = var.multi_az
  backup_retention_period         = 1
  auto_minor_version_upgrade      = true
  deletion_protection             = var.deletion_protection
  skip_final_snapshot             = var.skip_final_snapshot
  final_snapshot_identifier       = var.final_snapshot_identifier
  enabled_cloudwatch_logs_exports = ["error", "slowquery"]
  lifecycle {
    precondition {
      condition     = var.skip_final_snapshot || var.final_snapshot_identifier != null
      error_message = "Set a unique final snapshot identifier when final snapshots are enabled."
    }
  }
}

output "address" {
  value = aws_db_instance.this.address
}

output "secret_arn" {
  value = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "identifier" {
  value = aws_db_instance.this.identifier
}
