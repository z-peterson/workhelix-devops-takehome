# Module: `tenant-isolation`

Provisions the **cloud-layer boundary** for a single Workhelix enterprise tenant.

## What it creates

| Resource | Purpose |
|---|---|
| `aws_subnet` × N | One private subnet per AZ, carved from the tenant's `/24` CIDR block |
| `aws_route_table_association` × N | Associates each subnet with the shared private route table |
| `aws_security_group` | Allows intra-tenant traffic and ingress from the Istio ingress gateway |
| `aws_iam_role` | IRSA role — pods in the tenant namespace can assume it via OIDC federation |
| `aws_iam_policy` | Grants access only to `s3://<bucket>/<tenant>/` prefix and `/<env>/<tenant>/*` Secrets Manager paths |
| `aws_iam_role_policy_attachment` | Attaches the policy to the role |

## What it does NOT create

Kubernetes resources (namespace, RBAC, NetworkPolicy, ResourceQuota, Istio AuthorizationPolicy) are managed by the `tenant-base` Helm chart reconciled by Flux — not by Terraform. This module outputs the `iam_role_arn` and `security_group_id` that the Helm chart references via pod annotations.

## Usage

```hcl
module "tenant_acme" {
  source = "./modules/tenant-isolation"

  tenant_name    = "acme"
  environment    = "prod"
  aws_region     = "us-east-1"
  aws_account_id = data.aws_caller_identity.current.account_id

  vpc_id                 = module.vpc.vpc_id
  availability_zones     = ["us-east-1a", "us-east-1b", "us-east-1c"]
  tenant_cidr_block      = "10.1.4.0/24"
  private_route_table_id = module.vpc.private_route_table_id

  cluster_name              = module.eks.cluster_name
  cluster_oidc_provider_arn = module.eks.oidc_provider_arn
  cluster_oidc_issuer_url   = module.eks.cluster_oidc_issuer_url

  istio_ingress_sg_id = var.istio_ingress_security_group_id
  s3_bucket_name      = aws_s3_bucket.tenant_data.id
}

# Pass outputs to the Flux HelmRelease values
# module.tenant_acme.tenant_iam_role_arn    → serviceAccount.annotations."eks.amazonaws.com/role-arn"
# module.tenant_acme.tenant_security_group_id → pod security group annotation
# module.tenant_acme.tenant_subnet_ids      → subnet selection for tenant node groups
```

See `examples/basic/` for a runnable example.

## Inputs

| Name | Type | Required | Description |
|---|---|---|---|
| `tenant_name` | `string` | yes | Lowercase slug, 2–32 chars (e.g. `acme`) |
| `environment` | `string` | no | `dev`, `staging`, or `prod` (default: `prod`) |
| `vpc_id` | `string` | yes | VPC to create resources in |
| `availability_zones` | `list(string)` | yes | 1–3 AZs for subnet creation |
| `tenant_cidr_block` | `string` | yes | `/24` CIDR block for this tenant |
| `private_route_table_id` | `string` | yes | Route table for subnet associations |
| `cluster_name` | `string` | yes | EKS cluster name (for subnet discovery tags) |
| `cluster_oidc_provider_arn` | `string` | yes | OIDC provider ARN for IRSA trust |
| `cluster_oidc_issuer_url` | `string` | yes | OIDC issuer URL (without `https://`) |
| `istio_ingress_sg_id` | `string` | yes | Istio ingress gateway security group |
| `s3_bucket_name` | `string` | yes | Shared S3 bucket name |
| `aws_region` | `string` | yes | AWS region |
| `aws_account_id` | `string` | yes | AWS account ID |

## Outputs

| Name | Description |
|---|---|
| `tenant_subnet_ids` | List of created subnet IDs |
| `tenant_security_group_id` | Security group ID for tenant pods |
| `tenant_iam_role_arn` | IRSA role ARN — annotate the K8s ServiceAccount with this |

## Design decisions

**Why subnets-per-tenant rather than shared subnets?**
Dedicated subnets let us attach a per-tenant security group at the ENI level, which is the strongest network isolation boundary in AWS VPC. Shared subnets would require relying solely on K8s NetworkPolicies, which only filter intra-cluster traffic — not VPC-level traffic from outside the cluster.

**Why IRSA instead of node-level instance profiles?**
Instance profiles give every pod on a node the same IAM identity. IRSA scopes credentials to a specific K8s ServiceAccount, so a compromised pod in `tenant-a` cannot access `tenant-b`'s S3 prefix or secrets, even if both tenants share a node.

**Why is the S3 policy prefix-based rather than bucket-per-tenant?**
Bucket-per-tenant is cleaner but creates operational overhead (separate bucket policies, lifecycle rules, replication configs). Prefix-based isolation with strict `s3:prefix` conditions gives equivalent data separation with lower ops cost for Phase 1. Phase 2 can migrate to separate buckets once tenant count justifies it.
