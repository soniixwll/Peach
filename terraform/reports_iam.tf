resource "aws_iam_role" "report_mailer" {
  name = "peach-reports-ReportMailerRole-6XhSAh03L4Bw"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    PROJECT_NAME = var.project_name
  }

  lifecycle {
    # Inline policies are adopted by separate aws_iam_role_policy resources.
    ignore_changes = [inline_policy]
  }
}

resource "aws_iam_role_policy" "report_mailer" {
  name = "MailWeeklyReports"
  role = aws_iam_role.report_mailer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${local.reports_bucket_arn}/reports/*"
      },
      {
        Effect   = "Allow"
        Action   = "ses:SendRawEmail"
        Resource = "*"
        Condition = {
          StringEquals = {
            "ses:FromAddress" = var.report_sender_email
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = local.report_mailer_log_arn
      }
    ]
  })
}

resource "aws_iam_role" "report_builder" {
  name = "peach-reports-ReportBuilderRole-P9ln8esKNQTt"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    PROJECT_NAME = var.project_name
  }

  lifecycle {
    # Inline policies are adopted by separate aws_iam_role_policy resources.
    ignore_changes = [inline_policy]
  }
}

resource "aws_iam_role_policy" "report_builder_write" {
  name = "WriteWeeklyReports"
  role = aws_iam_role.report_builder.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "s3:PutObject"
      Resource = "${local.reports_bucket_arn}/reports/*"
    }]
  })
}

resource "aws_iam_role_policy" "report_builder_queue" {
  name = "ConsumeReportRequests"
  role = aws_iam_role.report_builder.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:ReceiveMessage"]
      Resource = local.reports_queue_arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "report_builder_vpc" {
  role       = aws_iam_role.report_builder.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role" "scheduler" {
  name = "peach-reports-SchedulerRole-RtKkqohlI7nl"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "scheduler.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    PROJECT_NAME = var.project_name
  }

  lifecycle {
    # Inline policies are adopted by a separate aws_iam_role_policy resource.
    ignore_changes = [inline_policy]
  }
}

resource "aws_iam_role_policy" "scheduler" {
  name = "SendScheduledReportRequest"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sqs:SendMessage"
      Resource = local.reports_queue_arn
    }]
  })
}
