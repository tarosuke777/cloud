terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

# ------------------------------------------------------------------------------
# 1. 変数定義・プロバイダー設定
# ------------------------------------------------------------------------------
variable "project_id" {
  type        = string
  description = "GCPのプロジェクトID"
}

variable "region" {
  type        = string
  default     = "us-central1"
  description = "デプロイ対象のリージョン"
}

variable "image_tag" {
  type        = string
  default     = "latest"
  description = "コンテナイメージのタグ"
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ------------------------------------------------------------------------------
# 2. 必要なAPIの有効化
# ------------------------------------------------------------------------------
resource "google_project_service" "enabled_apis" {
  for_each = toset([
    "run.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com"
  ])

  service            = each.key
  disable_on_destroy = false
}

# ------------------------------------------------------------------------------
# 3. Artifact Registry (Dockerリポジトリ) の作成
# ------------------------------------------------------------------------------
resource "google_artifact_registry_repository" "my_repo" {
  location      = var.region
  repository_id = "my-app-repo"
  description   = "Cloud Run用のDockerコンテナイメージリポジトリ"
  format        = "DOCKER"

  depends_on = [google_project_service.enabled_apis]
}

# ------------------------------------------------------------------------------
# 4. Cloud Build による自動ビルド & Push (null_resource)
# ------------------------------------------------------------------------------
resource "null_resource" "build_and_push" {
  # ソースコードや設定ファイルが変更された場合のみ再ビルドを実行
app  triggers = {
    dir_sha1 = sha1(join("", [
      filesha1("${path.module}/Dockerfile"),
      filesha1("${path.module}/server.js"),
      filesha1("${path.module}/package.json")
    ]))
  }

  provisioner "local-exec" {
    command = "gcloud builds submit --tag ${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.my_repo.repository_id}/my-app:${var.image_tag} ."
  }

  depends_on = [
    google_project_service.enabled_apis,
    google_artifact_registry_repository.my_repo
  ]
}

# ------------------------------------------------------------------------------
# 5. Cloud Run サービスの作成
# ------------------------------------------------------------------------------
resource "google_cloud_run_v2_service" "default" {
  name     = "cloudrun-auto-app"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.my_repo.repository_id}/my-app:${var.image_tag}"

      resources {
        limits = {
          cpu    = "1000m"
          memory = "512Mi"
        }
      }
    }
  }

  # ビルド処理（null_resource）が正常終了した後にCloud Runを作成する
  depends_on = [null_resource.build_and_push]
}

# ------------------------------------------------------------------------------
# 6. 未認証（パブリック）アクセスの許可
# ------------------------------------------------------------------------------
resource "google_cloud_run_v2_service_iam_member" "noauth" {
  project  = google_cloud_run_v2_service.default.project
  location = google_cloud_run_v2_service.default.location
  name     = google_cloud_run_v2_service.default.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# ------------------------------------------------------------------------------
# 7. 出力（URLを表示）
# ------------------------------------------------------------------------------
output "cloud_run_url" {
  value       = google_cloud_run_v2_service.default.uri
  description = "Cloud Run サービスのアクセスURL"
}