variable "tenant_name" {
  description = "Unique slug identifier for the tenant. Used as the Kubernetes namespace name, IAM resource name prefix, S3 prefix, and Secrets Manager path prefix. Must be lowercase alphanumeric with hyphens, starting with a letter, 2-32 characters."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,30}[a-z0-9]$", var.tenant_name))
    error_message = "tenant_name must be lowercase alphanumeric and hyphens only, start with a letter, end with a letter or digit, and be between 2 and 32 characters."
  }
}

variable "environment" {
  description = "Deployment environment. Controls resource naming and determines the Secrets Manager path prefix (<environment>/<tenant_name>/*)."
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "vpc_id" {
  description = "ID of the VPC in which tenant subnets and the security group will be created."
  type        = string
}

variable "availability_zones" {
  description = "List of AWS availability zones in which to create one private subnet each. Must contain between 1 and 3 AZs. The tenant CIDR block is subdivided into /26 slabs, one per AZ."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 1 && length(var.availability_zones) <= 3
    error_message = "availability_zones must contain between 1 and 3 availability zones."
  }
}

variable "tenant_cidr_block" {
  description = "/24 CIDR block within the VPC allocated exclusively for this tenant. The module subdivides this into /26 subnets, one per availability zone. Example: \"10.1.4.0/24\"."
  type        = string
}

variable "private_route_table_id" {
  description = "ID of the existing private route table to associate with the tenant subnets. This route table must already have a default route via a NAT gateway or transit gateway."
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster. Used in subnet tags so that the Kubernetes cloud controller manager and load balancer controller can discover the subnets."
  type        = string
}

variable "cluster_oidc_provider_arn" {
  description = "ARN of the IAM OIDC identity provider for the EKS cluster, used to establish IRSA trust. Example: \"arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE\"."
  type        = string
}

variable "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for the EKS cluster WITHOUT the https:// prefix. Used as the condition variable key in the IRSA trust policy. Example: \"oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE\"."
  type        = string
}

variable "istio_ingress_sg_id" {
  description = "Security group ID attached to the Istio ingress gateway pods. An ingress rule permitting all traffic from this SG is added to the tenant security group so the gateway can route requests to tenant pods."
  type        = string
}

variable "s3_bucket_name" {
  description = "Name of the shared S3 bucket. Tenant workloads are granted access only to the \"<tenant_name>/\" prefix within this bucket. The bucket itself must exist and be managed outside this module."
  type        = string
}

variable "aws_region" {
  description = "AWS region where resources are deployed. Used when constructing Secrets Manager ARNs in the IAM policy."
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID. Used when constructing Secrets Manager ARNs in the IAM policy to ensure the policy cannot be confused by cross-account resource names."
  type        = string
}
