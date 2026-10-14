#!/usr/bin/env bash
# Package the mailer, discover the deployed backend's network/image/database
# configuration, and create or update the reports stack. The schedule defaults
# to DISABLED and must be enabled explicitly after manual end-to-end testing.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT}/.env"
REPORTS_TEMPLATE="${ROOT}/infra/reports.yml"
ARTIFACTS_TEMPLATE="${ROOT}/infra/artifacts.yml"

log() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m==>\033[0m %s\n' "$*" >&2; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

if [[ -f "${ENV_FILE}" ]]; then
  preset="$(export -p)"
  set -a
  # shellcheck disable=SC1091
  source "${ENV_FILE}"
  set +a
  eval "${preset}"
fi

for var in AWS_PROFILE AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN; do
  [[ -n "${!var:-}" ]] || unset "${var}"
done

PROJECT_NAME="${PROJECT_NAME:-peach}"
BACKEND_STACK_NAME="${BACKEND_STACK_NAME:-${PROJECT_NAME}-backend}"
REPORTS_STACK_NAME="${REPORTS_STACK_NAME:-${PROJECT_NAME}-reports}"
ARTIFACTS_STACK_NAME="${ARTIFACTS_STACK_NAME:-${PROJECT_NAME}-artifacts}"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
REPORT_SENDER_EMAIL="${REPORT_SENDER_EMAIL:-reports@sofia-peach.pp.ua}"
REPORT_RECIPIENT_EMAIL="${REPORT_RECIPIENT_EMAIL:-}"
REPORTS_SCHEDULE_STATE="${REPORTS_SCHEDULE_STATE:-DISABLED}"
export AWS_DEFAULT_REGION="${AWS_REGION}"

for tool in aws python3; do
  command -v "${tool}" >/dev/null 2>&1 || die "${tool} is required but not installed"
done
aws sts get-caller-identity >/dev/null 2>&1 || die "no usable AWS credentials"
[[ "${AWS_REGION}" == "us-east-1" ]] || die "reports must be deployed in us-east-1"
[[ -n "${REPORT_RECIPIENT_EMAIL}" ]] \
  || die "REPORT_RECIPIENT_EMAIL must be explicitly provided and SES-verified"
[[ "${REPORTS_SCHEDULE_STATE}" == "DISABLED" || "${REPORTS_SCHEDULE_STATE}" == "ENABLED" ]] \
  || die "REPORTS_SCHEDULE_STATE must be DISABLED or ENABLED"

aws cloudformation describe-stacks --stack-name "${BACKEND_STACK_NAME}" >/dev/null 2>&1 \
  || die "backend stack ${BACKEND_STACK_NAME} does not exist"

backend_output() {
  aws cloudformation describe-stacks --stack-name "${BACKEND_STACK_NAME}" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}

BACKEND_FUNCTION="$(backend_output FunctionName)"
DATABASE_SECRET_ARN="$(backend_output DatabaseUrlSecretArn)"
[[ -n "${BACKEND_FUNCTION}" && "${BACKEND_FUNCTION}" != "None" ]] \
  || die "backend stack has no FunctionName output"
[[ -n "${DATABASE_SECRET_ARN}" && "${DATABASE_SECRET_ARN}" != "None" ]] \
  || die "backend stack has no DatabaseUrlSecretArn output"

BACKEND_IMAGE_URI="$(aws lambda get-function --function-name "${BACKEND_FUNCTION}" \
  --query Code.ImageUri --output text)"
ARCHITECTURE="$(aws lambda get-function-configuration --function-name "${BACKEND_FUNCTION}" \
  --query 'Architectures[0]' --output text)"
VPC_ID="$(aws lambda get-function-configuration --function-name "${BACKEND_FUNCTION}" \
  --query 'VpcConfig.VpcId' --output text)"
SUBNET_IDS="$(aws lambda get-function-configuration --function-name "${BACKEND_FUNCTION}" \
  --query 'join(`,`,VpcConfig.SubnetIds)' --output text)"
FUNCTION_SECURITY_GROUP_ID="$(aws lambda get-function-configuration \
  --function-name "${BACKEND_FUNCTION}" \
  --query 'VpcConfig.SecurityGroupIds[0]' --output text)"
[[ -n "${BACKEND_IMAGE_URI}" && "${BACKEND_IMAGE_URI}" != "None" ]] \
  || die "backend function has no container image URI"
[[ -n "${VPC_ID}" && "${VPC_ID}" != "None" && -n "${SUBNET_IDS}" ]] \
  || die "backend function is not configured in a VPC"
[[ -n "${FUNCTION_SECURITY_GROUP_ID}" && "${FUNCTION_SECURITY_GROUP_ID}" != "None" ]] \
  || die "backend function has no security group"

ROUTE_TABLE_IDS="$(VPC_ID="${VPC_ID}" SUBNET_IDS="${SUBNET_IDS}" python3 - <<'PY'
import json
import os
import subprocess

vpc_id = os.environ["VPC_ID"]
subnets = os.environ["SUBNET_IDS"].split(",")
document = json.loads(subprocess.check_output([
    "aws", "ec2", "describe-route-tables",
    "--filters", f"Name=vpc-id,Values={vpc_id}",
    "--output", "json",
]))
main = None
explicit = {}
for table in document["RouteTables"]:
    for association in table.get("Associations", []):
        if association.get("Main"):
            main = table["RouteTableId"]
        if association.get("SubnetId"):
            explicit[association["SubnetId"]] = table["RouteTableId"]
if main is None and any(subnet not in explicit for subnet in subnets):
    raise SystemExit("could not determine the VPC main route table")
print(",".join(sorted({explicit.get(subnet, main) for subnet in subnets})))
PY
)"
[[ -n "${ROUTE_TABLE_IDS}" ]] || die "could not determine effective route tables"

log "packaging report mailer"
MAILER_ZIP="$("${ROOT}/scripts/package-report-mailer.sh")"
MAILER_HASH="$(python3 - "${MAILER_ZIP}" <<'PY'
import hashlib
import pathlib
import sys

print(hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest())
PY
)"

log "creating or updating private artifact storage"
aws cloudformation deploy \
  --stack-name "${ARTIFACTS_STACK_NAME}" \
  --template-file "${ARTIFACTS_TEMPLATE}" \
  --parameter-overrides "ProjectName=${PROJECT_NAME}" \
  --no-fail-on-empty-changeset \
  --tags "PROJECT_NAME=${PROJECT_NAME}"
ARTIFACTS_BUCKET="$(aws cloudformation describe-stacks --stack-name "${ARTIFACTS_STACK_NAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='ArtifactsBucketName'].OutputValue" --output text)"
MAILER_KEY="report-mailer/${MAILER_HASH}.zip"
log "uploading versioned report-mailer artifact"
aws s3 cp "${MAILER_ZIP}" "s3://${ARTIFACTS_BUCKET}/${MAILER_KEY}" \
  --only-show-errors

PARAMS_FILE="$(mktemp)"
chmod 600 "${PARAMS_FILE}"
trap 'rm -f "${PARAMS_FILE}"' EXIT

PROJECT_NAME="${PROJECT_NAME}" \
VPC_ID="${VPC_ID}" \
ROUTE_TABLE_IDS="${ROUTE_TABLE_IDS}" \
SUBNET_IDS="${SUBNET_IDS}" \
FUNCTION_SECURITY_GROUP_ID="${FUNCTION_SECURITY_GROUP_ID}" \
BACKEND_IMAGE_URI="${BACKEND_IMAGE_URI}" \
ARCHITECTURE="${ARCHITECTURE}" \
DATABASE_SECRET_ARN="${DATABASE_SECRET_ARN}" \
ARTIFACTS_BUCKET="${ARTIFACTS_BUCKET}" \
MAILER_KEY="${MAILER_KEY}" \
REPORT_SENDER_EMAIL="${REPORT_SENDER_EMAIL}" \
REPORT_RECIPIENT_EMAIL="${REPORT_RECIPIENT_EMAIL}" \
REPORTS_SCHEDULE_STATE="${REPORTS_SCHEDULE_STATE}" \
python3 - "${PARAMS_FILE}" <<'PY'
import json
import os
import sys

values = {
    "ProjectName": os.environ["PROJECT_NAME"],
    "VpcId": os.environ["VPC_ID"],
    "RouteTableIds": os.environ["ROUTE_TABLE_IDS"],
    "SubnetIds": os.environ["SUBNET_IDS"],
    "FunctionSecurityGroupId": os.environ["FUNCTION_SECURITY_GROUP_ID"],
    "BackendImageUri": os.environ["BACKEND_IMAGE_URI"],
    "Architecture": os.environ["ARCHITECTURE"],
    "DatabaseUrlSecretArn": os.environ["DATABASE_SECRET_ARN"],
    "ReportMailerCodeS3Bucket": os.environ["ARTIFACTS_BUCKET"],
    "ReportMailerCodeS3Key": os.environ["MAILER_KEY"],
    "ReportSenderEmail": os.environ["REPORT_SENDER_EMAIL"],
    "ReportRecipientEmail": os.environ["REPORT_RECIPIENT_EMAIL"],
    "ScheduleState": os.environ["REPORTS_SCHEDULE_STATE"],
}
with open(sys.argv[1], "w") as file:
    json.dump(
        [{"ParameterKey": key, "ParameterValue": value} for key, value in values.items()],
        file,
    )
PY

log "deploying ${REPORTS_STACK_NAME} with schedule ${REPORTS_SCHEDULE_STATE}"
if ! aws cloudformation deploy \
  --stack-name "${REPORTS_STACK_NAME}" \
  --template-file "${REPORTS_TEMPLATE}" \
  --parameter-overrides "file://${PARAMS_FILE}" \
  --capabilities CAPABILITY_IAM \
  --no-fail-on-empty-changeset \
  --tags "PROJECT_NAME=${PROJECT_NAME}"; then
  warn "reports deployment failed; inspect ${REPORTS_STACK_NAME} stack events"
  exit 1
fi

log "reports stack deployed; schedule is ${REPORTS_SCHEDULE_STATE}"
