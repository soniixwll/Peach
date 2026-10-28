# These declarative imports are intentionally not executed during initial configuration review.

import {
  to = aws_cognito_user_pool.users
  id = "us-east-1_0aVezPaE9"
}

import {
  to = aws_cognito_identity_provider.google
  id = "us-east-1_0aVezPaE9:Google"
}

import {
  to = aws_cognito_user_pool_client.spa
  id = "us-east-1_0aVezPaE9/753rah2if6mt31ge63un1uuhtt"
}

import {
  to = aws_cognito_user_pool_domain.login
  id = "sofia-peach"
}

import {
  to = aws_cognito_managed_login_branding.login
  id = "cbcd2ba0-eef1-4bce-b8d4-8857db5d9095|us-east-1_0aVezPaE9|753rah2if6mt31ge63un1uuhtt"
}

import {
  to = aws_s3_bucket.reports
  id = "peach-reports-451071929383"
}

import {
  to = aws_s3_bucket_server_side_encryption_configuration.reports
  id = "peach-reports-451071929383"
}

import {
  to = aws_s3_bucket_lifecycle_configuration.reports
  id = "peach-reports-451071929383"
}

import {
  to = aws_s3_bucket_ownership_controls.reports
  id = "peach-reports-451071929383"
}

import {
  to = aws_s3_bucket_public_access_block.reports
  id = "peach-reports-451071929383"
}

import {
  to = aws_s3_bucket_notification.reports
  id = "peach-reports-451071929383"
}

import {
  to = aws_vpc_endpoint.reports_s3
  id = "vpce-0e8907e377f2bcf94"
}

import {
  to = aws_cloudwatch_log_group.report_mailer
  id = "/aws/lambda/peach-report-mailer"
}

import {
  to = aws_iam_role.report_mailer
  id = "peach-reports-ReportMailerRole-6XhSAh03L4Bw"
}

import {
  to = aws_iam_role_policy.report_mailer
  id = "peach-reports-ReportMailerRole-6XhSAh03L4Bw:MailWeeklyReports"
}

import {
  to = aws_lambda_function.report_mailer
  id = "peach-report-mailer"
}

import {
  to = aws_sqs_queue.reports_dlq
  id = "https://sqs.us-east-1.amazonaws.com/451071929383/peach-reports-dlq"
}

import {
  to = aws_sqs_queue.reports
  id = "https://sqs.us-east-1.amazonaws.com/451071929383/peach-reports"
}

import {
  to = aws_iam_role.report_builder
  id = "peach-reports-ReportBuilderRole-P9ln8esKNQTt"
}

import {
  to = aws_iam_role_policy.report_builder_write
  id = "peach-reports-ReportBuilderRole-P9ln8esKNQTt:WriteWeeklyReports"
}

import {
  to = aws_iam_role_policy.report_builder_queue
  id = "peach-reports-ReportBuilderRole-P9ln8esKNQTt:ConsumeReportRequests"
}

import {
  to = aws_iam_role_policy_attachment.report_builder_vpc
  id = "peach-reports-ReportBuilderRole-P9ln8esKNQTt/arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

import {
  to = aws_cloudwatch_log_group.report_builder
  id = "/aws/lambda/peach-report-builder"
}

import {
  to = aws_lambda_function.report_builder
  id = "peach-report-builder"
}

import {
  to = aws_iam_role.scheduler
  id = "peach-reports-SchedulerRole-RtKkqohlI7nl"
}

import {
  to = aws_iam_role_policy.scheduler
  id = "peach-reports-SchedulerRole-RtKkqohlI7nl:SendScheduledReportRequest"
}

import {
  to = aws_scheduler_schedule.weekly_report
  id = "default/peach-weekly-report"
}

import {
  to = aws_lambda_event_source_mapping.report_builder
  id = "32db05f3-2123-4864-8b6d-6ccbfbd12985"
}

import {
  to = aws_cloudwatch_log_group.agenda_parser
  id = "/aws/lambda/peach-agenda-parser"
}

import {
  to = aws_iam_role.agenda_parser
  id = "peach-ai-AgendaParserRole-Rvlv2karVjyd"
}

import {
  to = aws_iam_role_policy.agenda_parser_bedrock
  id = "peach-ai-AgendaParserRole-Rvlv2karVjyd:InvokeNovaMicro"
}

import {
  to = aws_iam_role_policy.agenda_parser_logs
  id = "peach-ai-AgendaParserRole-Rvlv2karVjyd:WriteParserLogs"
}

import {
  to = aws_lambda_function.agenda_parser
  id = "peach-agenda-parser"
}

import {
  to = aws_lambda_function_url.agenda_parser
  id = "peach-agenda-parser"
}

import {
  to = aws_budgets_budget.ai_monthly
  id = "451071929383:peach-ai-monthly-5-usd"
}
