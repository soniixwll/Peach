# Peach GCP lab infrastructure

This Terraform root creates the GCP copy of Peach's core: Artifact Registry, a small Cloud SQL for
PostgreSQL instance, Secret Manager, Cloud Run, and a Firebase Hosting site. It deliberately contains
no AWS provider, resources, data sources, or remote-state references.

## State and HCP Terraform

Use a new HCP Terraform workspace named `Peach-GCP`:

- organization: `ooad-soniixwll`
- execution mode: remote
- working directory: `gcp`
- Terraform version: `1.17.0`
- VCS branch: `main`, with speculative PR plans and manual apply approval
- state sharing: disabled unless a later, reviewed requirement needs it

Never point the existing `Peach` AWS workspace at this directory, never point `Peach-GCP` at
`terraform/`, and never attach the AWS variable set to `Peach-GCP`. HCP's workspace supplies the
remote backend during remote execution, so this root intentionally has no local `backend` or `cloud`
block. Do not run a local apply.

Configure HCP dynamic GCP credentials with Workload Identity Federation; do not create a JSON service
account key. Bootstrap IAM is a manual, separately reviewed action. For service-account
impersonation, configure these HCP **environment variables**:

- `TFC_GCP_PROVIDER_AUTH=true`
- `TFC_GCP_PRINCIPAL_TYPE=service_account`
- `TFC_GCP_RUN_SERVICE_ACCOUNT_EMAIL=peach-hcp-terraform@peach-gcp-lab.iam.gserviceaccount.com`
- `TFC_GCP_WORKLOAD_PROVIDER_NAME=projects/163608943214/locations/global/workloadIdentityPools/POOL_ID/providers/PROVIDER_ID`

Use the unified provider-name variable rather than also setting the separate project-number, pool-ID,
and provider-ID variables. Do not configure `GOOGLE_CREDENTIALS` or `GOOGLE_APPLICATION_CREDENTIALS`;
they conflict with HCP dynamic credentials. Restrict the GCP provider condition and service-account
impersonation binding to HCP organization `ooad-soniixwll` and workspace `Peach-GCP`.

Set these HCP Terraform variables:

- `project_id = peach-gcp-lab`
- `region = europe-central2`
- `terraform_service_account_email = peach-hcp-terraform@peach-gcp-lab.iam.gserviceaccount.com`
- `db_password` as sensitive, using a random value of at least 24 characters
- `cognito_issuer` and `cognito_client_id` from the existing AWS deployment
- `cognito_jwks_json` as sensitive
- `cors_origins` to the exact Firebase/custom-domain origins

The password and generated SQL connection URL are stored in encrypted HCP state because Terraform
configures both the PostgreSQL user and Secret Manager version. They are never written to Git.

## APIs

Core APIs are declared in `apis.tf` and are enabled only by a future approved apply:

- Service Usage and Cloud Resource Manager: project service management
- IAM, IAM Credentials, and Security Token Service: identities and keyless HCP federation
- Artifact Registry: backend image storage
- Cloud Run: API service and migration job
- Cloud SQL Admin: PostgreSQL instance and Cloud Run attachment
- Secret Manager: database connection secret
- Firebase Management and Firebase Hosting: static frontend site

BigQuery, Vision, and Document AI are declared behind `enable_demo_apis = false`. Enable them only for
the later evidence/demo phase. No Cloud Build API is needed because the documented workflow builds
the image locally or in existing CI.

## Deployed architecture and safe staged deployment

The lab deployment is live in `peach-gcp-lab` (`europe-central2`):

- frontend: <https://peach-gcp-lab.web.app>
- API: <https://peach-lab-api-7sq7lhfuha-lm.a.run.app>
- Cloud SQL: `peach-lab-postgres`
- Artifact Registry repository: `peach-backend`
- migration job: `peach-lab-migrate` (Alembic revision `0004` applied)

The core moved to GCP. Cognito/Google sign-in, weekly reports, SES delivery, and the agenda parser
remain on AWS. The API accepts the existing Cognito tokens, so both deployments continue to work.

`deploy_cloud_run` defaults to `false`. The first reviewed apply creates the APIs, repository,
database, secret, runtime identity, and Firebase site, but not Cloud Run: an empty Artifact Registry
cannot satisfy a Cloud Run image reference.

After that apply, the future image workflow is:

```sh
gcloud auth configure-docker europe-central2-docker.pkg.dev
docker build --target runtime -t peach-backend:gcp ./backend
docker tag peach-backend:gcp europe-central2-docker.pkg.dev/peach-gcp-lab/peach-backend/peach-backend:gcp-lab
docker push europe-central2-docker.pkg.dev/peach-gcp-lab/peach-backend/peach-backend:gcp-lab
```

These commands are documentation only. Authentication and `docker push` change external state and
require an explicit checkpoint. Prefer an immutable tag or digest for the final deployment.

Once the image exists, set `deploy_cloud_run = true`, review a new HCP plan, and apply only after
approval. Then execute the migration job exactly once:

```sh
gcloud run jobs execute peach-lab-migrate --region europe-central2 --wait
```

The existing migrations create an empty compatible schema. Do not `pg_dump` Aurora for this lab.

## Firebase build and deployment

The AWS frontend path remains unchanged. For Firebase, build the existing static export only after the
Cloud Run URL is known:

```sh
cd frontend
NEXT_OUTPUT=export \
NEXT_PUBLIC_API_URL="https://CLOUD_RUN_URL" \
NEXT_PUBLIC_APP_URL="https://peach-gcp-lab.web.app" \
NEXT_PUBLIC_COGNITO_REGION="us-east-1" \
NEXT_PUBLIC_COGNITO_USER_POOL_ID="POOL_ID" \
NEXT_PUBLIC_COGNITO_CLIENT_ID="CLIENT_ID" \
NEXT_PUBLIC_COGNITO_DOMAIN="https://COGNITO_DOMAIN" \
NEXT_PUBLIC_AGENDA_PARSER_URL="https://EXISTING_AWS_PARSER_URL" \
pnpm build
cd ../gcp
firebase deploy --only hosting --project peach-gcp-lab
```

Firebase CLI 15 does not allow a `public` directory outside the directory containing
`firebase.json`. The Hosting `predeploy` hook therefore copies the already-built `frontend/out`
into the ignored `gcp/.firebase-hosting/` staging directory. No generated frontend output is tracked.
`firebase.json` enables clean URLs for exported routes and gives immutable Next.js assets long cache
lifetimes. Firebase deployment and Cognito callback/logout changes require separate approval.

To validate the staging step without deploying:

```sh
cd gcp
./scripts/stage-firebase-hosting.sh
test -f .firebase-hosting/index.html
```

To stop database compute charges without destroying the lab, stop `peach-lab-postgres` in Cloud SQL.
Storage and retained backups still incur charges while stopped. Restart it before demonstrating the
database-backed API. Permanent cleanup remains the reviewed two-step Terraform process below.

## Cost and cleanup

Cloud SQL is the main continuous cost: it does not scale to zero. This lab uses a zonal
`db-f1-micro`, 10 GB HDD, one retained backup, no HA, and no storage auto-growth. Cloud Run has zero
minimum instances and a maximum of two. Artifact Registry, Secret Manager, Firebase bandwidth, logs,
and later demo APIs can also incur usage charges.

Cloud SQL deletion protection is enabled. Cleanup is intentionally two-step: first change
`deletion_protection` to `false` in a reviewed apply, then approve a separate destroy. API resources
use `disable_on_destroy = false`, so cleanup does not disable shared project APIs automatically.

## Local checks

Formatting is offline:

```sh
terraform -chdir=gcp fmt -check -recursive
```

Provider-aware validation requires a local provider download. Use only an isolated temporary plugin
initialization or the HCP speculative plan; never initialize this directory against the AWS workspace
and never run `terraform apply` locally.
