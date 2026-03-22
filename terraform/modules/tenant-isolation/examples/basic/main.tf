# Basic example: provision cloud-layer isolation for a single tenant.
#
# This example assumes a VPC, EKS cluster, shared S3 bucket, and Istio
# ingress gateway already exist. It provisions the per-tenant subnets,
# security group, and IRSA role.
#
# Usage:
#   terraform init
#   terraform plan -var-file=sample.tfvars

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = var.aws_region
}

module "tenant_acme" {
  source = "../../"

  tenant_name    = "acme"
  environment    = "prod"
  aws_region     = var.aws_region
  aws_account_id = var.aws_account_id

  vpc_id                 = var.vpc_id
  availability_zones     = var.availability_zones
  tenant_cidr_block      = "10.1.4.0/24"
  private_route_table_id = var.private_route_table_id

  cluster_name              = var.cluster_name
  cluster_oidc_provider_arn = var.cluster_oidc_provider_arn
  cluster_oidc_issuer_url   = var.cluster_oidc_issuer_url

  istio_ingress_sg_id = var.istio_ingress_sg_id
  s3_bucket_name      = var.s3_bucket_name
}

output "tenant_subnet_ids"       { value = module.tenant_acme.tenant_subnet_ids }
output "tenant_security_group_id" { value = module.tenant_acme.tenant_security_group_id }
output "tenant_iam_role_arn"     { value = module.tenant_acme.tenant_iam_role_arn }
