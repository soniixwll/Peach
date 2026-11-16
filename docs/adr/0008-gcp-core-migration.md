# ADR 0008: Run the Peach core on Google Cloud alongside AWS

- **Status:** Proposed
- **Date:** 2026-11-16

## Context

Peach currently runs its frontend through S3 and CloudFront, its FastAPI API as a Lambda container,
and PostgreSQL on Aurora. Cognito, weekly reports, the Nova agenda parser, mail delivery, and related
jobs also run on AWS. The GCP lab requires a working core deployment without replacing or taking
ownership of the existing AWS deployment.

## Decision

Add a separate Terraform root in `gcp/`, executed by a separate HCP Terraform workspace named
`Peach-GCP` with working directory `gcp`. It uses only the Google provider and its own remote state;
the existing `Peach` workspace, `terraform/` AWS root, and CloudFormation stacks remain unchanged.

Map the core services as follows:

| Existing AWS service | GCP lab service |
| --- | --- |
| Lambda container running FastAPI | Cloud Run running `app.main:app` |
| ECR | Artifact Registry |
| Aurora PostgreSQL | Cloud SQL for PostgreSQL |
| AWS Secrets Manager | Secret Manager |
| S3 and CloudFront static frontend | Firebase Hosting |
| CloudWatch logs and metrics | Cloud Logging and Cloud Monitoring |
| AWS Terraform provider/state | Google provider in separate state |

Use the existing Alembic history to initialize an empty Cloud SQL database. Do not copy Aurora data.
Run migrations through a one-off Cloud Run Job rather than during every API container startup. The
backend keeps its Mangum Lambda adapter, so the existing AWS image and deployment remain supported.

The current Next.js application already supports a static export. Build it with the deployed Cloud
Run URL in `NEXT_PUBLIC_API_URL`, then deploy `frontend/out` to Firebase Hosting. Continue using the
existing Cognito deployment for sign-in during the lab.

Weekly reports, the Bedrock/Nova agenda parser, SES mail delivery, Lambda jobs, Cognito, and all other
non-core features remain on AWS. Migrating them is unnecessary for the required core demonstration
and would increase cost, scope, and cross-cloud security risk.

## Consequences

- Cloud Run can scale to zero, keeping an idle API inexpensive, but the first request may be slower.
- Cloud SQL does not scale to zero and is the primary ongoing cost risk. The lab uses a small zonal
  instance, limited storage, no HA, and an explicit cleanup procedure.
- Firebase Hosting is simple because Peach already produces a static Next.js export. Public API and
  Cognito values must be injected at build time.
- Separate roots, providers, HCP workspaces, and state prevent a GCP plan from managing AWS objects.
- The database password and composed connection URL are sensitive. They are never committed, but
  Terraform must hold them in encrypted HCP state to configure the database user and secret version.
- The public Cloud Run endpoint relies on the application's existing Cognito validation for protected
  routes. CORS is restricted to the Firebase origins.
