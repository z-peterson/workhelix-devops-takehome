output "tenant_subnet_ids" {
  description = "Private subnet IDs provisioned for tenant workloads, one per availability zone. Pass these to the EKS node group or Fargate profile that runs tenant pods."
  value       = aws_subnet.tenant_private[*].id
}

output "tenant_security_group_id" {
  description = "Security group ID for tenant pods. When using the Amazon VPC CNI security-groups-for-pods feature, annotate the tenant's Kubernetes ServiceAccount or Pod spec with this SG ID so the CNI applies it to the pod's network interface."
  value       = aws_security_group.tenant.id
}

output "tenant_iam_role_arn" {
  description = "IAM role ARN for IRSA. Annotate the Kubernetes ServiceAccount in the tenant's namespace with this ARN via the tenant-base Helm chart (eks.amazonaws.com/role-arn annotation) so that pods can obtain temporary AWS credentials through the pod identity webhook."
  value       = aws_iam_role.tenant_workload.arn
}
