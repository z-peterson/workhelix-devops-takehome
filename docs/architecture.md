# Workhelix Platform Architecture
## ECS to EKS Migration + Multi-Tenant Enterprise Infrastructure

**Author:** Zac Peterson
**Date:** March 2026

---

## Background

This doc covers the architecture decisions for Workhelix's infrastructure evolution: migrating from ECS Fargate to EKS, building multi-tenant isolation, and laying the foundation for enterprise customers. The goal is to do this without overwhelming a 7-person team or burning budget on over-engineered solutions you won't need for 12 months.

---

## 1. Multi-Tenancy Strategy

The question with multi-tenancy is always the same: namespace-per-tenant on a shared cluster, or account-per-tenant? Both are valid. The answer depends on your team size, compliance posture, and how many tenants you're actually running.

Right now, with 10-20 enterprise customers on the horizon and a small ops team, **namespace-per-tenant on shared EKS** is the right call. Here's why:

- Account-per-tenant means a separate EKS cluster per customer. That's manageable at 5 customers. At 15, you're maintaining 15 clusters, 15 VPCs, 15 sets of Terraform state. For a 7-person team, that's a full-time job before you've written a line of product code.
- Namespace isolation with RBAC, NetworkPolicies, ResourceQuotas, and LimitRanges gets you strong logical boundaries at a fraction of the operational cost.
- Istio AuthorizationPolicy with `STRICT` mTLS per namespace adds a cryptographic enforcement layer on top of Kubernetes network controls.

The tradeoff is real: noisy neighbor risk and shared control plane. For customers with hard HIPAA or SOC2 Type II requirements that mandate infrastructure-level isolation, this won't cut it forever.

**Phase 2 roadmap:** When you have enterprise customers requiring hard compliance boundaries, move them to dedicated accounts via AWS Organizations + Control Tower. The infrastructure code is modular enough that you're not rewriting anything - you're adding an account vending machine on top.

I ran this exact pattern at BP on the "Bifrost" platform - more on that below. Namespace-per-environment across hundreds of data scientists, same Helm chart, environment-specific Kustomize overlays. It worked until it needed to work differently, and the migration path was clear.

---

## 2. EKS Cluster Design

(see Architecture Overview diagram)

### Node Groups

Three node groups covering different workload profiles:

| Group | Instance Type | Workloads |
|-------|--------------|-----------|
| System + Stateful | m6a.xlarge, on-demand | Control plane add-ons, any stateful services, PVC consumers |
| Stateless / Batch | Mixed instance policy (m6a, m5a, c6a), Spot | API pods, workers, anything horizontally scalable |
| Graviton ARM64 | m7g, c7g, Spot | Cost-optimized stateless workloads (20-30% cheaper than x86) |

Autoscaling via **Karpenter** rather than Cluster Autoscaler. Karpenter provisions nodes in under 30 seconds vs. 2-3 minutes with CA, and it bin-packs more aggressively - less idle capacity sitting around.

### Networking

- 3 AZs, private subnets for nodes, public subnets for load balancers only
- AWS VPC CNI for pod networking (native ENI IPs, no overlay overhead)
- ALB (TLS termination at edge) -> Istio Ingress Gateway -> Envoy sidecars
- Per-tenant ingress routing: `customer-a.workhelix.io` hits the ALB, routes through a VirtualService scoped to that tenant's namespace

### Service Mesh (Istio)

Istio runs across the full cluster. Key configs:

- `PeerAuthentication STRICT` per tenant namespace - mTLS enforced, no plaintext service-to-service traffic
- `AuthorizationPolicy` - services in tenant-a namespace cannot reach services in tenant-b namespace, period
- `VirtualService` + `DestinationRule` for canary deployments (weight-based traffic splitting), retries, circuit breaking
- Kiali for mesh visualization, Jaeger for distributed tracing

This is the same mesh topology I used at BP to enforce data isolation between competing research teams sharing the same cluster. Without mesh-layer enforcement, NetworkPolicies alone can be worked around by a misconfigured service. Istio gives you defense in depth.

### Security

- **IRSA** (IAM Roles for Service Accounts) for all pod-level AWS access - no instance profiles, no shared credentials
- **Kyverno** for policy enforcement: required labels, registry allowlists, no `latest` tags, resource request requirements
- **Pod Security Standards** (restricted profile) enforced at namespace level
- **Secrets Manager** + External Secrets Operator for secret injection - nothing sensitive in etcd

### GitOps

**Flux** watches GitHub. The flow:

1. CI builds image, pushes to ECR, updates image tag in config repo
2. Flux detects config repo change, reconciles HelmRelease
3. Pods roll out - no kubectl in CI, no human touching the cluster for deployments

New tenant onboarding = add a `HelmRelease` + Kustomize overlay to the config repo, commit, push. Flux deploys it. The whole thing takes about 10 minutes and zero manual steps.

### Queue-Based Autoscaling

**KEDA** with SQS triggers handles workload-driven scaling. When an SQS queue depth crosses a threshold, KEDA scales the consumer deployment. Karpenter picks up the pending pods and provisions nodes. This is particularly useful for Workhelix's async processing workloads - you scale to zero when there's no work and handle bursts without over-provisioning.

---

## 3. ECS to EKS Migration Strategy

Stateless services first, stateful services second, RDS stays where it is until you have a reason to move it (which you probably don't).

**Approach per service:**

1. Containerize for EKS (same Docker image, Kubernetes manifests added)
2. Deploy to EKS in parallel with the running ECS service
3. Shift traffic using weighted target groups on the ALB: start at 5% EKS, watch error rates and latency
4. Ramp to 50% -> 100% over 48 hours if metrics look good
5. Keep ECS task definitions live and deployable until 48-hour soak at 100% completes

**Rollback** at any step is just updating the ALB weights back to ECS. No database migrations until the service is fully migrated and stable.

The biggest risk in any ECS-to-EKS migration is service discovery. ECS uses CloudMap/DNS internally; in Kubernetes, services talk to each other via in-cluster DNS. During the transition window where some services are in ECS and some are in EKS, you need a clear communication path. An API gateway or ALB-fronted internal load balancer handles cross-boundary traffic for the transition period.

Don't migrate the data tier until the application tier is clean. RDS stays in its current VPC, accessible from both ECS and EKS during migration via security group rules and VPC peering if needed.

---

## 4. Four-Week Prioritization Plan

### Week 1: Foundation
- EKS cluster + VPC via Terraform (cluster, node groups, IAM, ECR, security groups)
- Flux bootstrapped against GitHub config repo
- Core namespaces: `platform-system`, `monitoring`, `istio-system`
- IRSA roles for all AWS service access
- External Secrets Operator pointed at Secrets Manager

**Deliverable:** A clean, empty cluster that deploys configs from Git automatically.

### Week 2: Tenant Isolation + Mesh
- Istio installed and configured (mTLS STRICT, Ingress Gateway)
- Terraform module for tenant namespace provisioning (RBAC, NetworkPolicies, ResourceQuotas, LimitRanges, Istio configs)
- First tenant namespace provisioned end-to-end using the module
- Kyverno policies deployed (admission control, registry enforcement)

**Deliverable:** Onboard a test tenant in under 15 minutes from a single Terraform variable block.

### Week 3: Service Migration + Observability
- Migrate 2-3 stateless services from ECS to EKS using the blue-green traffic split approach
- ALB routing fully functional, HTTPS with ACM certs
- Prometheus + Grafana deployed (kube-state-metrics, node-exporter, Istio metrics)
- KEDA deployed with SQS scaler for at least one worker queue
- Alerts: pod crash loops, HPA max replicas, node disk pressure

**Deliverable:** Real traffic running through EKS for migrated services, metrics visible in Grafana.

### Week 4: Hardening + Runbooks
- Karpenter tuning (consolidation policies, disruption budgets)
- Tenant onboarding runbook - step by step, tested end-to-end by someone not on the infra team
- ECS decommission plan with rollback criteria clearly documented
- Load test the multi-tenant setup at projected peak (simulate N tenants, verify NetworkPolicies hold, ResourceQuotas prevent noisy neighbor impact)
- DR runbook: what happens if a node group goes down, if a namespace gets corrupted, if Flux loses sync

**Deliverable:** Documentation and runbooks a new hire can follow. ECS retirement plan with dates.

---

## Prior Art: BP Bifrost

The multi-tenant namespace model here isn't theoretical. At BP in 2024, I built a hybrid platform called Bifrost as the sole DevOps engineer on the project. The situation: data scientists across competing research teams were self-managing unmanaged Windows VMs, running overnight training jobs on always-on compute, no corporate identity, no cost controls, no visibility. Azure costs were climbing with no accountability.

I built both sides of the platform. On Azure: a VM provisioning pipeline that enrolled machines into Entra ID automatically, mounted Azure Storage shares per team, and brought every data scientist under corporate identity for the first time. On GCP: a Kubernetes cluster with a custom controller that watched job queue depth and scaled GPU spot node pools up and down automatically - nodes at zero when idle, spun up in under two minutes when a job queued.

The K8s side used the same patterns described here: namespace-per-team with Kustomize overlays on a shared Helm chart, Istio mesh for inter-team service isolation (these teams could not share data), Flux + GitLab for GitOps. No kubectl in CI, no manual deployments, all state in Git.

The result was a 40% reduction in Azure compute costs (eliminated always-on VMs), and data scientists went from one overnight training run per day to multiple iterations. The platform hit 99.9% uptime over its production lifecycle.

That's the model I'm proposing for Workhelix - proven at a larger scale, right-sized for where you are now, with clear phase 2 paths as customer requirements get more demanding.

---

## Tech Stack Summary

| Layer | Technology |
|-------|-----------|
| Cloud | AWS (EKS, ECR, ALB, S3, SQS, Secrets Manager, Route53) |
| IaC | Terraform (cloud infra), Helm + Kustomize (in-cluster) |
| GitOps | Flux v2 + GitHub |
| Service Mesh | Istio (mTLS, traffic management, observability) |
| Policy | Kyverno (admission control), Pod Security Standards |
| Autoscaling | Karpenter (nodes), KEDA (workloads), HPA (pods) |
| Observability | Prometheus, Grafana, Jaeger, Kiali, CloudWatch |
| Secrets | AWS Secrets Manager + External Secrets Operator |
