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

- [x] BigQuery: public Shakespeare query returned 20 rows, processed 2,650,191 bytes (10 MiB billed
  minimum), job `bqjob_rd3ed3022848c59b_000001a1eb1004ff_1`, result table
  `lab9_demo.shakespeare_top_words`. Evidence: [bigquery-query.png](lab9/evidence/bigquery-query.png)
  (rendered from `bq show -j` job metadata and `bq head` result rows).
- [x] Looker Studio (Data Studio) report connected to `peach-gcp-lab.lab9_demo.shakespeare_top_words`,
  showing the 20-row table and a bar chart; account setup completed and report saved. Evidence:
  [looker-studio.png](lab9/evidence/looker-studio.png).
- [x] Vision OCR (`TEXT_DETECTION`) on Google's public `gs://cloud-samples-data/vision/ocr/sign.jpg`
  sample. Detected text: “WAITING? PLEASE TURN OFF YOUR ENGINE”. Evidence:
  [vision-ocr.png](lab9/evidence/vision-ocr.png) (rendered from `gcloud ml vision detect-text` output).

## Limitations and cleanup

After grading, stop or remove Cloud SQL through the reviewed Terraform cleanup process and remove demo datasets no longer needed. Check
Billing Reports the following day.
