# -----------------------------------------------------------------------------
# Module: tenant-isolation
#
# Provisions the AWS-level isolation boundary for a single tenant on EKS.
#
# What this module handles (AWS resources):
#   - Private subnets (one per AZ) carved from the tenant's allocated CIDR block
#   - Route table associations to attach tenant subnets to the shared private route table
#   - A tenant-scoped security group allowing intra-tenant and Istio ingress traffic
#   - An IAM role for IRSA (IAM Roles for Service Accounts) with a trust policy scoped
#     to the tenant's Kubernetes namespace
#   - An IAM policy granting the role access to the tenant's S3 prefix and Secrets Manager
#     path, with explicit deny-by-default for other tenants' prefixes
#
# What is NOT handled here (managed by the tenant-base Helm chart via Flux):
#   - Kubernetes Namespace
#   - RBAC (Role, RoleBinding, ClusterRoleBinding)
#   - NetworkPolicy (L4 namespace isolation)
#   - Istio resources (Sidecar, AuthorizationPolicy, PeerAuthentication, VirtualService)
#   - ServiceAccount annotation with the IRSA role ARN (output: tenant_iam_role_arn)
#   - ResourceQuota and LimitRange
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Tenant Subnets
# One private subnet per availability zone, carved from var.tenant_cidr_block.
# The /24 is subdivided into /26 blocks (up to 4 AZs); count.index selects the slab.
# Tagged for EKS internal-ELB discovery and cluster association.
# -----------------------------------------------------------------------------
resource "aws_subnet" "tenant_private" {
  count             = length(var.availability_zones)
  vpc_id            = var.vpc_id
  cidr_block        = cidrsubnet(var.tenant_cidr_block, 2, count.index)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name                                        = "${var.tenant_name}-private-${var.availability_zones[count.index]}"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    tenant                                      = var.tenant_name
    environment                                 = var.environment
    managed-by                                  = "terraform"
  }
}

# -----------------------------------------------------------------------------
# Route Table Associations
# Attach each tenant subnet to the shared private route table so that pods
# have outbound Internet access via the NAT gateway and can reach VPC endpoints.
# -----------------------------------------------------------------------------
resource "aws_route_table_association" "tenant_private" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.tenant_private[count.index].id
  route_table_id = var.private_route_table_id
}

# -----------------------------------------------------------------------------
# Tenant Security Group
# Applied to all pods in the tenant namespace via the Amazon VPC CNI
# security-groups-for-pods feature. Two ingress rules:
#   1. Self-referencing (intra-tenant east-west traffic)
#   2. Istio ingress gateway (allows the gateway to reach tenant pods)
# All egress is permitted; outbound filtering is enforced at the NetworkPolicy layer.
# -----------------------------------------------------------------------------
resource "aws_security_group" "tenant" {
  name        = "${var.tenant_name}-${var.environment}-sg"
  description = "Security group for tenant ${var.tenant_name} pods in ${var.environment}"
  vpc_id      = var.vpc_id

  # Allow all intra-tenant traffic (pod-to-pod within the same tenant)
  ingress {
    description = "Intra-tenant east-west traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # Allow traffic from the Istio ingress gateway so it can route to tenant pods
  ingress {
    description     = "Istio ingress gateway to tenant pods"
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [var.istio_ingress_sg_id]
  }

  # Unrestricted egress; cross-tenant egress is blocked at the NetworkPolicy layer
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.tenant_name}-${var.environment}-sg"
    tenant      = var.tenant_name
    environment = var.environment
    managed-by  = "terraform"
  }
}

# -----------------------------------------------------------------------------
# IRSA Trust Policy
# Restricts assumption of the tenant workload role to service accounts that
# live inside the tenant's Kubernetes namespace (system:serviceaccount:<ns>:*).
# The StringLike condition on sub is intentionally broad within the namespace
# so any SA in that namespace can adopt the role; fine-grained SA selection is
# enforced at the Helm chart level via the explicit SA annotation.
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "tenant_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.cluster_oidc_provider_arn]
    }

    condition {
      test     = "StringLike"
      variable = "${var.cluster_oidc_issuer_url}:sub"
      values   = ["system:serviceaccount:${var.tenant_name}:*"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.cluster_oidc_issuer_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# -----------------------------------------------------------------------------
# IAM Role for IRSA
# One role per tenant, assumed by any Kubernetes ServiceAccount in the tenant's
# namespace via OIDC federation. The role ARN is surfaced as an output so the
# tenant-base Helm chart can annotate the ServiceAccount automatically.
# -----------------------------------------------------------------------------
resource "aws_iam_role" "tenant_workload" {
  name               = "${var.tenant_name}-${var.environment}-workload-role"
  assume_role_policy = data.aws_iam_policy_document.tenant_assume_role.json
  description        = "IRSA role for tenant ${var.tenant_name} workloads in ${var.environment}"

  tags = {
    tenant      = var.tenant_name
    environment = var.environment
    managed-by  = "terraform"
  }
}

# -----------------------------------------------------------------------------
# Tenant IAM Policy
# Grants the tenant role least-privilege access to:
#   1. S3 — scoped to the tenant's prefix within the shared bucket. The
#      s3:prefix condition on ListBucket prevents enumeration of other tenants'
#      objects while still allowing the tenant to list its own prefix.
#   2. Secrets Manager — scoped to the tenant's path
#      (<environment>/<tenant_name>/*) so secrets cannot leak across tenants.
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "tenant_workload" {
  # S3 access scoped to the tenant's prefix
  statement {
    sid    = "TenantS3PrefixAccess"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]

    resources = [
      "arn:aws:s3:::${var.s3_bucket_name}/${var.tenant_name}/*",
    ]
  }

  # Allow ListBucket only for the tenant's own prefix
  statement {
    sid    = "TenantS3ListBucket"
    effect = "Allow"

    actions = ["s3:ListBucket"]

    resources = [
      "arn:aws:s3:::${var.s3_bucket_name}",
    ]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${var.tenant_name}/*"]
    }
  }

  # Secrets Manager access scoped to the tenant's path
  statement {
    sid    = "TenantSecretsManagerAccess"
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]

    resources = [
      "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:${var.environment}/${var.tenant_name}/*",
    ]
  }
}

resource "aws_iam_policy" "tenant_workload" {
  name        = "${var.tenant_name}-${var.environment}-workload-policy"
  description = "Least-privilege policy for tenant ${var.tenant_name} in ${var.environment}"
  policy      = data.aws_iam_policy_document.tenant_workload.json

  tags = {
    tenant      = var.tenant_name
    environment = var.environment
    managed-by  = "terraform"
  }
}

# Attach the tenant-scoped policy to the IRSA role
resource "aws_iam_role_policy_attachment" "tenant_workload" {
  role       = aws_iam_role.tenant_workload.name
  policy_arn = aws_iam_policy.tenant_workload.arn
}
