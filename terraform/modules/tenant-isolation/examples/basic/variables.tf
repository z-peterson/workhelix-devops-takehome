variable "aws_region"     { type = string; default = "us-east-1" }
variable "aws_account_id" { type = string }
variable "vpc_id"         { type = string }
variable "availability_zones" { type = list(string); default = ["us-east-1a", "us-east-1b", "us-east-1c"] }
variable "private_route_table_id" { type = string }
variable "cluster_name"              { type = string }
variable "cluster_oidc_provider_arn" { type = string }
variable "cluster_oidc_issuer_url"   { type = string }
variable "istio_ingress_sg_id" { type = string }
variable "s3_bucket_name"      { type = string }
