variable "project_name" {
  description = "Prefix used by the existing Peach resources."
  type        = string
  default     = "peach"
}

variable "backend_stack_name" {
  description = "CloudFormation stack that continues to own the backend and database infrastructure."
  type        = string
  default     = "peach-backend"
}

variable "artifacts_stack_name" {
  description = "CloudFormation stack that continues to own the deployment-artifact bucket."
  type        = string
  default     = "peach-artifacts"
}

variable "cognito_domain_prefix" {
  type    = string
  default = "sofia-peach"
}

variable "auth_callback_url" {
  type    = string
  default = "https://www.sofia-peach.pp.ua/login/"
}

variable "auth_logout_url" {
  type    = string
  default = "https://www.sofia-peach.pp.ua/login/"
}

variable "google_client_id" {
  description = "Existing Google OAuth client ID. Supply through TF_VAR_google_client_id."
  type        = string
  sensitive   = true
}

variable "google_client_secret" {
  description = "Existing Google OAuth client secret. Supply through TF_VAR_google_client_secret."
  type        = string
  sensitive   = true
}

variable "route_table_ids" {
  description = "Existing route tables attached to the reports S3 gateway endpoint."
  type        = set(string)
  default     = ["rtb-061bb62de317f9fe3"]
}

variable "report_builder_image_uri" {
  description = "Container image currently deployed to the report-builder Lambda."
  type        = string
  default     = "451071929383.dkr.ecr.us-east-1.amazonaws.com/peach-backend:b17bf9e3628e-dirty-20261014205428"
}

variable "report_mailer_code_s3_key" {
  description = "Existing report-mailer ZIP object key in the artifacts bucket."
  type        = string
  default     = "report-mailer/5f63b3691a39246363f43589d15801442eff7085e9c4f4b8976d4a1c60567481.zip"
}

variable "report_sender_email" {
  type    = string
  default = "reports@sofia-peach.pp.ua"
}

variable "report_recipient_email" {
  description = "Existing SES-verified report recipient. Supply through TF_VAR_report_recipient_email."
  type        = string
  sensitive   = true
}

variable "report_builder_timeout" {
  type    = number
  default = 180
}

variable "reports_schedule_state" {
  type    = string
  default = "ENABLED"

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.reports_schedule_state)
    error_message = "reports_schedule_state must be ENABLED or DISABLED."
  }
}

variable "agenda_parser_image_uri" {
  description = "Container image currently deployed to the agenda-parser Lambda."
  type        = string
  default     = "451071929383.dkr.ecr.us-east-1.amazonaws.com/peach-backend:c5b29618b062-dirty-20261020062734"
}

variable "parser_model" {
  type    = string
  default = "us.amazon.nova-micro-v1:0"
}

variable "ai_allowed_origin" {
  type    = string
  default = "https://www.sofia-peach.pp.ua"
}

variable "cognito_jwks_json" {
  description = "JWKS snapshot currently injected into the Lambdas. Supply securely through TF_VAR_cognito_jwks_json."
  type        = string
  sensitive   = true
}

variable "ai_budget_notification_email" {
  description = "Existing AWS Budget notification address. Supply through TF_VAR_ai_budget_notification_email."
  type        = string
  sensitive   = true
}

variable "log_retention_days" {
  type    = number
  default = 7
}

variable "enable_recreated_lambda_permissions" {
  description = "Enable only during the reviewed CloudFormation ownership handoff; Lambda permissions cannot be imported."
  type        = bool
  default     = false
}
