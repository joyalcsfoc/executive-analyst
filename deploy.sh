#!/usr/bin/env bash
#
# Deployment helper for the executive-analyst Databricks Asset Bundle.
#
# Usage:
#   ./deploy.sh [action] [options]
#
# Actions:
#   validate        Validate the bundle configuration (default)
#   deploy          Deploy the bundle (Genie space + metric-view job)
#   apply-metrics   Run apply_metric_views (tags, grants, kg_nodes/kg_edges, drop legacy)
#   test-metrics    Run validate_metric_views (read-only KPI-formula + dim-uniqueness checks)
#   regen-tags      Regenerate tag SQL + KG SQL + HTML reference from exec_analyst.ttl
#   destroy         Tear down the deployed bundle resources
#   open            Open the deployed Genie space in the browser
#   summary         Print the resolved bundle configuration for the target
#
# Recommended first-time order (Genie validates metric views at deploy):
#   1. ./deploy.sh deploy --target dev          # deploys job + Genie (views must already exist)
#   2. ./deploy.sh apply-metrics --target dev   # tags, grants, ontology.kg_* (does not CREATE metrics_*)
#   3. ./deploy.sh test-metrics --target dev    # read-only KPI-formula + dim-uniqueness assertions
#
# After editing src/ontology/exec_analyst.ttl (the ontology source of truth):
#   ./deploy.sh regen-tags                  # tags SQL + KG SQL + HTML reference
#   ./deploy.sh deploy --target dev && ./deploy.sh apply-metrics --target dev
#
# If the Genie space already points at facts-only sources, you can deploy the job,
# apply-metrics, then deploy again after Genie JSON references the metric views.
#
# Options:
#   -t, --target <name>       Bundle target: dev or prod (default: dev)
#   -p, --profile <name>      Databricks CLI auth profile (default: DATABRICKS_CONFIG_PROFILE or CLI default)
#   -w, --warehouse-id <id>   Override the warehouse_id bundle variable
#   -c, --gold-catalog <name> Override the gold_catalog bundle variable (default: gold_dev / gold per target)
#   -y, --auto-approve        Skip confirmation prompts on deploy/destroy
#   -h, --help                Show this help message
#
# Examples:
#   ./deploy.sh validate --target dev
#   ./deploy.sh deploy --target dev --profile data --warehouse-id abc123def456
#   ./deploy.sh apply-metrics --target dev
#   ./deploy.sh regen-tags
#   ./deploy.sh deploy --target prod --warehouse-id abc123def456 --gold-catalog gold --auto-approve
#   ./deploy.sh open --target dev
#   ./deploy.sh destroy --target dev

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ACTION="validate"
TARGET="dev"
PROFILE=""
WAREHOUSE_ID=""
GOLD_CATALOG=""
AUTO_APPROVE=""

usage() {
  sed -n '2,44p' "$0" | sed 's/^# \{0,1\}//'
}

# First positional arg (if not an option) is the action.
if [[ $# -gt 0 && "$1" != -* ]]; then
  ACTION="$1"
  shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--target)
      TARGET="$2"; shift 2 ;;
    -p|--profile)
      PROFILE="$2"; shift 2 ;;
    -w|--warehouse-id)
      WAREHOUSE_ID="$2"; shift 2 ;;
    -c|--gold-catalog)
      GOLD_CATALOG="$2"; shift 2 ;;
    -y|--auto-approve)
      AUTO_APPROVE="--auto-approve"; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1 ;;
  esac
done

if ! command -v databricks >/dev/null 2>&1; then
  echo "Error: Databricks CLI not found on PATH. Install it from https://docs.databricks.com/dev-tools/cli/install.html" >&2
  exit 1
fi

CLI_VERSION="$(databricks --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)"
if [[ -n "$CLI_VERSION" ]]; then
  CLI_MAJOR="${CLI_VERSION%%.*}"
  CLI_MINOR="$(echo "$CLI_VERSION" | cut -d. -f2)"
  if (( CLI_MAJOR < 1 || (CLI_MAJOR == 1 && CLI_MINOR < 3) )); then
    echo "Error: Databricks CLI $CLI_VERSION detected, but genie_space bundle resources require >= 1.3.0." >&2
    exit 1
  fi
fi

BUNDLE_ARGS=(--target "$TARGET")
if [[ -n "$PROFILE" ]]; then
  BUNDLE_ARGS+=(--profile "$PROFILE")
fi

VAR_ARGS=()
if [[ -n "$WAREHOUSE_ID" ]]; then
  VAR_ARGS+=(--var "warehouse_id=$WAREHOUSE_ID")
fi
if [[ -n "$GOLD_CATALOG" ]]; then
  VAR_ARGS+=(--var "gold_catalog=$GOLD_CATALOG")
fi

echo "==> Action: $ACTION | Target: $TARGET | Profile: ${PROFILE:-<default>}"

case "$ACTION" in
  validate)
    databricks bundle validate "${BUNDLE_ARGS[@]}" "${VAR_ARGS[@]}"
    ;;
  deploy)
    databricks bundle validate "${BUNDLE_ARGS[@]}" "${VAR_ARGS[@]}"
    echo "==> Deploying (Genie space + apply_metric_views job)..."
    databricks bundle deploy "${BUNDLE_ARGS[@]}" "${VAR_ARGS[@]}" $AUTO_APPROVE
    echo "==> Deployed."
    echo "    If this is the first deploy and Genie failed because metric views are missing:"
    echo "      ./deploy.sh apply-metrics --target $TARGET"
    echo "      ./deploy.sh deploy --target $TARGET"
    echo "    Otherwise open with: ./deploy.sh open --target $TARGET"
    ;;
  apply-metrics)
    echo "==> Running apply_metric_views job (kg_nodes/kg_edges + kg_functions, GRANT SELECT, tags, drop legacy)..."
    echo "    Ensure you have already run './deploy.sh deploy' so the job exists."
    databricks bundle run apply_metric_views "${BUNDLE_ARGS[@]}" "${VAR_ARGS[@]}"
    echo "==> Metric views + knowledge graph applied (tags + grants + kg_nodes/kg_edges)."
    echo "    Neighborhood SQL: src/ontology/kg_queries.sql"
    echo "    Re-run './deploy.sh deploy --target $TARGET' if Genie still needs updating."
    ;;
  test-metrics)
    echo "==> Running validate_metric_views job (KPI trap + dim-uniqueness + fan-out assertions)..."
    echo "    Read-only; safe to run anytime, including against prod."
    databricks bundle run validate_metric_views "${BUNDLE_ARGS[@]}" "${VAR_ARGS[@]}"
    echo "==> All assertions passed (a failed check would have failed this job run)."
    echo "    Details: src/tests/*.sql. Genie-UX companion: src/ontology/benchmark_questions.md."
    ;;
  regen-tags)
    echo "==> Regenerating tag_metric_views.sql, materialize_kg.sql, grant_kg.sql, kg_functions.sql,"
    echo "    kg_queries.sql, ontology_reference.html and genie_context.json from src/ontology/exec_analyst.ttl..."
    python "$SCRIPT_DIR/src/ontology/generate.py"
    echo "==> Done. Commit the generated files if changed; deploy + apply-metrics to push to UC."
    echo "    exec_analyst.ttl is the source of truth; everything else here is generated — do not hand-edit it."
    ;;
  destroy)
    databricks bundle destroy "${BUNDLE_ARGS[@]}" "${VAR_ARGS[@]}" $AUTO_APPROVE
    ;;
  open)
    databricks bundle open "${BUNDLE_ARGS[@]}"
    ;;
  summary)
    databricks bundle summary "${BUNDLE_ARGS[@]}" "${VAR_ARGS[@]}"
    ;;
  *)
    echo "Unknown action: $ACTION" >&2
    usage
    exit 1
    ;;
esac
