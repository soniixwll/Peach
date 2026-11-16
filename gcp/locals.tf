locals {
  name_prefix = "peach-${var.environment}"

  labels = {
    application = "peach"
    environment = var.environment
    managed_by  = "terraform"
  }

  repository_id    = "peach-backend"
  backend_image    = "${var.region}-docker.pkg.dev/${var.project_id}/${local.repository_id}/peach-backend:${var.backend_image_tag}"
  cloud_sql_socket = "/cloudsql/${google_sql_database_instance.peach.connection_name}"
  database_url     = "postgresql+asyncpg://${var.db_user}:${urlencode(var.db_password)}@/${var.db_name}?host=${local.cloud_sql_socket}"
  core_services = toset([
    "artifactregistry.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "firebase.googleapis.com",
    "firebasehosting.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "serviceusage.googleapis.com",
    "sqladmin.googleapis.com",
    "sts.googleapis.com",
  ])
  demo_services = toset([
    "bigquery.googleapis.com",
    "documentai.googleapis.com",
    "vision.googleapis.com",
  ])
}
