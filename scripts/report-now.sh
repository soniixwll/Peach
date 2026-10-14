#!/usr/bin/env bash
# Enqueue one explicit ISO week for the deployed Peach report builder.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT}/.env"

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
REPORTS_STACK_NAME="${REPORTS_STACK_NAME:-${PROJECT_NAME}-reports}"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
WEEK="${WEEK:-}"

[[ -n "${WEEK}" ]] || die "WEEK is required, for example: make report-now WEEK=2026-W40"
python3 - "${WEEK}" <<'PY' || exit 1
import datetime
import re
import sys

week = sys.argv[1]
match = re.fullmatch(r"(\d{4})-W(\d{2})", week)
if match is None:
    raise SystemExit("error: WEEK must use ISO format YYYY-Www, for example 2026-W40")
try:
    datetime.date.fromisocalendar(int(match[1]), int(match[2]), 1)
except ValueError as exc:
    raise SystemExit(f"error: invalid ISO week: {week}") from exc
PY

command -v aws >/dev/null 2>&1 || die "aws is required but not installed"

QUEUE_URL="$(aws cloudformation describe-stacks \
  --region "${AWS_REGION}" \
  --stack-name "${REPORTS_STACK_NAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='ReportsQueueUrl'].OutputValue" \
  --output text)"
[[ -n "${QUEUE_URL}" && "${QUEUE_URL}" != "None" ]] \
  || die "${REPORTS_STACK_NAME} has no ReportsQueueUrl output"

MESSAGE_BODY="$(WEEK_VALUE="${WEEK}" python3 -c \
  'import json, os; print(json.dumps({"source":"manual","week":os.environ["WEEK_VALUE"]}, separators=(",", ":")))')"

MESSAGE_ID="$(aws sqs send-message \
  --region "${AWS_REGION}" \
  --queue-url "${QUEUE_URL}" \
  --message-body "${MESSAGE_BODY}" \
  --query MessageId \
  --output text)"

printf 'queued report for %s (message %s)\n' "${WEEK}" "${MESSAGE_ID}"
