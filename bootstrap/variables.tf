variable "github_repo" {
  description = "owner/repo allowed to assume the deploy role."
  type        = string
  default     = "mimidoro/tflab-aws"
}

variable "github_environment" {
  description = "GitHub environment that AWS-facing jobs run in. Only jobs in this environment can assume the role."
  type        = string
  default     = "lab"
}

variable "alert_email" {
  type    = string
  default = "cwdyang888@gmail.com"
}

variable "budget_usd" {
  description = "Monthly budget, net of credits."
  type        = number
  default     = 100
}

variable "kill_switch_usd" {
  description = "Net spend at which the deny-create policy is attached to the deploy role."
  type        = number
  default     = 90
}

variable "replica_region" {
  type    = string
  default = "ap-southeast-4"
}
