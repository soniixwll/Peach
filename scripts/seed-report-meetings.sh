#!/usr/bin/env bash
# Directly invoke the private administrative seed action on the backend Lambda.
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
BACKEND_STACK_NAME="${BACKEND_STACK_NAME:-${PROJECT_NAME}-backend}"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
WEEK="${WEEK:-}"

[[ -n "${WEEK}" ]] || die "WEEK is required, for example: make seed-report-meetings WEEK=2026-W40"
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
FUNCTION_NAME="$(aws cloudformation describe-stacks \
  --region "${AWS_REGION}" \
  --stack-name "${BACKEND_STACK_NAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='FunctionName'].OutputValue" \
  --output text)"
[[ -n "${FUNCTION_NAME}" && "${FUNCTION_NAME}" != "None" ]] \
  || die "${BACKEND_STACK_NAME} has no FunctionName output"

PAYLOAD="$(WEEK_VALUE="${WEEK}" python3 -c \
  'import json, os; print(json.dumps({"action":"seed_report_meetings","week":os.environ["WEEK_VALUE"]}, separators=(",", ":")))')"
RESULT_FILE="$(mktemp)"
trap 'rm -f "${RESULT_FILE}"' EXIT

FUNCTION_ERROR="$(aws lambda invoke \
  --region "${AWS_REGION}" \
  --function-name "${FUNCTION_NAME}" \
  --cli-binary-format raw-in-base64-out \
  --cli-read-timeout 300 \
  --payload "${PAYLOAD}" \
  --query FunctionError \
  --output text \
  "${RESULT_FILE}")"
if [[ -n "${FUNCTION_ERROR}" && "${FUNCTION_ERROR}" != "None" ]]; then
  die "meeting seed failed; inspect the backend CloudWatch logs"
fi

python3 - "${RESULT_FILE}" <<'PY'
import json
import pathlib
import sys

result = json.loads(pathlib.Path(sys.argv[1]).read_text())
print(
    f"seeded {result['week']}: inserted={result['inserted']} "
    f"skipped={result['skipped']}"
)
PY
