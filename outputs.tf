output "vpc_id" {
  description = "ID створеної VPC"
  value       = module.vpc.vpc_id
}

output "ecr_repository_url" {
  description = "URL ECR репозиторію для Makefile"
  value       = module.ecr.repository_url
}

output "eks_cluster_name" {
  description = "Назва EKS кластера"
  value       = module.eks.cluster_name
}

output "update_kubeconfig_command" {
  description = "Команда для налаштування доступу до кластера"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "db_endpoint" {
  description = "URL для підключення до бази даних"
  value       = module.rds.db_endpoint
}

output "db_password" {
  description = "Пароль адміністратора БД"
  value       = module.rds.db_password
  sensitive   = true
}
