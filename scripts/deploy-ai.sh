#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT}/.env"
TEMPLATE="${ROOT}/infra/ai.yml"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
log() { printf '\033[36m==>\033[0m %s\n' "$*"; }

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
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
AI_STACK_NAME="${AI_STACK_NAME:-${PROJECT_NAME}-ai}"
BACKEND_STACK_NAME="${BACKEND_STACK_NAME:-${PROJECT_NAME}-backend}"
AUTH_STACK_NAME="${AUTH_STACK_NAME:-${PROJECT_NAME}-auth}"
PARSER_MODEL="${PARSER_MODEL:-us.amazon.nova-micro-v1:0}"
AI_ALLOWED_ORIGIN="${AI_ALLOWED_ORIGIN:-https://www.sofia-peach.pp.ua}"
AI_BUDGET_EMAIL="${AI_BUDGET_EMAIL:-}"
export AWS_DEFAULT_REGION="${AWS_REGION}"

[[ "${AWS_REGION}" == "us-east-1" ]] || die "agenda parser must be deployed in us-east-1"
[[ -n "${AI_BUDGET_EMAIL}" ]] || die "AI_BUDGET_EMAIL is required for the monthly budget alarm"
aws sts get-caller-identity >/dev/null 2>&1 || die "no usable AWS credentials"

stack_output() {
  aws cloudformation describe-stacks --stack-name "$1" \
    --query "Stacks[0].Outputs[?OutputKey=='$2'].OutputValue" --output text
}

BACKEND_FUNCTION="$(stack_output "${BACKEND_STACK_NAME}" FunctionName)"
IMAGE_URI="$(aws lambda get-function --function-name "${BACKEND_FUNCTION}" --query Code.ImageUri --output text)"
ARCHITECTURE="$(aws lambda get-function-configuration --function-name "${BACKEND_FUNCTION}" --query 'Architectures[0]' --output text)"
USER_POOL_ID="$(stack_output "${AUTH_STACK_NAME}" UserPoolId)"
CLIENT_ID="$(stack_output "${AUTH_STACK_NAME}" UserPoolClientId)"
ISSUER="$(stack_output "${AUTH_STACK_NAME}" Issuer)"
JWKS="$(curl --fail --silent --show-error "${ISSUER}/.well-known/jwks.json" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin),separators=(",",":")))')"

PARAMS_FILE="$(mktemp)"
chmod 600 "${PARAMS_FILE}"
trap 'rm -f "${PARAMS_FILE}"' EXIT

PROJECT_NAME="${PROJECT_NAME}" IMAGE_URI="${IMAGE_URI}" ARCHITECTURE="${ARCHITECTURE}" \
PARSER_MODEL="${PARSER_MODEL}" AI_ALLOWED_ORIGIN="${AI_ALLOWED_ORIGIN}" ISSUER="${ISSUER}" \
CLIENT_ID="${CLIENT_ID}" JWKS="${JWKS}" AI_BUDGET_EMAIL="${AI_BUDGET_EMAIL}" \
python3 - "${PARAMS_FILE}" <<'PY'
import json
import os
import sys

values = {
    "ProjectName": os.environ["PROJECT_NAME"],
    "BackendImageUri": os.environ["IMAGE_URI"],
    "Architecture": os.environ["ARCHITECTURE"],
    "ParserModel": os.environ["PARSER_MODEL"],
    "AllowedOrigin": os.environ["AI_ALLOWED_ORIGIN"],
    "CognitoIssuer": os.environ["ISSUER"],
    "CognitoClientId": os.environ["CLIENT_ID"],
    "CognitoJwksJson": os.environ["JWKS"],
    "BudgetNotificationEmail": os.environ["AI_BUDGET_EMAIL"],
}
with open(sys.argv[1], "w") as file:
    json.dump([{"ParameterKey": key, "ParameterValue": value} for key, value in values.items()], file)
PY

log "deploying ${AI_STACK_NAME} with ${PARSER_MODEL}"
aws cloudformation deploy \
  --stack-name "${AI_STACK_NAME}" \
  --template-file "${TEMPLATE}" \
  --parameter-overrides "file://${PARAMS_FILE}" \
  --capabilities CAPABILITY_IAM \
  --no-fail-on-empty-changeset \
  --tags "PROJECT_NAME=${PROJECT_NAME}"

PARSER_URL="$(stack_output "${AI_STACK_NAME}" FunctionUrl)"
env_set() {
  KEY="$1" VALUE="$2" ENV_FILE="${ENV_FILE}" python3 - <<'PY'
import os
import re

key, value, path = os.environ["KEY"], os.environ["VALUE"], os.environ["ENV_FILE"]
lines = open(path).read().splitlines() if os.path.exists(path) else []
pattern = re.compile(rf"^{re.escape(key)}=")
for index, line in enumerate(lines):
    if pattern.match(line):
        lines[index] = f"{key}={value}"
        break
else:
    lines.append(f"{key}={value}")
open(path, "w").write("\n".join(lines) + "\n")
PY
}
env_set AGENDA_PARSER_URL "${PARSER_URL}"
log "agenda parser deployed: ${PARSER_URL}"
log "public parser URL written to the ignored .env; deploy the frontend next"
