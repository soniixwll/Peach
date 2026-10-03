#!/usr/bin/env bash
# Create or update the separate Cognito stack. Google credentials are accepted
# only at deployment time and are never written back to project configuration.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="${ROOT}/infra/auth.yml"
ENV_FILE="${ROOT}/.env"
AUTH_ENV_FILE="${ROOT}/.env.auth.local"

log() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m==>\033[0m %s\n' "$*" >&2; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Exported values win. .env.auth.local is ignored by Git and may hold the two
# Google values when exporting them in the shell is inconvenient.
preset="$(export -p)"
for file in "${ENV_FILE}" "${AUTH_ENV_FILE}"; do
  if [[ -f "${file}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${file}"
    set +a
  fi
done
eval "${preset}"

for var in AWS_PROFILE AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN; do
  [[ -n "${!var:-}" ]] || unset "${var}"
done

PROJECT_NAME="${PROJECT_NAME:-peach}"
STACK_NAME="${AUTH_STACK_NAME:-${PROJECT_NAME}-auth}"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
COGNITO_DOMAIN_PREFIX="${COGNITO_DOMAIN_PREFIX:-sofia-peach}"
AUTH_CALLBACK_URL="${AUTH_CALLBACK_URL:-https://www.sofia-peach.pp.ua/login/}"
AUTH_LOGOUT_URL="${AUTH_LOGOUT_URL:-https://www.sofia-peach.pp.ua/login/}"
export AWS_DEFAULT_REGION="${AWS_REGION}"

command -v aws >/dev/null 2>&1 || die "aws cli is required"
command -v python3 >/dev/null 2>&1 || die "python3 is required"
aws sts get-caller-identity >/dev/null 2>&1 || die "no usable AWS credentials"

[[ -n "${GOOGLE_CLIENT_ID:-}" ]] \
  || die "GOOGLE_CLIENT_ID must be exported or set in ignored .env.auth.local"
[[ -n "${GOOGLE_CLIENT_SECRET:-}" ]] \
  || die "GOOGLE_CLIENT_SECRET must be exported or set in ignored .env.auth.local"

# Refuse to take a domain already owned by another user pool. An empty
# DomainDescription means the prefix is available.
DOMAIN_POOL_ID="$(aws cognito-idp describe-user-pool-domain \
  --domain "${COGNITO_DOMAIN_PREFIX}" \
  --query 'DomainDescription.UserPoolId' --output text 2>/dev/null || true)"
if [[ -n "${DOMAIN_POOL_ID}" && "${DOMAIN_POOL_ID}" != "None" ]]; then
  STACK_POOL_ID="$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" \
    --query "Stacks[0].Outputs[?OutputKey=='UserPoolId'].OutputValue" \
    --output text 2>/dev/null || true)"
  [[ "${DOMAIN_POOL_ID}" == "${STACK_POOL_ID}" ]] \
    || die "Cognito domain prefix ${COGNITO_DOMAIN_PREFIX} belongs to another user pool"
fi

PARAMS_FILE="$(mktemp)"
chmod 600 "${PARAMS_FILE}"
trap 'rm -f "${PARAMS_FILE}"' EXIT

PROJECT_NAME="${PROJECT_NAME}" \
COGNITO_DOMAIN_PREFIX="${COGNITO_DOMAIN_PREFIX}" \
AUTH_CALLBACK_URL="${AUTH_CALLBACK_URL}" \
AUTH_LOGOUT_URL="${AUTH_LOGOUT_URL}" \
GOOGLE_CLIENT_ID="${GOOGLE_CLIENT_ID}" \
GOOGLE_CLIENT_SECRET="${GOOGLE_CLIENT_SECRET}" \
python3 - "${PARAMS_FILE}" <<'PY'
import json
import os
import sys

parameters = {
    "ProjectName": os.environ["PROJECT_NAME"],
    "CognitoDomainPrefix": os.environ["COGNITO_DOMAIN_PREFIX"],
    "CallbackUrl": os.environ["AUTH_CALLBACK_URL"],
    "LogoutUrl": os.environ["AUTH_LOGOUT_URL"],
    "GoogleClientId": os.environ["GOOGLE_CLIENT_ID"],
    "GoogleClientSecret": os.environ["GOOGLE_CLIENT_SECRET"],
}
with open(sys.argv[1], "w") as file:
    json.dump(
        [{"ParameterKey": key, "ParameterValue": value} for key, value in parameters.items()],
        file,
    )
PY

if aws cloudformation describe-stacks --stack-name "${STACK_NAME}" >/dev/null 2>&1; then
  log "updating ${STACK_NAME}"
else
  log "creating ${STACK_NAME}"
fi

if ! aws cloudformation deploy \
  --stack-name "${STACK_NAME}" \
  --template-file "${TEMPLATE}" \
  --parameter-overrides "file://${PARAMS_FILE}" \
  --no-fail-on-empty-changeset \
  --tags "PROJECT_NAME=${PROJECT_NAME}"; then
  warn "deploy failed - most recent failure reasons:"
  aws cloudformation describe-stack-events --stack-name "${STACK_NAME}" \
    --max-items 30 \
    --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`||ResourceStatus==`UPDATE_FAILED`].[LogicalResourceId,ResourceStatusReason]' \
    --output table >&2 || true
  exit 1
fi

output() {
  aws cloudformation describe-stacks --stack-name "${STACK_NAME}" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}

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

env_set COGNITO_REGION "${AWS_REGION}"
env_set COGNITO_USER_POOL_ID "$(output UserPoolId)"
env_set COGNITO_CLIENT_ID "$(output UserPoolClientId)"
env_set COGNITO_DOMAIN "$(output CognitoDomain)"
env_set COGNITO_GOOGLE_ENABLED "true"

echo
echo "  user pool       $(output UserPoolId)"
echo "  app client      $(output UserPoolClientId)"
echo "  managed login   $(output CognitoDomain)"
echo "  callback        $(output CallbackUrl)"
echo "  logout          $(output LogoutUrl)"
echo "  google redirect $(output GoogleRedirectUrl)"
echo
log "Cognito configuration written to .env; the Google secret was not written"
