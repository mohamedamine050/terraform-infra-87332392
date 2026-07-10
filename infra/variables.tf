variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "rds_password" {
  description = "Master password for the PostgreSQL RDS instance (unused when manage_master_user_password is true)"
  type        = string
  sensitive   = true
}
