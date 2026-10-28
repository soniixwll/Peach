resource "aws_cloudwatch_log_group" "agenda_parser" {
  name              = "/aws/lambda/${var.project_name}-agenda-parser"
  retention_in_days = var.log_retention_days

  tags = {
    PROJECT_NAME = var.project_name
  }
}

resource "aws_lambda_function" "agenda_parser" {
  function_name = "${var.project_name}-agenda-parser"
  description   = "Parse pasted agendas with Amazon Nova for human review"
  role          = aws_iam_role.agenda_parser.arn
  package_type  = "Image"
  image_uri     = var.agenda_parser_image_uri
  architectures = data.aws_lambda_function.backend.architectures
  memory_size   = 512
  timeout       = 30

  image_config {
    command = ["app.ai.lambda_handler.handler"]
  }

  environment {
    variables = {
      APP_ENV           = "production"
      PARSER_MODEL      = var.parser_model
      PARSER_REGION     = "us-east-1"
      COGNITO_ISSUER    = local.cognito_issuer
      COGNITO_CLIENT_ID = aws_cognito_user_pool_client.spa.id
      COGNITO_JWKS_JSON = var.cognito_jwks_json
    }
  }

  tags = {
    PROJECT_NAME = var.project_name
  }

  depends_on = [
    aws_cloudwatch_log_group.agenda_parser,
    aws_iam_role_policy.agenda_parser_bedrock,
    aws_iam_role_policy.agenda_parser_logs,
  ]

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_lambda_function_url" "agenda_parser" {
  function_name      = aws_lambda_function.agenda_parser.function_name
  authorization_type = "NONE"
  invoke_mode        = "BUFFERED"

  cors {
    allow_credentials = false
    allow_headers     = ["authorization", "content-type"]
    allow_methods     = ["POST"]
    allow_origins     = [var.ai_allowed_origin]
    max_age           = 300
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Lambda permissions are the only CloudFormation resources without import support.
resource "aws_lambda_permission" "agenda_parser_url" {
  count = var.enable_recreated_lambda_permissions ? 1 : 0

  statement_id           = "peach-ai-AgendaParserUrlPermission-WjSyyziP5Nl2"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.agenda_parser.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "agenda_parser_invoke" {
  count = var.enable_recreated_lambda_permissions ? 1 : 0

  statement_id             = "peach-ai-AgendaParserInvokePermission-qfWq1YVMEzQM"
  action                   = "lambda:InvokeFunction"
  function_name            = aws_lambda_function.agenda_parser.function_name
  principal                = "*"
  invoked_via_function_url = true
}

resource "aws_budgets_budget" "ai_monthly" {
  name         = "${var.project_name}-ai-monthly-5-usd"
  budget_type  = "COST"
  limit_amount = "5"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  tags = {
    PROJECT_NAME = var.project_name
  }

  cost_filter {
    name   = "Service"
    values = ["Amazon Bedrock"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.ai_budget_notification_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.ai_budget_notification_email]
  }
}
