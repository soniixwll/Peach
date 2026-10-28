output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.users.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.spa.id
}

output "cognito_domain" {
  value = local.cognito_domain
}

output "cognito_issuer" {
  value = local.cognito_issuer
}

output "reports_bucket_name" {
  value = aws_s3_bucket.reports.id
}

output "reports_queue_url" {
  value = aws_sqs_queue.reports.url
}

output "reports_queue_arn" {
  value = aws_sqs_queue.reports.arn
}

output "reports_dead_letter_queue_url" {
  value = aws_sqs_queue.reports_dlq.url
}

output "report_builder_function_name" {
  value = aws_lambda_function.report_builder.function_name
}

output "report_mailer_function_name" {
  value = aws_lambda_function.report_mailer.function_name
}

output "weekly_report_schedule_arn" {
  value = aws_scheduler_schedule.weekly_report.arn
}

output "agenda_parser_function_name" {
  value = aws_lambda_function.agenda_parser.function_name
}

output "agenda_parser_function_url" {
  value = aws_lambda_function_url.agenda_parser.function_url
}
