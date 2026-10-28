provider "aws" {
  region = "us-east-1"

  # These tags remain on retained resources after the CloudFormation handoff
  # and must not be removed by Terraform during adoption.
  ignore_tags {
    key_prefixes = ["aws:cloudformation:"]
  }
}
