output "artifact_registry_repository" {
  description = "Artifact Registry repository resource name."
  value       = google_artifact_registry_repository.backend.name
}

output "backend_image" {
  description = "Image reference to build and push before enabling Cloud Run."
  value       = local.backend_image
}

output "cloud_sql_connection_name" {
  description = "Cloud SQL connection name consumed by Cloud Run."
  value       = google_sql_database_instance.peach.connection_name
}

output "cloud_run_service_url" {
  description = "Cloud Run API URL; null until deploy_cloud_run is true."
  value       = var.deploy_cloud_run ? google_cloud_run_v2_service.api[0].uri : null
}

output "migration_job_name" {
  description = "One-off Alembic job; null until deploy_cloud_run is true."
  value       = var.deploy_cloud_run ? google_cloud_run_v2_job.migrate[0].name : null
}

output "firebase_hosting_url" {
  description = "Default Firebase Hosting URL."
  value       = "https://${google_firebase_hosting_site.peach.site_id}.web.app"
}
