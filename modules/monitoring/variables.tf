variable "namespace" {
  description = "Namespace для моніторингу"
  type        = string
  default     = "monitoring"
}

variable "grafana_admin_password" {
  description = "Пароль адміністратора Grafana"
  type        = string
  sensitive   = true
}
