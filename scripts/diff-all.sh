#!/usr/bin/env bash
set -uo pipefail

# Runs all cdk diffs and exports the combined output to a file, preserving the
# green "+" / red "-" ANSI colors that cdk normally only emits to a TTY.
#
# Usage:  npm run diff:all [output-file]
# View with colors:  less -R cdk-diff.ansi   (terminal)
#                    or open cdk-diff.ansi in VS Code -> "ANSI Text: Open Preview"

OUTPUT_FILE="${1:-cdk-diff.ansi}"

# Force chalk (used by the cdk CLI) to emit ANSI color codes even though stdout
# is a pipe/file rather than a terminal.
export FORCE_COLOR=1

: > "$OUTPUT_FILE"

for stack in account-pool idc data compute; do
  {
    echo ""
    echo "========================================"
    echo "===== diff:$stack"
    echo "========================================"
  } | tee -a "$OUTPUT_FILE"
  npm run "diff:$stack" 2>&1 | tee -a "$OUTPUT_FILE"
  # ${PIPESTATUS[0]} is npm's exit code (not tee's). Note: cdk diff exits
  # non-zero when differences are found, so we only stop on a real error (>1).
  status=${PIPESTATUS[0]}
  if [ "$status" -gt 1 ]; then
    echo "diff:$stack errored (exit $status); stopping." | tee -a "$OUTPUT_FILE"
    exit "$status"
  fi
done

echo ""
echo "Diff written to $OUTPUT_FILE"
echo "View colors:  less -R $OUTPUT_FILE   (terminal)"
echo "              or in VS Code: open $OUTPUT_FILE -> Cmd+Shift+P -> \"ANSI Text: Open Preview\""
