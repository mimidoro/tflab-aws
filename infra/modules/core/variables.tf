variable "name" {
  description = "Prefix for every resource, e.g. tflab-syd. Must start with tflab- (IAM scope of the GitHub role)."
  type        = string
}

variable "is_primary" {
  description = "true = Sydney writer region, false = Melbourne standby with read replica."
  type        = bool
}

variable "db_source_arn" {
  description = "ARN of the primary RDS instance (standby only)."
  type        = string
  default     = null
}

variable "vpc_cidr" {
  type = string
}

variable "kubernetes_version" {
  type = string
}

variable "admin_arns" {
  description = "IAM principals granted EKS cluster admin."
  type        = list(string)
}

variable "api_allowed_cidrs" {
  type = list(string)
}

variable "zone_id" {
  type = string
}

variable "app_hostname" {
  description = "Global failover hostname, e.g. app.mimidog.click."
  type        = string
}

variable "regional_hostname" {
  description = "Region-pinned hostname, e.g. syd.mimidog.click (used by health checks and drills)."
  type        = string
}

variable "alert_email" {
  type = string
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}
