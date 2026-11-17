# Peach Lab 9 submission notes

## Submission links

- GCP Terraform and ADR commit: `69511857f6db1729f009582e58963a235bcf7fb5`
- GCP frontend: <https://peach-gcp-lab.web.app>
- GCP API: <https://peach-lab-api-7sq7lhfuha-lm.a.run.app>
- Database readiness check: <https://peach-lab-api-7sq7lhfuha-lm.a.run.app/api/v1/health/ready>

## Migration summary

Peach keeps its existing AWS deployment and adds an isolated GCP core. Firebase Hosting serves the
Next.js static export, Cloud Run serves FastAPI, Cloud SQL PostgreSQL stores the core data, Artifact
Registry stores the container, and Secret Manager supplies `DATABASE_URL`. A separate `gcp/`
Terraform root and `Peach-GCP` HCP workspace use Google Workload Identity Federation, so there are no
long-lived service-account keys and a GCP plan cannot manage AWS resources.

The database was initialized by running the existing Alembic migrations through Cloud Run Job
`peach-lab-migrate`; revision `0004` completed successfully. The API health endpoint returns HTTP 200
and the readiness endpoint returns HTTP 200 with `database=ok`.

Cognito/Google sign-in, weekly reports, SES mail, and the agenda parser remain on AWS. The GCP API
validates the existing Cognito tokens, and the Firebase callback was added without removing the
existing production callback.

## Validation

- Firebase homepage and a static asset: HTTP 200.
- Cloud Run `/health`: HTTP 200, `status=ok`.
- Cloud Run `/api/v1/health/ready`: HTTP 200, `status=ok`, `database=ok`.
- CORS preflight from `https://peach-gcp-lab.web.app`: HTTP 200 and exact origin allowed.
- Cloud Run scales to zero; Cloud SQL is the main continuing charge.

## Cost result

See [lab9-cost-comparison.md](lab9-cost-comparison.md). Under the documented Lab 4 assumptions, AWS
is cheaper for nobody/class-demo profiles, while GCP is cheaper for office-hours/continuous profiles.
The deciding line is relational database compute.

## Demo evidence checklist

- [x] BigQuery demo executed: the public Shakespeare query returned 20 rows and processed 2,650,191
  bytes (10 MiB billed minimum). Result table: `lab9_demo.shakespeare_top_words`; job:
  `bqjob_rd3ed3022848c59b_000001a1eb1004ff_1`.
- [ ] `docs/lab9/evidence/bigquery-public-query.png` — capture the completed Console query and result.
- [ ] `docs/lab9/evidence/looker-studio-chart.png` — chart over
  `lab9_demo.shakespeare_top_words` (data source is prepared; final account-consent click remains).
- [x] Vision OCR demo executed against Google's public `cloud-samples-data/vision/ocr/sign.jpg`
  sample. Detected text: “WAITING? PLEASE TURN OFF YOUR ENGINE”.
- [ ] `docs/lab9/evidence/vision-ocr.png` — capture the OCR result.
- [ ] Optional: `firebase-peach-home.png` and `cloud-run-readiness.png` for supporting evidence.

## Limitations and cleanup

The three Part 4 demos require Google Cloud console access and are documented only after they are
actually run. Do not claim them complete based on this file alone. After grading, stop or remove Cloud
SQL through the reviewed Terraform cleanup process and remove demo datasets no longer needed. Check
Billing Reports the following day.
