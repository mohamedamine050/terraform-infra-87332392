# Random suffix (for debugging)
output "random_suffix" {
  value = random_string.suffix.result
}

# S3 Buckets
output "scripts_bucket_name" {
  value = aws_s3_bucket.scripts.id
}
output "data_bucket_name" {
  value = aws_s3_bucket.data.id
}

# Lambda functions
output "producer_lambda_name" {
  value = aws_lambda_function.producer.function_name
}
output "producer_lambda_arn" {
  value = aws_lambda_function.producer.arn
}
output "consumer_lambda_name" {
  value = aws_lambda_function.consumer.function_name
}
output "consumer_lambda_arn" {
  value = aws_lambda_function.consumer.arn
}

# Lambda layer
output "common_layer_arn" {
  value = aws_lambda_layer_version.common.arn
}

# SQS Queue
output "events_queue_url" {
  value = aws_sqs_queue.events.id
}
output "events_queue_arn" {
  value = aws_sqs_queue.events.arn
}

# Glue jobs
output "validate_job_name" {
  value = aws_glue_job.validate.name
}
output "validate_job_arn" {
  value = aws_glue_job.validate.arn
}
output "sqlgen_job_name" {
  value = aws_glue_job.sqlgen.name
}
output "sqlgen_job_arn" {
  value = aws_glue_job.sqlgen.arn
}
output "rdsload_job_name" {
  value = aws_glue_job.rdsload.name
}
output "rdsload_job_arn" {
  value = aws_glue_job.rdsload.arn
}

# Glue test script URIs (used by CI/CD to replace)
output "validate_script_s3_uri" {
  value = "s3://${aws_s3_bucket.scripts.id}/${aws_s3_object.glue_validate.key}"
}
output "sqlgen_script_s3_uri" {
  value = "s3://${aws_s3_bucket.scripts.id}/${aws_s3_object.glue_sqlgen.key}"
}
output "rdsload_script_s3_uri" {
  value = "s3://${aws_s3_bucket.scripts.id}/${aws_s3_object.glue_rdsload.key}"
}

# Athena
output "athena_database_name" {
  value = aws_athena_database.analytics.name
}

# RDS
output "rds_endpoint" {
  value = aws_db_instance.postgres.endpoint
}
output "rds_port" {
  value = aws_db_instance.postgres.port
}
output "rds_master_secret_arn" {
  value     = aws_db_instance.postgres.master_user_secret[0].secret_arn
  sensitive = true
}

# Step Functions
output "state_machine_arn" {
  value = aws_sfn_state_machine.pipeline.arn
}
output "state_machine_name" {
  value = aws_sfn_state_machine.pipeline.name
}
