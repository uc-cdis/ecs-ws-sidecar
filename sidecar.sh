#!/usr/bin/env bash
set -Eeuo pipefail

# ===== Globals =====
LOGFILE="/data/populate_log.txt"
RUNNING=1

log() {
  local ts
  ts="$(date "+%Y-%m-%d %H:%M:%S")"
  echo "${ts}: $*" | tee -a "$LOGFILE"
}

# Kill children, flip RUNNING, and exit immediately
shutdown() {
  RUNNING=0
  log "Shutdown requested; terminating child processes…"
  # Kill all children of this script
  pkill -P $$ || true
  # Give them a brief moment to exit gracefully
  wait || true
  log "Exited."
  exit 0
}

trap shutdown TERM INT HUP QUIT

# Curl defaults (fast-fail, timeouts)
_curl() {
  # -f: fail on HTTP errors; --connect-timeout & --max-time to avoid hangs
  curl -sfS --retry 0 --connect-timeout 5 --max-time 15 "$@"
}

# Validate JSON; if invalid, treat as empty string
json_or_empty() {
  local input="$1"
  if jq -e . >/dev/null 2>&1 <<<"$input"; then
    printf '%s' "$input"
  else
    printf ''
  fi
}

apikeyfile() {
  if [[ ! -d "/.gen3" ]]; then
    log "Please mount shared docker volume under /.gen3. Gen3 SDK may not be configured correctly; creating directory."
    mkdir -p /.gen3
  fi
  if [[ -z "${API_KEY:-}" ]]; then
    log "\$API_KEY not set. Skipping writing api key to file. WARNING: Gen3 SDK will not be configured correctly."
  else
    log "Writing apiKey to /.gen3/credentials.json"
    jq -n --arg api_key "${API_KEY}" '{api_key:$api_key}' > /.gen3/credentials.json
  fi
}

get_access_token() {
  log "Getting access token from https://$GEN3_ENDPOINT/user/"
  local tries=0
  while (( tries < 10 )) && (( RUNNING )); do
    ACCESS_TOKEN="$(_curl -H "Content-Type: application/json" \
      -X POST "https://$GEN3_ENDPOINT/user/credentials/api/access_token/" \
      -d "{\"api_key\":\"${API_KEY:-}\"}" | jq -r .access_token || true)"
    if [[ -n "${ACCESS_TOKEN:-}" && "${ACCESS_TOKEN}" != "null" ]]; then
      export ACCESS_TOKEN
      log "Access token acquired."
      return 0
    fi
    ((tries++))
    log "Unable to get ACCESS TOKEN (attempt ${tries}); retrying in 5s…"
    sleep 5 & wait $!
  done
  log "Failed to obtain ACCESS TOKEN."
  exit 1
}

mount_hatchery_files() {
  log "Mounting Hatchery files"
  local FOLDER="/data"
  mkdir -p "$FOLDER"

  log "Fetching files to mount… (workspace flavor: '${WORKSPACE_FLAVOR:-}')"
  local DATA
  DATA="$(_curl -H "Authorization: Bearer ${ACCESS_TOKEN}" "https://$GEN3_ENDPOINT/lw-workspace/mount-files" || true)"
  DATA="$(json_or_empty "${DATA:-}")"
  [[ -z "$DATA" ]] && { log "No mount-files response."; return 0; }

  # Use process substitution to avoid subshell so traps work
  while IFS= read -r item; do
    [[ -z "${item:-}" ]] && continue
    file_path=$(jq -r .file_path <<<"$item")
    workspace_flavor=$(jq -r .workspace_flavor <<<"$item")
    if [[ -z "${workspace_flavor}" || -z "${WORKSPACE_FLAVOR:-}" || "${workspace_flavor}" == "${WORKSPACE_FLAVOR:-}" ]]; then
      log "Mounting '$file_path'"
      mkdir -p "$FOLDER/$(dirname "$file_path")"
      _curl -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        "https://$GEN3_ENDPOINT/lw-workspace/mount-files?file_path=$file_path" > "$FOLDER/$file_path" || log "Failed mounting '$file_path'"
    else
      log "Skipping '$file_path' (workspace flavor '$workspace_flavor' does not match)"
    fi
  done < <(jq -c -r '.[]' <<<"$DATA")

  chown -R 1000:100 "$FOLDER"
}

populate_notebook() {
  local MANIFEST_JSON="$1"
  local FOLDER="$2"

  local manifest_pull="!gen3  drs-pull manifest manifest.json"
  local manifest_ls="!gen3 drs-pull ls manifest.json"

  jq --arg cmd "$manifest_ls"  '.cells[1].source |= $cmd' "$FOLDER/data.ipynb" > "$FOLDER/data.tmp" && mv "$FOLDER/data.tmp" "$FOLDER/data.ipynb"
  jq --arg cmd "$manifest_pull" '.cells[3].source |= $cmd' "$FOLDER/data.ipynb" > "$FOLDER/data.tmp" && mv "$FOLDER/data.tmp" "$FOLDER/data.ipynb"

  while IFS= read -r j; do
    [[ -z "$j" ]] && continue
    obj=$(jq -r .object_id <<<"$j")
    filename=$(jq -r .file_name  <<<"$j")
    filesize=$(jq -r .file_size  <<<"$j")
    local drs_pull="!gen3 drs-pull object $obj"

    jq --arg cmd "# File name: $filename - File size: $filesize" '.cells[5].source += [$cmd]' "$FOLDER/data.ipynb" > "$FOLDER/data.tmp" && mv "$FOLDER/data.tmp" "$FOLDER/data.ipynb"
    jq --arg cmd "$drs_pull" '.cells[5].source += [$cmd]' "$FOLDER/data.ipynb" > "$FOLDER/data.tmp" && mv "$FOLDER/data.tmp" "$FOLDER/data.ipynb"
  done < <(jq -c '.[]' <<<"$MANIFEST_JSON")

  log "Done populating notebook"
}

process_files() {
  local base_dir="$1"
  local data_json="$2"

  while IFS= read -r i; do
    [[ -z "$i" ]] && continue
    FILENAME=$(jq -r .filename <<<"$i")
    FOLDERNAME="${FILENAME%.*}"
    FOLDER="/data/${GEN3_ENDPOINT}/exported-${base_dir}/exported-${FOLDERNAME}"

    if [[ ! -d "$FOLDER" ]]; then
      log "mkdir -p $FOLDER"
      mkdir -p "$FOLDER"
      chown -R 1000:100 "$FOLDER"

      if [[ "$base_dir" == "manifests" ]]; then
        MANIFEST_FILE="$(_curl -H "Authorization: Bearer ${ACCESS_TOKEN}" "https://$GEN3_ENDPOINT/manifests/file/$FILENAME" || true)"
        MANIFEST_FILE="$(json_or_empty "${MANIFEST_FILE:-}")"
        [[ -z "$MANIFEST_FILE" ]] && { log "Empty manifest for $FILENAME"; continue; }
        printf '%s' "$MANIFEST_FILE" > "$FOLDER/manifest.json"
        log "Creating notebook for $FILENAME"
        cp ./template_manifest.json "$FOLDER/data.ipynb"
        populate_notebook "$MANIFEST_FILE" "$FOLDER"
      elif [[ "$base_dir" == "metadata" ]]; then
        METADATA_FILE="$(_curl -H "Authorization: Bearer ${ACCESS_TOKEN}" "https://$GEN3_ENDPOINT/manifests/metadata/$FILENAME" || true)"
        METADATA_FILE="$(json_or_empty "${METADATA_FILE:-}")"
        [[ -z "$METADATA_FILE" ]] && { log "Empty metadata for $FILENAME"; continue; }
        printf '%s' "$METADATA_FILE" > "$FOLDER/metadata.json"
      fi
    fi
  done < <(jq -c '.[]' <<<"$data_json")
}

populate() {
  log "querying manifest service at $GEN3_ENDPOINT/manifests and /metadata"
  local MANIFESTS METADATA
  local tries=0

  # Retry until both endpoints are reachable or shutdown
  while (( RUNNING )); do
    MANIFESTS="$(_curl -H "Authorization: Bearer ${ACCESS_TOKEN}" "https://$GEN3_ENDPOINT/manifests/" || true)"
    METADATA="$(_curl -H "Authorization: Bearer ${ACCESS_TOKEN}" "https://$GEN3_ENDPOINT/manifests/metadata" || true)"
    MANIFESTS="$(json_or_empty "${MANIFESTS:-}")"
    METADATA="$(json_or_empty "${METADATA:-}")"

    if [[ -n "$MANIFESTS" || -n "$METADATA" ]]; then
      log "successfully retrieved manifests and/or metadata for user"
      break
    fi

    ((tries++))
    log "Unable to get manifests/metadata (attempt ${tries}); retrying in 15s…"
    sleep 15 & wait $!
  done
  (( RUNNING )) || return 0

  if [[ -n "$MANIFESTS" ]]; then
    process_files "manifests" "$(jq -c '.manifests' <<<"$MANIFESTS")"
  fi
  if [[ -n "$METADATA" ]]; then
    process_files "metadata" "$(jq -c '.external_file_metadata' <<<"$METADATA")"
  fi

  chown -R 1000:100 /data
}

main() {
  : "${GEN3_ENDPOINT:?GEN3_ENDPOINT is required}"

  # Ensure log file exists early
  mkdir -p /data
  touch "$LOGFILE" || true

  apikeyfile
  get_access_token
  mount_hatchery_files

  if [[ ! -d "/data/${GEN3_ENDPOINT}" ]]; then
    log "Creating /data/$GEN3_ENDPOINT/ directory"
    mkdir -p "/data/${GEN3_ENDPOINT}/"
  fi

  log "Starting population loop…"
  while (( RUNNING )); do
    populate
    (( RUNNING )) || break

    # If the access token expired, refresh and continue
    local err="$(jq -r '.error // empty' <<<"${MANIFESTS:-}" 2>/dev/null || true)"
    if [[ "${err:-}" == "Please log in." ]]; then
      log "Session expired; fetching new access token…"
      get_access_token
      continue
    fi

    # Sleep 30s but remain interruptible by trap
    sleep 30 & wait $!
  done
}

main
