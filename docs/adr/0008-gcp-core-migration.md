# ADR 0008: Run the Peach core on Google Cloud alongside AWS

- **Status:** Accepted
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

Map the AWS services as follows. “Keep” means the service remains on AWS during this lab; “drop”
means the feature is outside the migrated core.

| Existing AWS service | Decision | GCP lab service / reason |
| --- | --- | --- |
| S3 + CloudFront + WAF static frontend | Replace for GCP core | Firebase Hosting includes CDN, TLS, and a free lab-sized quota. |
| Lambda container running FastAPI | Replace for GCP core | Cloud Run runs the ASGI container on `PORT` and scales to zero. |
| ECR | Replace for GCP core | Artifact Registry stores the Cloud Run image. |
| Aurora PostgreSQL | Replace for GCP core | Cloud SQL PostgreSQL preserves SQLAlchemy, relations, and Alembic with minimal code change. |
| DynamoDB alternative | Drop | Firestore would be cheaper when idle but requires a data-model and repository rewrite. |
| Cognito user pool + Google | Keep | Existing Cognito tokens work on both APIs; Identity Platform is optional stretch work. |
| EventBridge Scheduler | Keep | Weekly reports are not part of the migrated core; Cloud Scheduler is the future counterpart. |
| SQS | Keep | Existing report/event flows stay on AWS; Pub/Sub or Cloud Tasks would be the future counterpart. |
| S3 events + Lambda | Keep | Agenda/report non-core flows stay on AWS; Cloud Storage + Eventarc is the counterpart. |
| SES | Keep | GCP has no direct transactional-mail equivalent and retaining SES avoids a provider migration. |
| Bedrock/Nova | Keep | Agenda parsing is a stretch goal; Vertex AI is the evaluated counterpart. |
| SSM Parameter Store / Secrets Manager | Replace for GCP core | Secret Manager stores `DATABASE_URL`; AWS secrets remain intact for AWS. |
| CloudWatch Logs | Replace for GCP core | Cloud Run writes to Cloud Logging automatically. |
| IAM roles | Replace for GCP resources | Dedicated service accounts and least-privilege IAM roles; no JSON keys. |
| Terraform AWS provider/state | Add alongside | Google providers in an isolated `Peach-GCP` HCP workspace and state. |

Use the existing Alembic history to initialize an empty Cloud SQL database. Do not copy Aurora data.
Run migrations through a one-off Cloud Run Job rather than during every API container startup. The
backend keeps its Mangum Lambda adapter, so the existing AWS image and deployment remain supported.

The current Next.js application already supports a static export. Build it with the deployed Cloud
Run URL in `NEXT_PUBLIC_API_URL`, then deploy `frontend/out` to Firebase Hosting. Continue using the
existing Cognito deployment for sign-in during the lab.

Weekly reports, the Bedrock/Nova agenda parser, SES mail delivery, Lambda jobs, Cognito, and all other
non-core features remain on AWS. Migrating them is unnecessary for the required core demonstration
and would increase cost, scope, and cross-cloud security risk.

Cloud SQL was chosen instead of Firestore or a cross-cloud Aurora connection. It keeps application
code and migrations portable and avoids cross-cloud latency and egress, at the cost of continuous
instance billing. The instance can be stopped between demonstrations, but storage continues to bill.
Keeping Aurora would minimize data migration but couple every GCP API request to AWS networking and
availability. Firestore would scale to zero but requires rewriting relational queries and migrations.

E-mail remains on SES. No new API key is needed; if a later migration chooses SendGrid or Mailgun,
its key belongs in Secret Manager and is granted only to the runtime service account.

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
