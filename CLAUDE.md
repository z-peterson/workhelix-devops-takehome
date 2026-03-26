# Workhelix DevOps Take-Home - Interview Session

## Context
This repo contains my take-home submission for the Workhelix Software Engineer (DevOps) role.
Today's interview (Mar 26, 3-5pm CT) has two parts:
1. Take-home review + system design (Ben Labaschin, James Black)
2. Live coding + work style (Tom Marthaler, Jory Pestorious)

## Repo Structure
- `docs/architecture.md` - Full architecture design doc (ECS->EKS migration, multi-tenant isolation)
- `terraform/modules/tenant-isolation/` - Terraform module for per-tenant AWS isolation
- `slides/index.html` - Reveal.js presentation deck (open in browser)
- `README.md` - Overview and usage

## Their Actual Stack (important context)
They use account-per-tenant ECS (not K8s). Django control plane manages Terraform across AWS accounts.
My take-home proposed namespace-per-tenant EKS as a Phase 1 optimization for a small team,
with account-per-tenant on the Phase 2 roadmap. Both approaches are valid.

## Key Tech
- AWS: ECS, EC2, Lambda, S3, SQS, Secrets Manager, multi-account
- IaC: Terraform
- Languages: Python (FastAPI, SQLAlchemy), SQL
- Auth: WorkOS (SSO), Tailscale VPN
- Observability: Prometheus, Grafana, CloudWatch

## During Live Coding
- AI tools explicitly encouraged (Copilot, etc.)
- Expect Python + AWS (boto3) tasks or Terraform debugging
- They provide files, you code in your own environment
- Focus on explaining decisions, not just writing code

## Commit Rules
- NEVER include Co-Authored-By lines or any AI attribution in commit messages
- NEVER reference AI tools by name in any committed file or message
