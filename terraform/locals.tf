locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region

  reports_bucket_name = "${var.project_name}-reports-${local.account_id}"

  backend_function_name = data.aws_cloudformation_stack.backend.outputs["FunctionName"]
  database_secret_arn   = data.aws_cloudformation_stack.backend.outputs["DatabaseUrlSecretArn"]
  artifacts_bucket_name = data.aws_cloudformation_stack.artifacts.outputs["ArtifactsBucketName"]

  backend_vpc_config    = data.aws_lambda_function.backend.vpc_config[0]
  cognito_issuer        = "https://cognito-idp.${local.region}.amazonaws.com/${aws_cognito_user_pool.users.id}"
  cognito_domain        = "https://${var.cognito_domain_prefix}.auth.${local.region}.amazoncognito.com"
  reports_bucket_arn    = "arn:${data.aws_partition.current.partition}:s3:::${local.reports_bucket_name}"
  reports_queue_arn     = "arn:${data.aws_partition.current.partition}:sqs:${local.region}:${local.account_id}:${var.project_name}-reports"
  report_mailer_log_arn = "arn:${data.aws_partition.current.partition}:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/${var.project_name}-report-mailer:*"
  agenda_parser_log_arn = "arn:${data.aws_partition.current.partition}:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/${var.project_name}-agenda-parser:*"
}
