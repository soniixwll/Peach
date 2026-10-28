data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

data "aws_cloudformation_stack" "backend" {
  name = var.backend_stack_name
}

data "aws_cloudformation_stack" "artifacts" {
  name = var.artifacts_stack_name
}

data "aws_lambda_function" "backend" {
  function_name = local.backend_function_name
}
