output "node_group_arn" {
  value = module.nodes.node_group_arn
}

output "fis_templates" {
  value = {
    node_terminate  = aws_fis_experiment_template.node_terminate.id
    db_reboot       = aws_fis_experiment_template.db_reboot.id
    az_blackout     = aws_fis_experiment_template.az_blackout.id
    region_blackout = aws_fis_experiment_template.region_blackout.id
  }
}
