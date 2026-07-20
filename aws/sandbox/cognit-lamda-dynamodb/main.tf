terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
}

# ==========================================
# 1. DynamoDB テーブル作成
# ==========================================
resource "aws_dynamodb_table" "user_table" {
  name         = "UserTable"
  billing_mode = "PAY_PER_REQUEST" # オンデマンドキャパシティ
  hash_key     = "userId"

  attribute {
    name = "userId"
    type = "S"
  }

  tags = {
    Environment = "Dev"
  }
}

# ==========================================
# 2. Cognito ユーザープール & クライアント作成
# ==========================================
resource "aws_cognito_user_pool" "user_pool" {
  name = "demo-user-pool"

  # メールアドレスでのサインインを許可
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_lowercase = false
    require_numbers   = false
    require_symbols   = false
    require_uppercase = false
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "demo-app-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  # CLIや認証APIからのログイン（パスワード認証）を許可する設定
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]

  generate_secret = false # フロントエンド/CLIで扱うためシークレットはOFF
}

# ==========================================
# 3. Lambda 用 IAM ロール & ポリシー
# ==========================================
resource "aws_iam_role" "lambda_role" {
  name = "demo_lambda_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# CloudWatch Logs 出力権限の付与
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# DynamoDB への読み書き権限付与
resource "aws_iam_policy" "dynamodb_access_policy" {
  name        = "demo_lambda_dynamodb_policy"
  description = "Allow Lambda to access DynamoDB UserTable"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem"
        ]
        Resource = aws_dynamodb_table.user_table.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.dynamodb_access_policy.arn
}

# ==========================================
# 4. Lambda 関数 & 関数URL設定
# ==========================================

# Lambdaコードの自動ZIP化
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "lambda_function.py"
  output_path = "lambda_function.zip"
}

resource "aws_lambda_function" "auth_dynamo_demo" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "demo-cognito-dynamo-function"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.11"
  timeout          = 10

  # 環境変数としてCognito情報を注入（Lambda側で手動書き換え不要にする場合）
  environment {
    variables = {
      REGION       = "ap-northeast-1"
      USER_POOL_ID = aws_cognito_user_pool.user_pool.id
      CLIENT_ID    = aws_cognito_user_pool_client.user_pool_client.id
    }
  }
}

# Lambda 関数URL (Function URL) の発行
resource "aws_lambda_function_url" "demo_url" {
  function_name      = aws_lambda_function.auth_dynamo_demo.function_name
  authorization_type = "NONE" # トークン検証はLambdaコード内で行うため NONE

  cors {
    allow_credentials = false
    allow_origins     = ["*"]
    allow_methods     = ["*"]
    allow_headers     = ["*"]
  }
}

# Function URL へのパブリックアクセス許可
resource "aws_lambda_permission" "allow_function_url" {
  statement_id           = "FunctionURLAllowPublicAccess"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.auth_dynamo_demo.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

# Function URL 経由での Lambda 関数実行許可
resource "aws_lambda_permission" "allow_invoke_function" {
  statement_id             = "FunctionURLAllowInvokeAction"
  action                   = "lambda:InvokeFunction"
  function_name            = aws_lambda_function_url.demo_url.function_arn
  principal                = "*"
}

# ==========================================
# 5. 構築結果の出力 (Outputs)
# ==========================================
output "user_pool_id" {
  value       = aws_cognito_user_pool.user_pool.id
  description = "Cognito User Pool ID"
}

output "client_id" {
  value       = aws_cognito_user_pool_client.user_pool_client.id
  description = "Cognito User Pool Client ID"
}

output "function_url" {
  value       = aws_lambda_function_url.demo_url.function_url
  description = "Lambda Function URL"
}