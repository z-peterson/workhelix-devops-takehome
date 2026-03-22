# Workhelix DevOps Take-Home — Zac Peterson

This repo contains my submission for the Workhelix Senior DevOps/Platform Engineer role. It covers two parts: a multi-tenant EKS architecture design doc and a Terraform module that provisions the AWS-side infrastructure for each tenant.

---

## Part 1: Architecture Design

[docs/architecture.md](docs/architecture.md)

Namespace-per-tenant isolation on a shared EKS cluster, with account-per-tenant on the roadmap for customers requiring hard infra boundaries. Istio handles traffic isolation and mTLS; Flux manages in-cluster state via GitOps.

---

## Part 2: Terraform Module — tenant-isolation

[terraform/modules/tenant-isolation/](terraform/modules/tenant-isolation/)

**What it provisions:**

- Private subnets (one per AZ) with route table associations
- Tenant-scoped security group with ingress restricted to the Istio ingress gateway
- IRSA IAM role and policy scoped to the tenant's S3 prefix and KMS key

**What it does NOT provision:**

In-cluster Kubernetes resources (namespace, RBAC, NetworkPolicy, ResourceQuota, Istio VirtualService/AuthorizationPolicy) are out of scope for this module. Those are managed by the `tenant-base` Helm chart, reconciled by Flux. The module outputs `tenant_iam_role_arn` and `tenant_subnet_ids`, which are passed as Helm values so the chart can annotate the Kubernetes ServiceAccount correctly.

This boundary is intentional. Terraform managing K8s resources via the Kubernetes provider creates circular dependencies and drift when the cluster is also managed by Terraform. Keeping cloud infra in Terraform and K8s config in Flux+Helm gives each tool a clean ownership domain.

### Usage

```hcl
module "tenant_acme" {
  source = "./modules/tenant-isolation"

  tenant_name               = "acme"
  environment               = "prod"
  vpc_id                    = "vpc-0abc123"
  availability_zones        = ["us-east-1a", "us-east-1b", "us-east-1c"]
  tenant_cidr_block         = "10.1.4.0/24"
  private_route_table_id    = "rtb-0def456"
  cluster_name              = "workhelix-prod"
  cluster_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
  cluster_oidc_issuer_url   = "oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
  istio_ingress_sg_id       = "sg-0ghi789"
  s3_bucket_name            = "workhelix-prod-tenant-data"
  aws_region                = "us-east-1"
  aws_account_id            = "123456789012"
}
```

### Key Assumptions

- EKS cluster and VPC are pre-provisioned. This module is called from a parent root module.
- Istio ingress gateway is installed cluster-wide before any tenant is onboarded.
- GitOps flow: GitHub Actions builds and tags images, Flux detects config repo changes, rolls out to cluster. No `kubectl` in CI.

---

## Bonus: Slide Deck

Open [slides/index.html](slides/index.html) in any browser for the full presentation deck.

---

Zac Peterson | zac@zacp.xyz
