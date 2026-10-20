output "node_group_arn" {
  value = module.nodes.node_group_arn
}

output "fis_templates" {
  value = {
    node_terminate  = try(aws_fis_experiment_template.node_terminate[0].id, null)
    db_reboot       = try(aws_fis_experiment_template.db_reboot[0].id, null)
    az_blackout     = try(aws_fis_experiment_template.az_blackout[0].id, null)
    region_blackout = try(aws_fis_experiment_template.region_blackout[0].id, null)
  }
}
