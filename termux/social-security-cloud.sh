#!/data/data/com.termux/files/usr/bin/bash
# Secure interactive client for the Social Security Cloud Pro REST API.
# Credentials and access tokens are kept in memory only; nothing is written to disk.
set -Eeuo pipefail

APP_NAME="Social Security Cloud Pro"
API_BASE_URL="${SOCIAL_SECURITY_API_URL:-}"
API_PREFIX="/api/v1"
ACCESS_TOKEN=""
CURL_BIN="$(command -v curl || true)"
JQ_BIN="$(command -v jq || true)"

cleanup() {
  ACCESS_TOKEN=""
}
trap cleanup EXIT INT TERM

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

require_dependencies() {
  [[ -n "$CURL_BIN" ]] || fail "curl is required. Install it with: pkg install curl"
  [[ -n "$JQ_BIN" ]] || fail "jq is required. Install it with: pkg install jq"
}

configure_server() {
  if [[ -z "$API_BASE_URL" ]]; then
    read -r -p "Cloud API base URL (https://...): " API_BASE_URL
  fi
  API_BASE_URL="${API_BASE_URL%/}"
  [[ "$API_BASE_URL" =~ ^https://[^[:space:]]+$ ]] || fail "Use a valid HTTPS URL, for example https://api.example.com. HTTP is not accepted."
}

# Prints the response body and stores the HTTP status in RESPONSE_STATUS.
http_request() {
  local method="$1" path="$2" payload="${3:-}" auth="${4:-yes}" raw
  local -a args
  args=(--silent --show-error --connect-timeout 10 --max-time 30 --request "$method" \
        --header 'Accept: application/json' --header 'Content-Type: application/json')
  if [[ "$auth" == yes ]]; then
    args+=(--header "Authorization: Bearer ${ACCESS_TOKEN}")
  fi
  if [[ -n "$payload" ]]; then
    args+=(--data-binary "$payload")
  fi

  if ! raw="$("$CURL_BIN" "${args[@]}" --write-out $'\n%{http_code}' "${API_BASE_URL}${API_PREFIX}${path}")"; then
    RESPONSE_STATUS="000"
    printf '%s' '{"error":"Network request failed. Check connectivity and the API URL."}'
    return 0
  fi
  RESPONSE_STATUS="${raw##*$'\n'}"
  raw="${raw%$'\n'*}"
  printf '%s' "$raw"
}

show_response() {
  local body="$1" status="$2"
  if [[ "$status" =~ ^2[0-9][0-9]$ ]]; then
    if ! printf '%s' "$body" | "$JQ_BIN" . 2>/dev/null; then
      printf 'The server returned a successful response that was not valid JSON.\n'
    fi
    return 0
  fi
  printf 'Request failed (HTTP %s).\n' "$status" >&2
  if [[ -n "$body" ]] && printf '%s' "$body" | "$JQ_BIN" -e . >/dev/null 2>&1; then
    printf '%s' "$body" | "$JQ_BIN" -r '(.message // .error // .detail // "No error details provided") | if type == "string" then . else tostring end' >&2
    printf '\n' >&2
  else
    printf 'No readable error details were returned.\n' >&2
  fi
  return 1
}

login() {
  local username password payload body token status
  printf '\nSign in using an account provisioned by your service administrator.\n'
  read -r -p 'Email or username: ' username
  read -r -s -p 'Password: ' password
  printf '\n'
  payload="$("$JQ_BIN" -cn --arg username "$username" --arg password "$password" \
    '{username:$username,password:$password}')"
  password=""
  body="$(http_request POST '/auth/login' "$payload" no)"
  status="$RESPONSE_STATUS"
  payload=""
  if [[ ! "$status" =~ ^2[0-9][0-9]$ ]]; then
    show_response "$body" "$status" || true
    return 1
  fi
  token="$(printf '%s' "$body" | "$JQ_BIN" -er '.accessToken // .access_token // empty' 2>/dev/null || true)"
  if [[ -z "$token" ]]; then
    printf 'Login response did not contain an access token; no authenticated session was started.\n' >&2
    return 1
  fi
  ACCESS_TOKEN="$token"
  token=""
  printf 'Signed in. The access token is held in memory only.\n'
}

get_and_display() {
  local method="$1" path="$2" label="$3" body status
  printf '\n%s\n' "$label"
  body="$(http_request "$method" "$path")"
  status="$RESPONSE_STATUS"
  show_response "$body" "$status"
}

account_lookup() {
  local reference encoded body status
  read -r -p 'Facebook profile/account reference (URL or public ID): ' reference
  [[ -n "$reference" ]] || { printf 'Reference cannot be empty.\n' >&2; return 1; }
  # --get/--data-urlencode performs URL encoding; the value is not interpreted as shell code.
  encoded="$("$JQ_BIN" -rn --arg value "$reference" '$value|@uri')"
  get_and_display GET "/security/lookups?reference=${encoded}" 'Authorized security lookup response:'
}

report_history() {
  get_and_display GET '/reports' 'Report history (only reports recorded by the connected service):'
}

telegram_status() {
  get_and_display GET '/telegram/bots/status' 'Telegram bot status (as reported by the connected backend):'
}

api_status() {
  get_and_display GET '/integrations/status' 'Configured integration status:'
}

dashboard_stats() {
  get_and_display GET '/admin/dashboard/stats' 'Dashboard statistics (server-provided values only):'
}

menu() {
  local choice
  while [[ -n "$ACCESS_TOKEN" ]]; do
    printf '\n--- %s ---\n' "$APP_NAME"
    printf '1) Dashboard statistics\n'
    printf '2) Facebook security lookup\n'
    printf '3) Report history\n'
    printf '4) Telegram bot status\n'
    printf '5) API/integration status\n'
    printf '6) Log out\n'
    read -r -p 'Choose an option: ' choice
    case "$choice" in
      1) dashboard_stats || true ;;
      2) account_lookup || true ;;
      3) report_history || true ;;
      4) telegram_status || true ;;
      5) api_status || true ;;
      6) break ;;
      *) printf 'Choose a number from 1 to 6.\n' ;;
    esac
  done
}

main() {
  require_dependencies
  configure_server
  while true; do
    if login; then
      menu
      if [[ -n "$ACCESS_TOKEN" ]]; then
        local body status
        body="$(http_request POST '/auth/logout' '{}' yes)"
        status="$RESPONSE_STATUS"
        if [[ "$status" =~ ^2[0-9][0-9]$ ]]; then
          printf 'Server confirmed logout.\n'
        else
          printf 'Server logout could not be confirmed (HTTP %s); clearing the local in-memory token.\n' "$status" >&2
        fi
        ACCESS_TOKEN=""
      fi
    else
      printf 'Sign-in failed or was rejected.\n' >&2
    fi
    local again
    read -r -p 'Try signing in again? [y/N]: ' again
    [[ "$again" =~ ^[Yy]$ ]] || break
  done
}

main "$@"
