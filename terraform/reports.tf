resource "aws_cloudwatch_log_group" "report_mailer" {
  name              = "/aws/lambda/${var.project_name}-report-mailer"
  retention_in_days = var.log_retention_days

  tags = {
    PROJECT_NAME = var.project_name
  }
}

resource "aws_lambda_function" "report_mailer" {
  function_name = "${var.project_name}-report-mailer"
  description   = "${var.project_name} weekly report email delivery"
  role          = aws_iam_role.report_mailer.arn
  package_type  = "Zip"
  runtime       = "python3.14"
  handler       = "app.reports.mailer_handler.handler"
  architectures = ["arm64"]
  memory_size   = 128
  timeout       = 30
  s3_bucket     = local.artifacts_bucket_name
  s3_key        = var.report_mailer_code_s3_key

  environment {
    variables = {
      REPORT_SENDER_EMAIL    = var.report_sender_email
      REPORT_RECIPIENT_EMAIL = var.report_recipient_email
    }
  }

  tags = {
    PROJECT_NAME = var.project_name
  }

  depends_on = [
    aws_cloudwatch_log_group.report_mailer,
    aws_iam_role_policy.report_mailer,
  ]

  lifecycle {
    prevent_destroy = true

    # Lambda does not return the original S3 source location during import.
    ignore_changes = [s3_bucket, s3_key]
  }
}

# aws_lambda_permission has no import support. Create only during the later ownership handoff.
resource "aws_lambda_permission" "report_mailer_from_s3" {
  count = var.enable_recreated_lambda_permissions ? 1 : 0

  statement_id   = "peach-reports-ReportMailerInvokePermission-MfllIiBgjSW3"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.report_mailer.function_name
  principal      = "s3.amazonaws.com"
  source_account = local.account_id
  source_arn     = local.reports_bucket_arn
}

resource "aws_sqs_queue" "reports_dlq" {
  name                      = "${var.project_name}-reports-dlq"
  max_message_size          = 1048576
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true

  tags = {
    PROJECT_NAME = var.project_name
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_sqs_queue" "reports" {
  name                       = "${var.project_name}-reports"
  visibility_timeout_seconds = 1080
  max_message_size           = 1048576
  message_retention_seconds  = 1209600
  sqs_managed_sse_enabled    = true
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.reports_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    PROJECT_NAME = var.project_name
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_vpc_endpoint" "reports_s3" {
  vpc_id            = local.backend_vpc_config.vpc_id
  service_name      = "com.amazonaws.${local.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.route_table_ids

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = ["s3:DeleteObject", "s3:GetBucketLocation", "s3:GetObject", "s3:ListBucket", "s3:PutObject"]
      Resource  = [local.reports_bucket_arn, "${local.reports_bucket_arn}/*"]
    }]
  })

  tags = {
    Name         = "${var.project_name}-reports-s3"
    PROJECT_NAME = var.project_name
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_cloudwatch_log_group" "report_builder" {
  name              = "/aws/lambda/${var.project_name}-report-builder"
  retention_in_days = var.log_retention_days

  tags = {
    PROJECT_NAME = var.project_name
  }
}

resource "aws_lambda_function" "report_builder" {
  function_name = "${var.project_name}-report-builder"
  description   = "${var.project_name} weekly report builder"
  role          = aws_iam_role.report_builder.arn
  package_type  = "Image"
  image_uri     = var.report_builder_image_uri
  architectures = data.aws_lambda_function.backend.architectures
  memory_size   = 512
  timeout       = var.report_builder_timeout

  image_config {
    command = ["app.reports.lambda_handler.handler"]
  }

  vpc_config {
    subnet_ids         = local.backend_vpc_config.subnet_ids
    security_group_ids = local.backend_vpc_config.security_group_ids
  }

  environment {
    variables = {
      APP_ENV        = "production"
      DB_POOLING     = "false"
      DATABASE_URL   = "{{resolve:secretsmanager:${local.database_secret_arn}:SecretString}}"
      REPORTS_BUCKET = aws_s3_bucket.reports.id
    }
  }

  tags = {
    PROJECT_NAME = var.project_name
  }

  depends_on = [
    aws_cloudwatch_log_group.report_builder,
    aws_vpc_endpoint.reports_s3,
    aws_iam_role_policy.report_builder_write,
    aws_iam_role_policy.report_builder_queue,
    aws_iam_role_policy_attachment.report_builder_vpc,
  ]

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_scheduler_schedule" "weekly_report" {
  name                         = "${var.project_name}-weekly-report"
  group_name                   = "default"
  description                  = "Build the previous week's ${var.project_name} meeting report"
  schedule_expression          = "cron(0 7 ? * MON *)"
  schedule_expression_timezone = "Europe/Kyiv"
  state                        = var.reports_schedule_state

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_sqs_queue.reports.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ source = "schedule" })
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_lambda_event_source_mapping" "report_builder" {
  event_source_arn = aws_sqs_queue.reports.arn
  function_name    = aws_lambda_function.report_builder.arn
  batch_size       = 1
  enabled          = true

  lifecycle {
    prevent_destroy = true
  }
}
