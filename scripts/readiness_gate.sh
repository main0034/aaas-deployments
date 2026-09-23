#!/usr/bin/env bash
# Post-apply readiness gate (D-22).
#
# `terraform apply` succeeding means Terraform did its job, not that the
# application runs. At min_replicas = 0 nothing starts during the apply, so a
# revision whose `migrate` init container fails is reported as a successful
# deploy (FINDINGS.md, finding 16).
#
# This asks the platform, not the app. A request to the app URL is answered by
# whichever revision is serving - after a failed deploy that is the OLD one, so
# anything the app reports about itself (pending migrations, latest migration)
# describes the wrong revision. The revision's own runningState does not.
#
#   1. Find the revision this apply produced.
#   2. Poke the app so a replica starts, and poll that revision until it is
#      Running and is the latest ready revision - or fails, or times out.
#   3. Only then ask /ready (Single revision mode: the new revision is now the
#      one answering) and require database == ok.
#   4. On failure, pull the init container's own log from Log Analytics, because
#      `az containerapp logs show --container migrate` cannot find it.
#
# Inputs (env): RESOURCE_GROUP, APP_URL
# Outputs ($GITHUB_OUTPUT): result, reason, revision, migration, log (multi-line)

set -uo pipefail

RG="${RESOURCE_GROUP:?RESOURCE_GROUP is required}"
APP_URL="${APP_URL:?APP_URL is required}"
READY_TIMEOUT="${GATE_READY_TIMEOUT_SECONDS:-420}"
LOG_TIMEOUT="${GATE_LOG_TIMEOUT_SECONDS:-360}"
POLL="${GATE_POLL_SECONDS:-10}"
OUT="${GITHUB_OUTPUT:-/dev/null}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

az config set extension.use_dynamic_install=yes_without_prompt --only-show-errors >/dev/null 2>&1 || true

emit()      { echo "$1=$2" >> "$OUT"; }
emit_multi() { { echo "$1<<__GATE_EOF__"; echo "$2"; echo "__GATE_EOF__"; } >> "$OUT"; }
ts()        { echo "$(( $(date +%s) - START ))s"; }

START=$(date +%s)

# --- Log Analytics ----------------------------------------------------------
# Ingestion lags by minutes, so poll. Stop early once the runner's own failure
# line is in; otherwise return whatever arrived, which may be nothing.
fetch_logs() {
  local ws deadline q rows sys
  ws=$(az monitor log-analytics workspace list -g "$RG" --query "[0].customerId" -o tsv 2>/dev/null)
  if [ -z "$ws" ]; then
    echo "(no Log Analytics workspace found in $RG)"
    return
  fi

  q="ContainerAppConsoleLogs_CL
| where RevisionName_s == '$REV' and ContainerName_s == 'migrate'
| order by TimeGenerated asc
| project Log_s
| take 40"

  deadline=$(( $(date +%s) + LOG_TIMEOUT ))
  rows=""
  while [ "$(date +%s)" -lt "$deadline" ]; do
    rows=$(az monitor log-analytics query -w "$ws" --analytics-query "$q" -o json 2>/dev/null \
      | jq -r '.[].Log_s' 2>/dev/null)
    if grep -q '^\[migrate\] FAILED' <<<"$rows"; then break; fi
    echo "  [$(ts)] waiting for the migrate log to reach Log Analytics..." >&2
    sleep 20
  done

  if [ -n "$rows" ]; then
    echo "$rows"
  else
    echo "(no output from the migrate init container reached Log Analytics within ${LOG_TIMEOUT}s - the cause may not be the migration)"
  fi

  # The platform's own view of the revision: image pull failures, probe
  # failures and the like never reach the console log.
  sys=$(az monitor log-analytics query -w "$ws" --analytics-query "ContainerAppSystemLogs_CL
| where RevisionName_s == '$REV'
| order by TimeGenerated desc
| project Log_s
| take 8" -o json 2>/dev/null | jq -r '.[].Log_s' 2>/dev/null)
  if [ -n "$sys" ]; then
    echo "--- platform events (newest first) ---"
    echo "$sys"
  fi
}

fail() {
  local reason="$1" log first
  echo "::error::Readiness gate: $reason"
  echo "Fetching the init container's log from Log Analytics..."
  log=$(fetch_logs)
  first=$(grep -m1 '^\[migrate\] FAILED' <<<"$log" || true)
  [ -n "$first" ] && echo "::error::$first"
  echo "$log"

  emit result failed
  emit reason "$reason"
  emit revision "${REV:-unknown}"
  emit_multi log "$log"

  {
    echo "### Readiness gate: FAILED"
    echo
    echo "**Terraform applied, but the new revision is not running.**"
    echo
    echo "- Reason: $reason"
    echo "- Revision: \`${REV:-unknown}\`"
    echo "- URL: $APP_URL"
    [ -n "$first" ] && { echo; echo "Cause: \`$first\`"; }
    echo
    echo '```'
    echo "$log"
    echo '```'
  } >> "$SUMMARY"
  exit 1
}

# --- 1. Which revision did this apply produce? -------------------------------
APPS=$(az containerapp list -g "$RG" --query "[].name" -o tsv)
if [ "$(grep -c . <<<"$APPS")" -ne 1 ]; then
  REV=""
  fail "expected exactly one container app in $RG, found: ${APPS:-none}"
fi
APP="$APPS"
REV=$(az containerapp show -g "$RG" -n "$APP" --query properties.latestRevisionName -o tsv)
[ -n "$REV" ] || fail "could not read latestRevisionName for $APP"
echo "App $APP, revision under test: $REV"

# --- 2. Start a replica and wait for the platform's verdict ------------------
deadline=$(( START + READY_TIMEOUT ))
state="unknown"
while :; do
  # At min_replicas = 0 nothing runs the new revision until something asks.
  # The response itself is irrelevant - it may come from the old revision.
  curl -s -o /dev/null -m 15 "$APP_URL/health" || true

  rev_json=$(az containerapp revision show -g "$RG" -n "$APP" --revision "$REV" \
    --query "{running:properties.runningState, health:properties.healthState, provisioning:properties.provisioningState, replicas:properties.replicas}" \
    -o json 2>/dev/null || echo '{}')
  running=$(jq -r '.running // "unknown"' <<<"$rev_json")
  health=$(jq -r '.health // "unknown"' <<<"$rev_json")
  prov=$(jq -r '.provisioning // "unknown"' <<<"$rev_json")
  replicas=$(jq -r '.replicas // "?"' <<<"$rev_json")
  ready_rev=$(az containerapp show -g "$RG" -n "$APP" --query properties.latestReadyRevisionName -o tsv 2>/dev/null || echo "")
  state="runningState=$running healthState=$health provisioningState=$prov replicas=$replicas latestReady=$ready_rev"
  echo "[$(ts)] $state"

  case "$running" in
    *Failed*) fail "revision $REV is $running" ;;
  esac
  [ "$prov" = "Failed" ] && fail "revision $REV provisioning failed"

  if [ "$running" = "Running" ] && [ "$ready_rev" = "$REV" ]; then
    break
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    fail "revision $REV did not become ready within ${READY_TIMEOUT}s ($state)"
  fi
  sleep "$POLL"
done

# --- 3. The app's own view, now that the new revision is the one answering ---
body=""
for attempt in 1 2 3; do
  body=$(curl -s -m 90 "$APP_URL/ready" || true)
  [ "$(jq -r '.database // empty' <<<"$body" 2>/dev/null)" = "ok" ] && break
  echo "[$(ts)] /ready attempt $attempt: ${body:-no response}"
  sleep 10
done
database=$(jq -r '.database // "no response"' <<<"$body" 2>/dev/null || echo "unparseable")
if [ "$database" != "ok" ]; then
  fail "revision $REV is running but /ready reports database=$database: $(jq -r '.detail // empty' <<<"$body" 2>/dev/null)"
fi
migration=$(jq -r '.migration // "none"' <<<"$body")

# --- 4. Pass ------------------------------------------------------------------
echo "Ready after $(ts): revision $REV, migration $migration"
emit result ok
emit revision "$REV"
emit migration "$migration"
{
  echo "### Readiness gate: passed"
  echo
  echo "- URL: $APP_URL"
  echo "- Revision: \`$REV\` (Running, latest ready)"
  echo "- Schema: \`$migration\`"
  echo "- Time to ready: $(ts)"
} >> "$SUMMARY"
