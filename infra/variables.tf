variable "domain_name" {
  description = "Route 53 hosted zone created when the domain was registered (playbook step M4)."
  type        = string
}

variable "alert_email" {
  description = "Email address subscribed to the CloudWatch alarm SNS topics."
  type        = string
}

variable "image_tag" {
  description = "Container image tag (git commit SHA) built by the build workflow."
  type        = string
}

variable "kubernetes_version" {
  description = "EKS version. Keep inside standard support - extended support costs 6x."
  type        = string
  default     = "1.36"
}

variable "api_allowed_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint. Narrow to your IP for extra safety."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "console_admin_role_names" {
  description = "IAM role names people sign in with (console / aws login) that get EKS cluster admin."
  type        = list(string)
  default     = ["AccountFullAccessRole"]
}

variable "extra_admin_arns" {
  description = "Additional IAM principals granted cluster admin (the GitHub role and whoever runs apply are added automatically)."
  type        = list(string)
  default     = []
}

variable "cilium_version" {
  type    = string
  default = "1.20.3"
}

variable "chaos_mesh_version" {
  type    = string
  default = "2.8.5"
}

variable "metrics_server_version" {
  type    = string
  default = "3.14.0"
}
