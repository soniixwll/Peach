resource "aws_iam_role" "agenda_parser" {
  name = "peach-ai-AgendaParserRole-Rvlv2karVjyd"

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

resource "aws_iam_role_policy" "agenda_parser_bedrock" {
  name = "InvokeNovaMicro"
  role = aws_iam_role.agenda_parser.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["bedrock:GetInferenceProfile", "bedrock:InvokeModel"]
      Resource = [
        "arn:${data.aws_partition.current.partition}:bedrock:us-east-1:${local.account_id}:inference-profile/us.amazon.nova-micro-v1:0",
        "arn:${data.aws_partition.current.partition}:bedrock:us-east-1::foundation-model/amazon.nova-micro-v1:0",
        "arn:${data.aws_partition.current.partition}:bedrock:us-east-2::foundation-model/amazon.nova-micro-v1:0",
        "arn:${data.aws_partition.current.partition}:bedrock:us-west-2::foundation-model/amazon.nova-micro-v1:0",
      ]
    }]
  })
}

resource "aws_iam_role_policy" "agenda_parser_logs" {
  name = "WriteParserLogs"
  role = aws_iam_role.agenda_parser.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = local.agenda_parser_log_arn
    }]
  })
}
