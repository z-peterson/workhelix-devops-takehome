aws_region     = "us-east-1"
aws_account_id = "123456789012"

# Replace with real IDs from your EKS + VPC Terraform outputs
vpc_id                    = "vpc-0abc123"
availability_zones        = ["us-east-1a", "us-east-1b", "us-east-1c"]
private_route_table_id    = "rtb-0abc123"
cluster_name              = "workhelix-prod"
cluster_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE"
cluster_oidc_issuer_url   = "oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE"
istio_ingress_sg_id       = "sg-0abc123"
s3_bucket_name            = "workhelix-tenant-data"
