variable "name" {
  type = string
}

variable "is_primary" {
  type = bool
}

variable "region_label" {
  description = "Human-readable region name shown in the UI and /api/info."
  type        = string
}

variable "core" {
  description = "Outputs of the matching core module."
  type        = any
}

variable "kubernetes_version" {
  type = string
}

variable "pod_cidr" {
  description = "Cilium cluster-pool CIDR. Must not overlap any VPC or the service CIDR."
  type        = string
}

variable "account_id" {
  type = string
}

variable "image_registry" {
  type = string
}

variable "image_tag" {
  type = string
}

variable "web_replicas" {
  type = object({ min = number, max = number })
}

variable "api_replicas" {
  type = object({ min = number, max = number })
}

variable "node_instance_types" {
  description = "Graviton (ARM) Spot pool - several types to improve Spot availability in Melbourne."
  type        = list(string)
  default     = ["t4g.medium", "t4g.large", "m6g.large", "m7g.medium", "m7g.large"]
}

variable "cilium_version" {
  type = string
}

variable "chaos_mesh_version" {
  type = string
}

variable "metrics_server_version" {
  type = string
}
