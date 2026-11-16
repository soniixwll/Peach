resource "google_service_account" "runtime" {
  project      = var.project_id
  account_id   = "peach-api-runtime"
  display_name = "Peach Cloud Run runtime"
  description  = "Runtime-only identity for the Peach API and migration job"

  depends_on = [google_project_service.core["iam.googleapis.com"]]
}

resource "google_project_iam_member" "runtime_cloud_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = google_service_account.runtime.member
}

resource "google_service_account_iam_member" "terraform_can_use_runtime" {
  service_account_id = google_service_account.runtime.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${var.terraform_service_account_email}"
}

# The HCP Terraform run identity is deliberately not created here. It must be
# bootstrapped once with Workload Identity Federation, outside the identity it
# will subsequently use. No service-account keys are created by this root.
