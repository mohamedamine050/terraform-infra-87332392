
# ─────────────────────────────────────────────────────────────────────────────
# Remote backend — state stored in S3, locking via DynamoDB
# (Provisioned by the bootstrap/ folder)
# ─────────────────────────────────────────────────────────────────────────────
terraform {
  backend "s3" {
    bucket         = "tfstate-infra-ok12aisb"
    key            = "infra/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "tflock-infra-ok12aisb"
    encrypt        = true
  }
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
  required_version = ">= 1.5.0"
}

provider "aws" {
  region = var.aws_region
}

# --------------------------------------------------------------------
# Random suffix (16 chars, lowercase alphanumeric)
# --------------------------------------------------------------------
resource "random_string" "suffix" {
  length  = 16
  lower   = true
  upper   = false
  numeric = true
  special = false
}

# --------------------------------------------------------------------
# Default VPC & Subnets
# --------------------------------------------------------------------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# --------------------------------------------------------------------
# IAM Roles & Policies
# --------------------------------------------------------------------
# Lambda role
resource "aws_iam_role" "lambda_role" {
  name = "lambda-role-${random_string.suffix.result}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_service" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_admin" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Glue role
resource "aws_iam_role" "glue_role" {
  name = "glue-role-${random_string.suffix.result}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy_attachment" "glue_admin" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Step Functions role
resource "aws_iam_role" "stepfunctions_role" {
  name = "stepfunctions-role-${random_string.suffix.result}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "stepfunctions_admin" {
  role       = aws_iam_role.stepfunctions_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# --------------------------------------------------------------------
# S3 Buckets (scripts & data)
# --------------------------------------------------------------------
resource "aws_s3_bucket" "scripts" {
  bucket        = "scripts-bucket-${random_string.suffix.result}"
  force_destroy = true
}

resource "aws_s3_bucket" "data" {
  bucket        = "data-bucket-${random_string.suffix.result}"
  force_destroy = true
}

# --------------------------------------------------------------------
# Lambda Test Artifacts (producer & consumer) + Common Layer
# --------------------------------------------------------------------
# Producer Lambda code
resource "local_file" "producer_code" {
  filename = "${path.module}/src/producer_lambda.py"
  content  = <<-EOF
def lambda_handler(event, context):
    return {"statusCode": 200, "body": "Producer TEST"}
EOF
}

data "archive_file" "producer_zip" {
  type        = "zip"
  source_file = local_file.producer_code.filename
  output_path = "${path.module}/dist/producer.zip"
}

resource "aws_s3_object" "producer_zip" {
  bucket = aws_s3_bucket.scripts.id
  key    = "lambda/producer.zip"
  source = data.archive_file.producer_zip.output_path
  etag   = data.archive_file.producer_zip.output_md5
}

# Consumer Lambda code
resource "local_file" "consumer_code" {
  filename = "${path.module}/src/consumer_lambda.py"
  content  = <<-EOF
def lambda_handler(event, context):
    return {"statusCode": 200, "body": "Consumer TEST"}
EOF
}

data "archive_file" "consumer_zip" {
  type        = "zip"
  source_file = local_file.consumer_code.filename
  output_path = "${path.module}/dist/consumer.zip"
}

resource "aws_s3_object" "consumer_zip" {
  bucket = aws_s3_bucket.scripts.id
  key    = "lambda/consumer.zip"
  source = data.archive_file.consumer_zip.output_path
  etag   = data.archive_file.consumer_zip.output_md5
}

# Common Layer code
resource "local_file" "layer_common_code" {
  filename = "${path.module}/layer/python/common.py"
  content  = <<-EOF
def helper():
    return "Layer TEST"
EOF
}

data "archive_file" "common_layer_zip" {
  type        = "zip"
  source_dir  = "${path.module}/layer"
  output_path = "${path.module}/dist/common_layer.zip"
  depends_on  = [local_file.layer_common_code]
}

resource "aws_s3_object" "common_layer_zip" {
  bucket = aws_s3_bucket.scripts.id
  key    = "layer/common_layer.zip"
  source = data.archive_file.common_layer_zip.output_path
  etag   = data.archive_file.common_layer_zip.output_md5
}

resource "aws_lambda_layer_version" "common" {
  layer_name          = "common-layer-${random_string.suffix.result}"
  s3_bucket           = aws_s3_bucket.scripts.id
  s3_key              = aws_s3_object.common_layer_zip.key
  compatible_runtimes = ["python3.9"]
  source_code_hash    = data.archive_file.common_layer_zip.output_base64sha256
}

# Producer Lambda
resource "aws_lambda_function" "producer" {
  function_name    = "producer-lambda-${random_string.suffix.result}"
  s3_bucket        = aws_s3_bucket.scripts.id
  s3_key           = aws_s3_object.producer_zip.key
  source_code_hash = data.archive_file.producer_zip.output_base64sha256
  handler          = "producer_lambda.lambda_handler"
  runtime          = "python3.9"
  timeout          = 30
  memory_size      = 256
  role             = aws_iam_role.lambda_role.arn
  layers           = [aws_lambda_layer_version.common.arn]

  depends_on = [
    aws_s3_object.producer_zip,
    aws_lambda_layer_version.common
  ]
}

# Consumer Lambda
resource "aws_lambda_function" "consumer" {
  function_name    = "consumer-lambda-${random_string.suffix.result}"
  s3_bucket        = aws_s3_bucket.scripts.id
  s3_key           = aws_s3_object.consumer_zip.key
  source_code_hash = data.archive_file.consumer_zip.output_base64sha256
  handler          = "consumer_lambda.lambda_handler"
  runtime          = "python3.9"
  timeout          = 30
  memory_size      = 256
  role             = aws_iam_role.lambda_role.arn
  layers           = [aws_lambda_layer_version.common.arn]

  depends_on = [
    aws_s3_object.consumer_zip,
    aws_lambda_layer_version.common
  ]
}

# --------------------------------------------------------------------
# SQS Queue
# --------------------------------------------------------------------
resource "aws_sqs_queue" "events" {
  name = "events-queue-${random_string.suffix.result}"
}

# --------------------------------------------------------------------
# Glue Test Scripts
# --------------------------------------------------------------------
# Validate script
resource "local_file" "glue_validate_script" {
  filename = "${path.module}/glue/validate_test.py"
  content  = <<-EOF
print("Validate TEST")
EOF
}

resource "aws_s3_object" "glue_validate" {
  bucket = aws_s3_bucket.scripts.id
  key    = "scripts/validate_test.py"
  source = local_file.glue_validate_script.filename
}

# SQLGen script
resource "local_file" "glue_sqlgen_script" {
  filename = "${path.module}/glue/sqlgen_test.py"
  content  = <<-EOF
print("SQLGen TEST")
EOF
}

resource "aws_s3_object" "glue_sqlgen" {
  bucket = aws_s3_bucket.scripts.id
  key    = "scripts/sqlgen_test.py"
  source = local_file.glue_sqlgen_script.filename
}

# RDSLoad script
resource "local_file" "glue_rdsload_script" {
  filename = "${path.module}/glue/rdsload_test.py"
  content  = <<-EOF
print("RDSLoad TEST")
EOF
}

resource "aws_s3_object" "glue_rdsload" {
  bucket = aws_s3_bucket.scripts.id
  key    = "scripts/rdsload_test.py"
  source = local_file.glue_rdsload_script.filename
}

# --------------------------------------------------------------------
# Glue Jobs
# --------------------------------------------------------------------
resource "aws_glue_job" "validate" {
  name         = "validate-job-${random_string.suffix.result}"
  role_arn     = aws_iam_role.glue_role.arn
  glue_version = "4.0"
  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.scripts.id}/${aws_s3_object.glue_validate.key}"
  }
  default_arguments = {
    "--TempDir"      = "s3://${aws_s3_bucket.scripts.id}/temp/"
    "--job-language" = "python"
  }
  max_retries = 0
  timeout     = 10
}

resource "aws_glue_job" "sqlgen" {
  name         = "sqlgen-job-${random_string.suffix.result}"
  role_arn     = aws_iam_role.glue_role.arn
  glue_version = "4.0"
  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.scripts.id}/${aws_s3_object.glue_sqlgen.key}"
  }
  default_arguments = {
    "--TempDir"      = "s3://${aws_s3_bucket.scripts.id}/temp/"
    "--job-language" = "python"
  }
  max_retries = 0
  timeout     = 10
}

resource "aws_glue_job" "rdsload" {
  name         = "rdsload-job-${random_string.suffix.result}"
  role_arn     = aws_iam_role.glue_role.arn
  glue_version = "4.0"
  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.scripts.id}/${aws_s3_object.glue_rdsload.key}"
  }
  default_arguments = {
    "--TempDir"      = "s3://${aws_s3_bucket.scripts.id}/temp/"
    "--job-language" = "python"
    "--extra-jars"   = "" # placeholder for real jar later
  }
  max_retries = 0
  timeout     = 10
}

# --------------------------------------------------------------------
# RDS PostgreSQL Instance (private subnet group, SG open for testing)
# --------------------------------------------------------------------
resource "aws_security_group" "rds_sg" {
  name        = "rds-sg-${random_string.suffix.result}"
  description = "RDS SG open for testing"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_subnet_group" "rds_subnet" {
  name       = "rds-subnet-${random_string.suffix.result}"
  subnet_ids = data.aws_subnets.default.ids
}

resource "aws_db_instance" "postgres" {
  identifier                  = "postgres-rds-${random_string.suffix.result}"
  engine                      = "postgres"
  engine_version              = "13"
  instance_class              = "db.t3.micro"
  allocated_storage           = 20
  username                    = "masteruser"
  publicly_accessible         = true
  skip_final_snapshot         = true
  db_subnet_group_name        = aws_db_subnet_group.rds_subnet.name
  vpc_security_group_ids      = [aws_security_group.rds_sg.id]
  manage_master_user_password = true
  deletion_protection         = false
}

# --------------------------------------------------------------------
# Athena Database
# --------------------------------------------------------------------
resource "aws_athena_database" "analytics" {
  name   = "analytics_db_${random_string.suffix.result}"
  bucket = aws_s3_bucket.data.id
}

# --------------------------------------------------------------------
# Step Functions State Machine
# --------------------------------------------------------------------
data "aws_iam_policy_document" "sf_definition" {
  statement {
    actions = ["lambda:InvokeFunction"]
    resources = [
      aws_lambda_function.producer.arn,
      aws_lambda_function.consumer.arn
    ]
  }

  statement {
    actions = ["glue:StartJobRun"]
    resources = [
      aws_glue_job.validate.arn,
      aws_glue_job.sqlgen.arn,
      aws_glue_job.rdsload.arn
    ]
  }
}

resource "aws_sfn_state_machine" "pipeline" {
  name     = "pipeline-sm-${random_string.suffix.result}"
  role_arn = aws_iam_role.stepfunctions_role.arn

  definition = jsonencode({
    Comment = "E‑commerce pipeline"
    StartAt = "InvokeProducer"
    States = {
      InvokeProducer = {
        Type     = "Task"
        Resource = aws_lambda_function.producer.arn
        Next     = "InvokeConsumer"
      }
      InvokeConsumer = {
        Type     = "Task"
        Resource = aws_lambda_function.consumer.arn
        Next     = "ValidateJob"
      }
      ValidateJob = {
        Type     = "Task"
        Resource = "arn:aws:states:::glue:startJobRun.sync"
        Parameters = {
          JobName = aws_glue_job.validate.name
        }
        Next = "ParallelJobs"
      }
      ParallelJobs = {
        Type = "Parallel"
        Branches = [
          {
            StartAt = "SQLGenJob"
            States = {
              SQLGenJob = {
                Type     = "Task"
                Resource = "arn:aws:states:::glue:startJobRun.sync"
                Parameters = {
                  JobName = aws_glue_job.sqlgen.name
                }
                End = true
              }
            }
          },
          {
            StartAt = "RDSLoadJob"
            States = {
              RDSLoadJob = {
                Type     = "Task"
                Resource = "arn:aws:states:::glue:startJobRun.sync"
                Parameters = {
                  JobName = aws_glue_job.rdsload.name
                }
                End = true
              }
            }
          }
        ]
        End = true
      }
    }
  })
}
