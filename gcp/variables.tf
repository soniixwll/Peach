variable "project_id" {
  description = "Google Cloud project dedicated to the Peach GCP lab."
  type        = string
  default     = "peach-gcp-lab"

  validation {
    condition     = var.project_id == "peach-gcp-lab"
    error_message = "This root is intentionally scoped to the peach-gcp-lab project."
  }
}

variable "region" {
  description = "Single region for Cloud Run, Artifact Registry, and Cloud SQL."
  type        = string
  default     = "europe-central2"
}

variable "environment" {
  description = "Short environment label used in resource names and labels."
  type        = string
  default     = "lab"
}

variable "terraform_service_account_email" {
  description = "Pre-bootstrapped HCP Terraform deployment service account email."
  type        = string

  validation {
    condition = endswith(
      var.terraform_service_account_email,
      "@${var.project_id}.iam.gserviceaccount.com",
    )
    error_message = "The Terraform service account must belong to peach-gcp-lab."
  }
}

variable "enable_demo_apis" {
  description = "Enable BigQuery, Vision, and Document AI APIs for the later demo phase."
  type        = bool
  default     = false
}

variable "deploy_cloud_run" {
  description = "Create Cloud Run service/job only after the backend image has been pushed."
  type        = bool
  default     = false
}

variable "backend_image_tag" {
  description = "Immutable tag for the backend image already pushed to Artifact Registry."
  type        = string
  default     = "gcp-lab"
}

variable "db_name" {
  description = "Application database name."
  type        = string
  default     = "peach"
}

variable "db_user" {
  description = "Built-in PostgreSQL application user."
  type        = string
  default     = "peach_app"
}

variable "db_password" {
  description = "Strong database password supplied as a sensitive HCP workspace variable."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 24
    error_message = "db_password must contain at least 24 characters."
  }
}

variable "cognito_issuer" {
  description = "Existing AWS Cognito issuer used by the portable FastAPI API."
  type        = string
  default     = ""
}

variable "cognito_client_id" {
  description = "Existing public Cognito app client ID."
  type        = string
  default     = ""
}

variable "cognito_jwks_json" {
  description = "Current Cognito JWKS snapshot, supplied as a sensitive HCP variable."
  type        = string
  sensitive   = true
  default     = "{\"keys\":[]}"
}

variable "cors_origins" {
  description = "Comma-separated exact Firebase/custom-domain origins allowed by FastAPI."
  type        = string
  default     = "https://peach-gcp-lab.web.app,https://peach-gcp-lab.firebaseapp.com"
}

variable "cloud_run_max_instances" {
  description = "Cost and Cloud SQL connection safety cap."
  type        = number
  default     = 2

  validation {
    condition     = var.cloud_run_max_instances >= 1 && var.cloud_run_max_instances <= 5
    error_message = "For this lab, cloud_run_max_instances must be between 1 and 5."
  }
}
