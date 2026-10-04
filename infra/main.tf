module "network" {
  origin_port = var.alb_certificate_arn != "" ? 443 : 80

  source             = "./modules/network"
  name               = var.name
  availability_zones = var.availability_zones
}

module "database" {
  source                    = "./modules/database"
  name                      = var.name
  subnet_ids                = module.network.private_subnet_ids
  security_group_id         = module.network.database_sg_id
  instance_class            = var.db_instance_class
  multi_az                  = var.db_multi_az
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.final_snapshot_identifier
}

resource "random_password" "origin" {
  length  = 40
  special = false
}

module "compute" {
  depends_on = [module.network]

  source          = "./modules/compute"
  name            = var.name
  vpc_id          = module.network.vpc_id
  subnet_ids      = module.network.public_subnet_ids
  alb_sg_id       = module.network.alb_sg_id
  web_sg_id       = module.network.web_sg_id
  instance_type   = var.instance_type
  db_host         = module.database.address
  db_secret_arn   = module.database.secret_arn
  origin_token    = random_password.origin.result
  region          = var.region
  certificate_arn = var.alb_certificate_arn
}

module "edge" {
  source = "./modules/edge"
  providers = {
    aws = aws.edge
  }

  name            = var.name
  origin_domain   = var.origin_domain_name != "" ? var.origin_domain_name : module.compute.alb_dns_name
  origin_token    = random_password.origin.result
  origin_https    = var.alb_certificate_arn != ""
  domain_name     = var.domain_name
  certificate_arn = var.cloudfront_certificate_arn
}

resource "aws_route53_record" "site" {
  count   = var.domain_name != "" ? 1 : 0
  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = module.edge.domain_name
    zone_id                = module.edge.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "origin" {
  count   = var.origin_domain_name != "" ? 1 : 0
  zone_id = var.hosted_zone_id
  name    = var.origin_domain_name
  type    = "A"
  alias {
    name                   = module.compute.alb_dns_name
    zone_id                = module.compute.alb_zone_id
    evaluate_target_health = true
  }
}
