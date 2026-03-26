#!/usr/bin/env bash
set -euo pipefail

# ── config ────────────────────────────────────────────────────────────────────
CHART_DIRS=("./charts")          # adjust to your repo layout
HELM_ARGS=""                     # e.g. "-f values.prod.yaml"
NAMESPACE="default"              # namespace used for server-side dry-run
# ──────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

changed_charts() {
  # Find all changed files under charts/, then walk up to find the Chart.yaml root
  git diff --cached --name-only | grep -E '^charts/' | while IFS= read -r file; do
    dir=$(dirname "$file")
    # Walk up the directory tree to find the nearest Chart.yaml
    while [[ "$dir" != "." && "$dir" != "charts" ]]; do
      if [[ -f "${dir}/Chart.yaml" ]]; then
        echo "$dir"
        break
      fi
      dir=$(dirname "$dir")
    done
  done | sort -u
}

validate_chart() {
  local chart_dir="$1"

  echo -e "${YELLOW}▶ Validating${NC} ${chart_dir}"

  if grep -q 'dependencies' "${chart_dir}/Chart.yaml" 2>/dev/null; then
    helm dependency update "${chart_dir}" --quiet
  fi

  local output
  if ! output=$(helm template "${chart_dir}" \
      --namespace "${NAMESPACE}" \
      ${HELM_ARGS} 2>&1 | \
      kubectl apply --dry-run=server --namespace "${NAMESPACE}" -f - 2>&1); then
    echo -e "${RED}✗ Validation failed for ${chart_dir}${NC}"
    echo "${output}"
    return 1
  fi

  echo -e "${GREEN}✓ ${chart_dir} is valid${NC}"
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
