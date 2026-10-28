provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      PROJECT_NAME = var.project_name
    }
  }
}
