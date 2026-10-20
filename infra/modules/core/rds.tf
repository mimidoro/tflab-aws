# PostgreSQL on db.t4g.micro.
#   Sydney  : writer, single-AZ (cost), automated backups 1 day (required for replicas).
#   Melbourne: cross-region read replica - async, typically seconds of lag => RPO well under 15 min.
# Failover = promote the Melbourne replica (drills/promote-replica.sh), which takes ~5-10 min => RTO < 15 min.
# Auth: IAM database authentication for the API (no app passwords anywhere).
# Master password: generated ephemerally and written ONLY to the DB and to our own Secrets Manager
# secret via write-only arguments - it never lands in Terraform state or plan output.
# (RDS-managed master passwords - manage_master_user_password - can't be used: AWS rejects read
#  replicas of a postgres source with it enabled.) Only the db-init Job reads the secret, once.

resource "aws_security_group" "db" {
  name        = "${var.name}-db"
  description = "PostgreSQL from EKS nodes only"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "db_from_nodes" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = module.eks.node_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "API pods (masqueraded to node IP by Cilium)"
}

# Cross-region replicas of an encrypted source need a KMS key in the destination region.
resource "aws_kms_key" "replica" {
  count                   = var.is_primary ? 0 : 1
  description             = "${var.name} RDS replica storage encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

ephemeral "random_password" "db_master" {
  count   = var.is_primary ? 1 : 0
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "db_master" {
  count                   = var.is_primary ? 1 : 0
  name                    = "${var.name}-pg-master"
  description             = "tflab master credentials for ${var.name}-pg (read by the db-init Job only)"
  recovery_window_in_days = 0 # lab: delete immediately on destroy so the name is reusable on the next up
}

resource "aws_secretsmanager_secret_version" "db_master" {
  count     = var.is_primary ? 1 : 0
  secret_id = aws_secretsmanager_secret.db_master[0].id
  secret_string_wo = jsonencode({
    username = "tflab_admin"
    password = ephemeral.random_password.db_master[0].result
  })
  secret_string_wo_version = 1
}

resource "aws_db_instance" "this" {
  identifier     = "${var.name}-pg"
  instance_class = var.db_instance_class

  # Primary-only settings (a replica inherits these from its source)
  engine              = var.is_primary ? "postgres" : null
  engine_version      = var.is_primary ? "17" : null
  allocated_storage   = var.is_primary ? 20 : null
  db_name             = var.is_primary ? "tflab" : null
  username            = var.is_primary ? "tflab_admin" : null
  password_wo         = var.is_primary ? ephemeral.random_password.db_master[0].result : null
  password_wo_version = var.is_primary ? 1 : null

  # Replica-only settings
  replicate_source_db = var.is_primary ? null : var.db_source_arn
  kms_key_id          = var.is_primary ? null : aws_kms_key.replica[0].arn

  storage_type                        = "gp3"
  storage_encrypted                   = true
  iam_database_authentication_enabled = true
  db_subnet_group_name                = module.vpc.database_subnet_group_name
  vpc_security_group_ids              = [aws_security_group.db.id]
  publicly_accessible                 = false
  multi_az                            = false

  backup_retention_period  = 1
  delete_automated_backups = true
  skip_final_snapshot      = true
  deletion_protection      = false
  apply_immediately        = true

  auto_minor_version_upgrade   = true
  performance_insights_enabled = false
  monitoring_interval          = 0

  lifecycle {
    # After a DR drill the replica is promoted; don't let the next plan try to re-attach it.
    ignore_changes = [replicate_source_db]
  }
}
