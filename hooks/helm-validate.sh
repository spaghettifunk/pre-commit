#!/usr/bin/env bash
set -euo pipefail

# ── config ────────────────────────────────────────────────────────────────────
CHART_DIRS=("./charts")          # adjust to your repo layout
HELM_ARGS=""                     # e.g. "-f values.prod.yaml"
NAMESPACE="default"              # namespace used for server-side dry-run
# ──────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

changed_charts() {
  # Only validate charts that have staged changes
  git diff --cached --name-only | \
    grep -E '^charts/' | \
    awk -F'/' '{print $1"/"$2}' | \
    sort -u
}

validate_chart() {
  local chart_dir="$1"

  if [[ ! -f "${chart_dir}/Chart.yaml" ]]; then
    return 0  # not a chart root, skip
  fi

  echo -e "${YELLOW}▶ Validating${NC} ${chart_dir}"

  # 1. Dependency update (skip if no dependencies)
  if grep -q 'dependencies' "${chart_dir}/Chart.yaml" 2>/dev/null; then
    helm dependency update "${chart_dir}" --quiet
  fi

  # 2. Render → validate against the API server
  local output
  if ! output=$(helm template "${chart_dir}" \
      --namespace "${NAMESPACE}" \
      ${HELM_ARGS} \
      2>&1 | kubectl apply \
        --dry-run=server \
        --namespace "${NAMESPACE}" \
        -f - 2>&1); then
    echo -e "${RED}✗ Validation failed for ${chart_dir}${NC}"
    echo "${output}"
    return 1
  fi

  echo -e "${GREEN}✓ ${chart_dir} is valid${NC}"
  return 0
}

main() {
  local failed=0

  # Validate only changed charts (fast path for large monorepos)
  local charts
  charts=$(changed_charts)

  if [[ -z "${charts}" ]]; then
    # Fallback: validate all configured chart dirs
    charts=$(printf '%s\n' "${CHART_DIRS[@]}")
  fi

  while IFS= read -r chart; do
    validate_chart "${chart}" || failed=1
  done <<< "${charts}"

  if [[ $failed -ne 0 ]]; then
    echo -e "\n${RED}Pre-commit hook failed. Fix the errors above before committing.${NC}"
    exit 1
  fi
}

main
