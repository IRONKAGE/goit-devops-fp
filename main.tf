# ==========================================
# ІНІЦІАЛІЗАЦІЯ ПРОВАЙДЕРІВ
# ==========================================
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17.0"
    }
  }
}

provider "aws" {
  region = var.region

  # Налаштування для коректної роботи S3 та AWS API в LocalStack через Docker
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  dynamic "endpoints" {
    for_each = var.environment == "dev" ? [1] : []
    content {
      s3       = "http://${var.localstack_ip}:4566"
      dynamodb = "http://${var.localstack_ip}:4566"
      ec2      = "http://${var.localstack_ip}:4566"
      eks      = "http://${var.localstack_ip}:4566"
      iam      = "http://${var.localstack_ip}:4566"
      rds      = "http://${var.localstack_ip}:4566"
      ecr      = "http://${var.localstack_ip}:4566"
    }
  }
}

module "vpc" {
  source             = "./modules/vpc"
  environment        = var.environment
  project_name       = var.project_name
  vpc_cidr_block     = var.vpc_cidr
  public_subnets     = var.public_subnets_cidr
  private_subnets    = var.private_subnets_cidr
  availability_zones = var.availability_zones
  vpc_name           = "${var.project_name}-${var.environment}-vpc"
}

module "s3_backend" {
  source       = "./modules/s3-backend"
  project_name = var.project_name
  environment  = var.environment
}

module "ecr" {
  source       = "./modules/ecr"
  ecr_name     = var.ecr_repo_name
  scan_on_push = var.scan_on_push
}

resource "aws_iam_role" "eks_cluster_role" {
  name = "${var.cluster_name}-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_iam_role" "eks_node_role" {
  name = "${var.cluster_name}-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_role.name
}
resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_role.name
}

# Повернув ReadOnly за рекомендацією ментора (Principle of Least Privilege)
resource "aws_iam_role_policy_attachment" "eks_container_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_role.name
}

module "eks" {
  source = "./modules/eks"

  environment               = var.environment
  cluster_name              = var.cluster_name
  cluster_version           = var.cluster_version
  subnet_ids                = module.vpc.private_subnet_ids

  cluster_role_arn          = aws_iam_role.eks_cluster_role.arn
  node_role_arn             = aws_iam_role.eks_node_role.arn

  node_instance_types       = var.node_instance_types
  node_min_size             = var.node_min_size
  node_max_size             = var.node_max_size
  node_desired_size         = var.node_desired_size
  enabled_cluster_log_types = var.enabled_cluster_log_types

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry_policy
  ]
}

module "jenkins" {
  source                 = "./modules/jenkins"
  namespace              = "jenkins"
  jenkins_admin_username = var.jenkins_admin_username
  jenkins_admin_password = var.jenkins_admin_password
  depends_on             = [module.eks]
}

module "argo_cd" {
  source      = "./modules/argo_cd"
  namespace   = "argocd"
  github_repo = var.github_repo
  depends_on  = [module.eks]
}

module "rds" {
  source = "./modules/rds"

  project_name       = var.project_name
  environment        = var.environment

  vpc_id             = module.vpc.vpc_id
  vpc_cidr_block     = module.vpc.vpc_cidr_block
  private_subnet_ids = module.vpc.private_subnet_ids

  # ===================================================
  # РОЗУМНИЙ ПЕРЕМИКАЧ СЕРЕДОВИЩ
  # ===================================================
  # Якщо це prod -> розгортаємо Aurora Serverless v2.
  # Якщо dev (LocalStack) -> падаємо на звичайний RDS.
  use_aurora         = var.environment == "prod" ? true : false
  engine_version     = var.engine_version

  # Параметри для фолбеку (використовуються у Dev / LocalStack Pro)
  engine                    = "postgres"
  db_parameter_group_family = "postgres18"
  instance_class            = "db.t3.micro"
  db_port                   = 5432
  multi_az                  = false
}

# ---------------------------------------------
# НАЛАШТУВАННЯ HELM ПРОВАЙДЕРА
# ---------------------------------------------
data "aws_eks_cluster" "main" {
  name       = module.eks.cluster_name
  depends_on = [module.eks]
}

data "aws_eks_cluster_auth" "main" {
  name       = module.eks.cluster_name
  depends_on = [module.eks]
}

provider "helm" {
  kubernetes {
    # Для Prod (AWS) - використовуємо безпечну AWS IAM аутентифікацію
    host                   = var.environment == "prod" ? data.aws_eks_cluster.main.endpoint : null
    cluster_ca_certificate = var.environment == "prod" ? base64decode(data.aws_eks_cluster.main.certificate_authority[0].data) : null
    token                  = var.environment == "prod" ? data.aws_eks_cluster_auth.main.token : null

    # Для Dev (LocalStack) - ігноруємо токени і змушуємо читати локальний конфіг
    config_path            = var.environment == "dev" ? "~/.kube/config" : null
  }
}

module "monitoring" {
  source                 = "./modules/monitoring"
  namespace              = "monitoring"
  grafana_admin_password = var.grafana_admin_password
  depends_on             = [module.eks] # Чекаємо, поки підніметься EKS
}

module "vault" {
  source     = "./modules/vault"
  namespace  = "vault"
  depends_on = [module.eks]
}
