resource "google_sql_database_instance" "peach" {
  project          = var.project_id
  name             = "${local.name_prefix}-postgres"
  region           = var.region
  database_version = "POSTGRES_17"

  # Keep this true while the lab contains useful data. Cleanup is an explicit
  # two-step change: first disable protection in a reviewed run, then destroy.
  deletion_protection = true

  settings {
    tier              = "db-f1-micro"
    availability_type = "ZONAL"
    disk_type         = "PD_HDD"
    disk_size         = 10
    disk_autoresize   = false
    edition           = "ENTERPRISE"

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = false
      start_time                     = "03:00"
      transaction_log_retention_days = 1
      backup_retention_settings {
        retained_backups = 1
        retention_unit   = "COUNT"
      }
    }

    ip_configuration {
      ipv4_enabled = true
      ssl_mode     = "ENCRYPTED_ONLY"
    }

    insights_config {
      query_insights_enabled = false
    }

    user_labels = local.labels
  }

  depends_on = [google_project_service.core["sqladmin.googleapis.com"]]
}

resource "google_sql_database" "peach" {
  project  = var.project_id
  name     = var.db_name
  instance = google_sql_database_instance.peach.name
}

resource "google_sql_user" "application" {
  project  = var.project_id
  name     = var.db_user
  instance = google_sql_database_instance.peach.name
  password = var.db_password
}
