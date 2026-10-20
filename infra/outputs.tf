output "app_url" {
  value = "https://${local.app_hostname}"
}

output "regional_urls" {
  value = {
    sydney    = "https://syd.${var.domain_name}"
    melbourne = "https://mel.${var.domain_name}"
  }
}

output "clusters" {
  value = {
    sydney    = { name = module.syd_core.cluster_name, region = "ap-southeast-2" }
    melbourne = { name = module.mel_core.cluster_name, region = "ap-southeast-4" }
  }
}

output "databases" {
  value = {
    primary = { id = module.syd_core.db_identifier, region = "ap-southeast-2" }
    replica = { id = module.mel_core.db_identifier, region = "ap-southeast-4" }
  }
}

output "fis_templates" {
  value = {
    sydney    = module.syd_platform.fis_templates
    melbourne = module.mel_platform.fis_templates
  }
}

output "route53_health_check_id" {
  value = aws_route53_health_check.syd.id
}
