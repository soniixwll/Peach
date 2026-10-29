# ADR 0007: Manage application infrastructure with Terraform and HCP Terraform

- **Status:** Accepted
- **Date:** 2026-10-29

## Context

Peach originally managed Cognito authentication, weekly reports, and the Nova agenda parser in
three CloudFormation stacks: `peach-auth`, `peach-reports`, and `peach-ai`. Lab 7 requires these
resources to move to Terraform without replacing persistent identities such as the Cognito user
pool and client, reports bucket and queues, Lambda functions, IAM roles, schedule, function URL,
VPC endpoint, or budget.

The backend/database, artifact bucket, frontend/site, and GitHub deployment role remain in their
earlier CloudFormation stacks. Terraform consumes the required backend and artifact-stack outputs
through data sources rather than taking ownership of those resources.

## Decision

The application infrastructure is represented by the root module in `terraform/` and executed in
HCP Terraform organization `ooad-soniixwll`, workspace `Peach`. The workspace uses Terraform
1.17.0, AWS provider 6.70.0, working directory `terraform`, remote state/execution, AWS dynamic
credentials, `us-east-1`, a VCS connection to `main`, and manual apply approval.

Infrastructure changes follow a VCS-driven workflow: branch and pull request, speculative plan,
review, merge to `main`, review of the resulting HCP run, then manual apply. Local commands are
limited to formatting and validation; production state is not managed from a local backend.

## Migration and ownership handoff

Before stack deletion, every resource that had to survive received both `DeletionPolicy: Retain`
and `UpdateReplacePolicy: Retain`. The three stacks were deleted one at a time, with physical IDs
verified after each deletion. Terraform then adopted 35 existing objects through declarative
import blocks. Three non-importable Lambda permissions were intentionally removed with their
stacks and recreated by Terraform.

The migration apply preserved all 35 original physical identities, created only the three expected
permissions, and destroyed or replaced nothing. The old application-stack templates and deployment
scripts are removed so they cannot recreate a second CloudFormation owner. The import blocks remain
as an auditable record of the handoff IDs.

Persistent and identity-critical resources retain `prevent_destroy` where supported and useful.
Provider/API round-trip exceptions use narrowly scoped lifecycle handling; broad drift suppression
is not used.

## Drift management

HCP Terraform is the source of truth for the migrated resources. Console changes are detected with
a plan-only run. After review, drift is reconciled through the normal VCS/HCP apply workflow, then
verified with a clean plan. Operators must stop on an unexpected replacement, destroy, or identity
change rather than applying automatically.

The Lab 7 drift exercise changed only the agenda-parser timeout from 30 to 31 seconds. Terraform
detected one in-place update and restored the declared value of 30 seconds. The subsequent plan was
clean.

## Security

HCP supplies short-lived AWS credentials through workload identity; static AWS access keys are not
stored in the repository or workspace. Google OAuth credentials, notification addresses, and the
deployed JWKS snapshot are HCP workspace variables and remain sensitive in Terraform. Secret
values, local `.env` files, `.tfvars`, state files, crash logs, and provider working directories are
excluded from Git.

## Consequences

- Terraform/HCP owns authentication, reports, and AI infrastructure; CloudFormation must not be
  used to recreate those deleted stacks.
- Existing resource identities and user data are preserved.
- Applies require reviewed HCP runs and explicit confirmation.
- The project retains a mixed-ownership boundary while older backend/site infrastructure remains
  in CloudFormation.
- Developers must obtain Terraform outputs from HCP and keep any local copies in ignored files.
