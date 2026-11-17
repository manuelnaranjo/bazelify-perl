#!/usr/bin/env bash
set -euo pipefail

# Configures .bazelrc.user for BuildBuddy remote cache and remote build execution (RBE).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

ENDPOINT="${1:-${BB_ENDPOINT:-${BUILDBUDDY_ENDPOINT:-}}}"
API_KEY="${2:-${BB_API_KEY:-${BUILDBUDDY_API_KEY:-}}}"

if [ -z "${ENDPOINT}" ] || [ -z "${API_KEY}" ]; then
  echo "Usage: $0 [<endpoint> <api-key>] (or set BB_ENDPOINT and BB_API_KEY)" >&2
  exit 1
fi

cat <<EOF > ".bazelrc.user"
common:buildbuddy --bes_backend=grpcs://${ENDPOINT}
common:buildbuddy --bes_results_url=https://${ENDPOINT}/invocation/
common:buildbuddy --remote_cache=grpcs://${ENDPOINT}
common:buildbuddy --remote_header=x-buildbuddy-api-key=${API_KEY}

# Enable RBE execution on BuildBuddy cluster
common:rbe --config=buildbuddy
common:rbe --remote_executor=grpcs://${ENDPOINT}
EOF

echo "Configured .bazelrc.user with BuildBuddy RBE endpoint ${ENDPOINT}"
