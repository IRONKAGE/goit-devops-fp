# ==============================================================================
# 1. Роль для AWS Load Balancer Controller
# ==============================================================================
module "load_balancer_controller_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                              = "${var.cluster_name}-alb-controller-role"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    ex = {
      # Посилаємось на провайдера з нашого eks.tf
      provider_arn               = aws_iam_openid_connect_provider.eks.arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

# ==============================================================================
# 2. Роль для External Secrets Operator, щоб він міг читати AWS Secrets Manager
# ==============================================================================
module "external_secrets_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                      = "${var.cluster_name}-external-secrets-role"
  attach_external_secrets_policy = true # Модуль сам створить правильну політику!

  oidc_providers = {
    ex = {
      provider_arn               = aws_iam_openid_connect_provider.eks.arn
      namespace_service_accounts = ["default:external-secrets"]
    }
  }
}

# ==============================================================================
# 3. Роль для Argo CD (Доступ до ECR)
# ==============================================================================
# Кастомна політика для читання образів з ECR
resource "aws_iam_policy" "argocd_ecr_policy" {
  name        = "${var.cluster_name}-argocd-ecr-policy"
  description = "Allow Argo CD to pull images from ECR"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}

# Прив'язка політики до ServiceAccount Argo CD
module "argocd_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-argocd-repo-server"

  # Передаємо нашу кастомну політику сюди
  role_policy_arns = {
    argocd_ecr = aws_iam_policy.argocd_ecr_policy.arn
  }

  oidc_providers = {
    ex = {
      provider_arn               = aws_iam_openid_connect_provider.eks.arn
      # Зв'язуємо з неймспейсом та сервіс-акаунтом Argo CD
      namespace_service_accounts = ["argocd:argocd-repo-server"]
    }
  }
}
