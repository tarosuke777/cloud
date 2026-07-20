terraform {
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
# 1. Cognito の設定
# ==========================================

# ユーザープールの作成
resource "aws_cognito_user_pool" "pool" {
  name = "demo-user-pool"

  # サインイン方法にメールアドレスを指定
  username_attributes = ["email"]
  
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_lowercase = false
    require_numbers   = false
    require_symbols   = false
    require_uppercase = false
  }
}

# アプリケーションクライアントの作成（★ここがポイント）
resource "aws_cognito_user_pool_client" "client" {
  name         = "demo-app-client"
  user_pool_id = aws_cognito_user_pool.pool.id

  # CLIやHTMLからログインするために必要な認証フローを有効化
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH", # ユーザー名・パスワード認証（エラーになったやつです）
    "ALLOW_REFRESH_TOKEN_AUTH", # リフレッシュトークン認証
    "ALLOW_USER_SRP_AUTH"       # デフォルトのSRP認証
  ]

  # クライアントシークレットは今回はオフ（ブラウザJSから叩くため）
  generate_secret = false
}

# ==========================================
# 2. Lambda の設定
# ==========================================

# Lambda用IAMロール
resource "aws_iam_role" "lambda_role" {
  name = "demo-lambda-url-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# 基本的な実行権限のポリシーアタッチ
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# 起動用コードのアーカイブ化
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "lambda.js"
  output_path = "lambda.zip"
}

# Lambda関数の作成
resource "aws_lambda_function" "func" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "demo-auth-function"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda.handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "nodejs18.x"
}

# 関数URLの作成（認証なし: NONE で公開し、コード側やフロントで制御する形）
resource "aws_lambda_function_url" "func_url" {
  function_name      = aws_lambda_function.func.function_name
  authorization_type = "NONE"

  cors {
    allow_credentials = false
    allow_origins     = ["*"]
    allow_methods     = ["GET", "POST"]
    allow_headers     = ["authorization", "content-type"]
    max_age           = 86400
  }
}

# ==========================================
# 3. アウトプット（作成された値を画面に出力）
# ==========================================

output "cognito_client_id" {
  value       = aws_cognito_user_pool_client.client.id
  description = "HTMLの CLIENT_ID に貼り付ける値"
}

output "lambda_url" {
  value       = aws_lambda_function_url.func_url.function_url
  description = "HTMLの API_URL に貼り付ける値"
}