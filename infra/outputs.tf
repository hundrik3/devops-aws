output "site_url" {
  value = "https://${var.domain_name != "" ? var.domain_name : module.edge.domain_name}"
}

output "autoscaling_group_name" {
  value = module.compute.asg_name
}

output "target_group_arn" {
  value = module.compute.target_group_arn
}

output "database_identifier" {
  value = module.database.identifier
}

output "distribution_id" {
  value = module.edge.distribution_id
}
