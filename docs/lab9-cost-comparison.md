# Lab 9: Peach AWS vs GCP monthly cost comparison

## Assumptions

- Prices are on-demand USD estimates, excluding tax, for 730 hours/month.
- AWS is `us-east-1`; GCP is the deployed `europe-central2` project.
- The four profiles are the Lab 4 profiles: nobody (0 active hours), class demos (10 × 2 h = 20 h),
  office hours (8 h × 22 days = 176 h), and busy around the clock (730 h).
- The static frontend, low-volume API requests, registry image, secrets, and logs remain inside the
  applicable free quotas. Cloud Run has `min_instance_count = 0`.
- AWS Aurora Serverless v2 is estimated at the Lab 4 rate of `$0.12/ACU-hour`, using 1 ACU while
  awake, plus 1 GB storage at `$0.10/month`.
- The deployed GCP database is zonal `db-f1-micro`, 10 GB HDD. The Moodle reference rate is
  `$0.0105/hour`; HDD storage is `$0.09/GB-month`. It is assumed to remain running for the whole
  month in every traffic profile. Calculator totals can vary slightly with region/currency updates.
- Network egress is assumed negligible for this student demo.

## Core service table

| Piece | AWS Peach | GCP Peach |
| --- | ---: | ---: |
| Frontend + CDN + HTTPS | CloudFront free plan: $0.00 | Firebase Hosting free quota: $0.00 |
| API compute | Lambda free quota at these profiles: $0.00 | Cloud Run free quota at these profiles: $0.00 |
| Database compute | Aurora: `$0.12 × awake hours` | Cloud SQL: `$0.0105 × 730 = $7.67` |
| Database storage | 1 GB: $0.10 | 10 GB HDD: $0.90 |
| Registry, secrets, basic logs | Approx. $0.20 | Within free quotas: $0.00 |

## Four traffic profiles

| Profile | Active DB hours | AWS estimate | GCP estimate | Cheaper cloud | Deciding line |
| --- | ---: | ---: | ---: | --- | --- |
| Nobody | 0 | **$0.30** | **$8.57** | AWS | Cloud SQL runs while idle; Aurora pauses. |
| Class demos | 20 | **$2.70** | **$8.57** | AWS | Aurora compute is only `$2.40`; Cloud SQL is month-long. |
| Office hours | 176 | **$21.42** | **$8.57** | GCP | Aurora awake ACU-hours overtake fixed Cloud SQL. |
| Busy around the clock | 730 | **$87.90** | **$8.57** | GCP | Aurora Serverless compute dominates at continuous use. |

The break-even point under these assumptions is about 69 awake Aurora hours per month:
`$0.30 + $0.12h = $8.57`.

## Conclusions

- AWS is cheaper when the relational database can genuinely pause for most of the month.
- GCP is cheaper once the database is awake regularly because the small Cloud SQL tier has a lower
  fixed monthly compute estimate than 1 ACU of continuous Aurora Serverless v2.
- The GCP equivalent of the Lab 4 trap is leaving Cloud SQL running when nobody uses it. Unlike
  Aurora, it never auto-pauses. Stopping it removes compute but not storage charges.
- Firestore could make idle GCP cost approximately zero, but Peach would give up relational schemas,
  joins, foreign keys, and its existing Alembic/SQLAlchemy data layer.

## Pricing evidence

- Moodle Lab 9 reference table, checked 5 November 2026.
- Google Cloud SQL pricing: <https://cloud.google.com/sql/pricing>
- Google Cloud Run pricing: <https://cloud.google.com/run/pricing>
- Firebase pricing: <https://firebase.google.com/pricing>
- AWS Aurora pricing: <https://aws.amazon.com/rds/aurora/pricing/>
