#!/usr/bin/env bash
set -uo pipefail

# Deploys all cdk stacks and exports the combined output to a file, preserving
# the ANSI colors that the cdk CLI normally only emits to a TTY.
#
# Usage:  npm run deploy:all:file [output-file]
# View with colors:  less -R cdk-deploy.ansi   (terminal)
#                    or open cdk-deploy.ansi in VS Code -> "ANSI Text: Open Preview"

OUTPUT_FILE="${1:-cdk-deploy.ansi}"

# Force chalk (used by the cdk CLI) to emit ANSI color codes even though stdout
# is a pipe/file rather than a terminal.
export FORCE_COLOR=1

# Confirmation before deploying (not captured to the log file).
echo "This will deploy all Innovation Sandbox stacks and write output to $OUTPUT_FILE"
echo "Do you want to continue? (y/N)"
read -r response
if [[ ! "$response" =~ ^[Yy]$ ]]; then
  echo "Deployment cancelled by user"
  exit 0
fi

: > "$OUTPUT_FILE"

for stack in account-pool idc data compute; do
  {
    echo ""
    echo "========================================"
    echo "===== deploy:$stack"
    echo "========================================"
  } | tee -a "$OUTPUT_FILE"
  npm run "deploy:$stack" 2>&1 | tee -a "$OUTPUT_FILE"
  # ${PIPESTATUS[0]} is npm's exit code (not tee's); stop on first failure,
  # matching the "&&" chaining used by deploy:all in package.json.
  status=${PIPESTATUS[0]}
  if [ "$status" -ne 0 ]; then
    echo "deploy:$stack failed (exit $status); stopping." | tee -a "$OUTPUT_FILE"
    exit "$status"
  fi
done

echo ""
echo "Deploy log written to $OUTPUT_FILE"
echo "View colors:  less -R $OUTPUT_FILE   (terminal)"
echo "              or in VS Code: open $OUTPUT_FILE -> Cmd+Shift+P -> \"ANSI Text: Open Preview\""
