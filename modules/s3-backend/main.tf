locals {
  # Формуємо унікальні назви на основі проекту та середовища
  bucket_name = "${var.project_name}-${var.environment}-terraform-state"
  table_name  = "${var.project_name}-${var.environment}-terraform-locks"
}

# 1. S3 Bucket для збереження стейту Terraform
resource "aws_s3_bucket" "terraform_state" {
  bucket        = local.bucket_name
  force_destroy = true # Дозволяє видалити бакет при make destroy (тільки для Dev/Навчання!)

  tags = {
    Name        = local.bucket_name
    Environment = var.environment
  }
}

# 1.1. Блокування публічного доступу (Zero Trust)
resource "aws_s3_bucket_public_access_block" "terraform_state_access" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 1.2. Створюємо власний KMS ключ (Customer Managed Key)
resource "aws_kms_key" "terraform_state" {
  description             = "KMS key for Terraform State encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true # Автоматична щорічна ротація ключа - вимога безпеки FAANG!

  tags = {
    Name        = "${local.bucket_name}-kms-key"
    Environment = var.environment
  }
}

# 1.3. Прив'язуємо KMS ключ до S3 бакета
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state_crypto" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.terraform_state.arn
    }
    bucket_key_enabled = true # Зменшує витрати на виклики API KMS
  }
}

# 2. Увімкнення версіонування (щоб мати бекапи попередніх стейтів)
resource "aws_s3_bucket_versioning" "state_versioning" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# 3. DynamoDB таблиця для блокування стейту (захист від одночасного запуску)
resource "aws_dynamodb_table" "terraform_locks" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name        = local.table_name
    Environment = var.environment
  }
}
