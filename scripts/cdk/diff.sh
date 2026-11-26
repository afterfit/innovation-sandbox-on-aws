#!/bin/bash
set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

# Read-only counterpart of deploy.sh: synthesizes the app with the same context
# as deploy.sh, then runs `cdk diff` against the deployed stacks. It never
# deploys, and never builds or pushes the agent runtime image.

# =============================================================================
# Diff-specific functions
# =============================================================================

show_help() {
  cat <<EOF
Innovation Sandbox - Unified Diff Script

Usage:
  ./scripts/cdk/diff.sh                    Diff all stacks
  ./scripts/cdk/diff.sh account-pool       Diff only AccountPool stack
  ./scripts/cdk/diff.sh idc                Diff only IDC stack
  ./scripts/cdk/diff.sh data               Diff only Data stack
  ./scripts/cdk/diff.sh compute            Diff only Compute stack
  ./scripts/cdk/diff.sh data compute       Diff multiple specific stacks
  ./scripts/cdk/diff.sh all                Diff all stacks (explicit)

Options:
  --skip-build           Skip the TypeScript build before synthesis
  --help, -h             Show this help message
EOF
  exit 0
}

# `cdk diff` compares templates only (this CDK version ignores --parameters), so
# the stack parameter values deploy.sh requires from .env are not needed here.
validate_required_vars() {
  if [ -z "$DEPLOY_REGION" ]; then
    log_err "Missing required variable DEPLOY_REGION. Please set it in your .env file."
    return 1
  fi
}

build_common_args() {
  CDK_CONTEXT_ARGS=()

  [ -n "$STACK_PREFIX" ] && CDK_CONTEXT_ARGS+=(--context "stackPrefix=$STACK_PREFIX")
  [ -n "$DEPLOYMENT_MODE" ] && CDK_CONTEXT_ARGS+=(--context "deploymentMode=$DEPLOYMENT_MODE")

  # Logging and retention
  [ -n "$LOG_LEVEL" ] && CDK_CONTEXT_ARGS+=(--context "logLevel=$LOG_LEVEL")
  [ -n "$CLOUDWATCH_LOG_RETENTION_IN_DAYS" ] && CDK_CONTEXT_ARGS+=(--context "cloudWatchLogRetentionInDays=$CLOUDWATCH_LOG_RETENTION_IN_DAYS")
  [ -n "$S3_LOGS_ARCHIVE_RETENTION_IN_DAYS" ] && CDK_CONTEXT_ARGS+=(--context "s3LogsArchiveRetentionInDays=$S3_LOGS_ARCHIVE_RETENTION_IN_DAYS")
  [ -n "$S3_LOGS_GLACIER_RETENTION_IN_DAYS" ] && CDK_CONTEXT_ARGS+=(--context "s3LogsGlacierRetentionInDays=$S3_LOGS_GLACIER_RETENTION_IN_DAYS")

  # API throttling
  [ -n "$API_THROTTLING_RATE_LIMIT" ] && CDK_CONTEXT_ARGS+=(--context "apiThrottlingRateLimit=$API_THROTTLING_RATE_LIMIT")
  [ -n "$API_THROTTLING_BURST_LIMIT" ] && CDK_CONTEXT_ARGS+=(--context "apiThrottlingBurstLimit=$API_THROTTLING_BURST_LIMIT")

  # Cognito token validity
  [ -n "$COGNITO_ACCESS_TOKEN_VALIDITY_MINUTES" ] && CDK_CONTEXT_ARGS+=(--context "cognitoAccessTokenValidityMinutes=$COGNITO_ACCESS_TOKEN_VALIDITY_MINUTES")
  [ -n "$COGNITO_ID_TOKEN_VALIDITY_MINUTES" ] && CDK_CONTEXT_ARGS+=(--context "cognitoIdTokenValidityMinutes=$COGNITO_ID_TOKEN_VALIDITY_MINUTES")
  [ -n "$COGNITO_REFRESH_TOKEN_VALIDITY_DAYS" ] && CDK_CONTEXT_ARGS+=(--context "cognitoRefreshTokenValidityDays=$COGNITO_REFRESH_TOKEN_VALIDITY_DAYS")

  # Build-time context (affects synthesized templates)
  [ -n "$NUKE_CONFIG_FILE_PATH" ] && CDK_CONTEXT_ARGS+=(--context "nukeConfigFilePath=$NUKE_CONFIG_FILE_PATH")
  [ -n "$SCP_DIRECTORY_PATH" ] && CDK_CONTEXT_ARGS+=(--context "scpDirectoryPath=$SCP_DIRECTORY_PATH")
  [ -n "$PRIVATE_ACCOUNT_CLEANER_ECR_REPO" ] && CDK_CONTEXT_ARGS+=(--context "privateAccountCleanerEcrRepo=$PRIVATE_ACCOUNT_CLEANER_ECR_REPO")
  [ -n "$PRIVATE_SANDBOX_AGENT_RUNTIME_ECR_REPO" ] && CDK_CONTEXT_ARGS+=(--context "privateSandboxAgentRuntimeEcrRepo=$PRIVATE_SANDBOX_AGENT_RUNTIME_ECR_REPO")

  # Stack tags are deploy-time only and are not shown by `cdk diff`.

  # The `[ -n ... ] &&` lines above return 1 when their variable is unset; without
  # this, the last one would become the function's status and `set -e` would exit.
  return 0
}

diff_stack() {
  local stack="$1"
  local stack_name
  local profile
  stack_name=$(get_stack_name "$stack")
  profile=$(get_stack_profile "$stack")
  local args=(--app "${PROJECT_ROOT}/source/infrastructure/cdk.out" "$stack_name")

  [ -n "$profile" ] && args+=(--profile "$profile")

  run_cdk diff "${args[@]}"
}

agent_runtime_image_in_scope() {
  [ -n "$PRIVATE_SANDBOX_AGENT_RUNTIME_ECR_REPO" ] &&
    [[ " ${STACKS_TO_DIFF[*]} " == *" compute "* ]]
}

# Looks up the image pushed for the current source. Sets AGENT_RUNTIME_IMAGE_TAG
# and AGENT_RUNTIME_IMAGE_DIGEST (empty when no image was pushed for this
# source, or the repository does not exist yet). Exits on any other error.
lookup_agent_runtime_image() {
  local profile digest exit_code err_file err
  if ! AGENT_RUNTIME_IMAGE_TAG=$(npm run --silent agent-runtime:source-tag); then
    log_err "Could not compute the agent runtime source tag. Run 'npm install' first."
    exit 1
  fi

  profile=$(get_stack_profile compute)
  # stderr is kept apart so a warning on a successful call cannot corrupt the digest.
  err_file=$(mktemp)
  set +e
  digest=$(aws ecr describe-images \
    --repository-name "$PRIVATE_SANDBOX_AGENT_RUNTIME_ECR_REPO" \
    --image-ids "imageTag=$AGENT_RUNTIME_IMAGE_TAG" \
    --region "$DEPLOY_REGION" \
    ${profile:+--profile "$profile"} \
    --query 'imageDetails[0].imageDigest' \
    --output text 2>"$err_file")
  exit_code=$?
  set -e
  err=$(<"$err_file")
  rm -f "$err_file"

  AGENT_RUNTIME_IMAGE_DIGEST=""
  if [ $exit_code -eq 0 ] && [[ "$digest" == sha256:* ]]; then
    AGENT_RUNTIME_IMAGE_DIGEST="$digest"
  elif [[ "$err" != *ImageNotFoundException* && "$err" != *RepositoryNotFoundException* ]]; then
    log_err "Could not look up the agent runtime image ${PRIVATE_SANDBOX_AGENT_RUNTIME_ECR_REPO}:${AGENT_RUNTIME_IMAGE_TAG} in ${DEPLOY_REGION}: ${err:-$digest}"
    exit 1
  fi
}

# Pins the runtime to the digest of the image pushed for the current source, as
# deploy.sh would. Unlike deploy.sh, a missing image is never built: the template
# then references the source tag instead, so the diff shows the image changing
# where a deploy would show a digest.
add_agent_runtime_image_digest() {
  agent_runtime_image_in_scope || return 0

  lookup_agent_runtime_image
  if [ -z "$AGENT_RUNTIME_IMAGE_DIGEST" ]; then
    log_warn "No agent runtime image pushed for the current source (${PRIVATE_SANDBOX_AGENT_RUNTIME_ECR_REPO}:${AGENT_RUNTIME_IMAGE_TAG}); deploy.sh would build and push it."
    log_warn "Diffing against the tag instead of a digest."
    return 0
  fi

  log_info "Agent runtime image: ${PRIVATE_SANDBOX_AGENT_RUNTIME_ECR_REPO}:${AGENT_RUNTIME_IMAGE_TAG} (${AGENT_RUNTIME_IMAGE_DIGEST})"
  CDK_CONTEXT_ARGS+=(--context "sandboxAgentRuntimeImageDigest=$AGENT_RUNTIME_IMAGE_DIGEST")
}

# =============================================================================
# Execution
# =============================================================================

# Parse arguments
STACKS_TO_DIFF=()
SKIP_BUILD=false

for arg in "$@"; do
  case "$arg" in
    --help|-h) show_help ;;
    --skip-build) SKIP_BUILD=true ;;
    account-pool|idc|data|compute) STACKS_TO_DIFF+=("$arg") ;;
    all) STACKS_TO_DIFF=(account-pool idc data compute) ;;
    *)
      log_err "Unknown argument: $arg"
      printf "Usage: %s [account-pool|idc|data|compute|all] [--skip-build] [--help]\n" "$0"
      exit 1
      ;;
  esac
done

if [ ${#STACKS_TO_DIFF[@]} -eq 0 ]; then
  STACKS_TO_DIFF=(account-pool idc data compute)
fi

check_dependencies
load_env
resolve_stack_names
build_common_args

validate_required_vars || exit 1

add_agent_runtime_image_digest

# Build
# The generated packages under source/api-client and source/api-server are
# gitignored, so on a fresh checkout synth cannot resolve them at all — and on a
# warm tree it silently resolves a stale copy after the model changes.
if [ "$SKIP_BUILD" = false ]; then
  printf "\n"
  log_info "Building TypeScript packages..."

  set +e
  npm run build
  BUILD_EXIT=$?
  set -e

  if [ $BUILD_EXIT -ne 0 ]; then
    log_err "Build failed"
    exit 1
  fi

  log_ok "Build complete"
else
  printf "\n"
  log_warn "Skipping build (--skip-build); generated code may be stale"
fi

# Synth
printf "\n"
log_info "Synthesizing CDK application..."

set +e
run_cdk synth "${CDK_CONTEXT_ARGS[@]}"
SYNTH_EXIT=$?
set -e

if [ $SYNTH_EXIT -ne 0 ]; then
  log_err "CDK synthesis failed"
  exit 1
fi

log_ok "Synthesis complete"
printf "\n"

# Diff — a failure on one stack does not stop the others, since nothing is changed.
SUCCEEDED_STACKS=()
FAILED_STACKS=()

for stack in "${STACKS_TO_DIFF[@]}"; do
  DISPLAY_NAME=$(get_stack_name "$stack")

  log_info "Diffing ${DISPLAY_NAME}..."

  set +e
  diff_stack "$stack"
  DIFF_EXIT=$?
  set -e

  if [ $DIFF_EXIT -ne 0 ]; then
    FAILED_STACKS+=("$stack")
    log_err "${DISPLAY_NAME} diff FAILED"
  else
    SUCCEEDED_STACKS+=("$stack")
    log_ok "${DISPLAY_NAME} diff complete"
  fi
  printf "\n"
done

if [ ${#FAILED_STACKS[@]} -gt 0 ]; then
  log_err "========================================"
  log_err "Diff failed for:"
  for s in "${FAILED_STACKS[@]}"; do
    log_err "  $(get_stack_name "$s")"
  done
  log_err "========================================"
  exit 1
fi

log_ok "========================================"
log_ok "Diff completed successfully!"
log_ok "========================================"
