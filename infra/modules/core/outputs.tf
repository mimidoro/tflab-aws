output "region" {
  value = data.aws_region.current.region
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "vpc_cidr" {
  value = var.vpc_cidr
}

output "private_subnet_ids" {
  value = module.vpc.private_subnets
}

output "private_subnet_arns" {
  value = module.vpc.private_subnet_arns
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_ca" {
  value = module.eks.cluster_certificate_authority_data
}

output "cluster_service_cidr" {
  value = module.eks.cluster_service_cidr
}

output "cluster_primary_security_group_id" {
  value = module.eks.cluster_primary_security_group_id
}

output "node_security_group_id" {
  value = module.eks.node_security_group_id
}

output "db_instance_arn" {
  value = aws_db_instance.this.arn
}

output "db_identifier" {
  value = aws_db_instance.this.identifier
}

output "db_address" {
  value = aws_db_instance.this.address
}

output "db_resource_id" {
  value = aws_db_instance.this.resource_id
}

output "db_master_secret_arn" {
  description = "Only set on the primary."
  value       = try(aws_secretsmanager_secret.db_master[0].arn, null)
}

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "alb_zone_id" {
  value = aws_lb.this.zone_id
}

output "alb_arn_suffix" {
  value = aws_lb.this.arn_suffix
}

output "target_group_arns" {
  value = {
    web = aws_lb_target_group.web.arn
    api = aws_lb_target_group.api.arn
  }
}

output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "regional_hostname" {
  value = var.regional_hostname
}
