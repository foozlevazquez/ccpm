#!/bin/bash
# GitHub API Rate Limit Coordination
# Prevents multiple agents from exceeding GitHub API limits

RATE_LIMIT_FILE=".claude/locks/github-rate-limit.json"
RATE_LIMIT_LOCK="github-api"
LOW_LIMIT_THRESHOLD=100

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/locking.sh"
source "$SCRIPT_DIR/atomic-ops.sh"

# Initialize rate limit file
init_rate_limit() {
    mkdir -p "$(dirname "$RATE_LIMIT_FILE")"
    
    if [ ! -f "$RATE_LIMIT_FILE" ]; then
        echo '{
  "remaining": 5000,
  "limit": 5000,
  "reset": "'$(date -u -d '+1 hour' +"%Y-%m-%dT%H:%M:%SZ")'",
  "last_updated": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"
}' > "$RATE_LIMIT_FILE"
    fi
}

# Fetch current rate limit from GitHub
update_rate_limit() {
    if ! command -v gh &> /dev/null; then
        echo "5000"
        return 0
    fi
    
    local rate_data=$(gh api rate_limit 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "5000"
        return 0
    fi
    
    local remaining=$(echo "$rate_data" | jq -r '.resources.core.remaining')
    local limit=$(echo "$rate_data" | jq -r '.resources.core.limit')
    local reset_epoch=$(echo "$rate_data" | jq -r '.resources.core.reset')
    local reset=$(date -u -d "@$reset_epoch" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
    
    echo "{
  \"remaining\": $remaining,
  \"limit\": $limit,
  \"reset\": \"$reset\",
  \"last_updated\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"
}" > "$RATE_LIMIT_FILE"
    
    echo "$remaining"
}

# Get current rate limit
check_rate_limit() {
    init_rate_limit
    jq -r '.remaining' "$RATE_LIMIT_FILE" 2>/dev/null || echo "5000"
}

# Reserve API calls
reserve_api_calls() {
    local count="${1:-1}"
    init_rate_limit
    
    local remaining=$(check_rate_limit)
    local new_remaining=$((remaining - count))
    
    jq --arg remaining "$new_remaining" \
       '.remaining = ($remaining | tonumber)' \
       "$RATE_LIMIT_FILE" > "$RATE_LIMIT_FILE.tmp"
    mv "$RATE_LIMIT_FILE.tmp" "$RATE_LIMIT_FILE"
    
    echo "$new_remaining"
}

# Wait if rate limit low
wait_for_rate_limit() {
    local required="${1:-1}"
    local remaining=$(update_rate_limit)
    
    if [ "$remaining" -lt "$required" ]; then
        echo "⚠️ Rate limit low: $remaining remaining" >&2
        sleep 10
    fi
}

# Safe GitHub API call wrapper
safe_gh_call() {
    local remaining=$(check_rate_limit)
    
    if [ "$remaining" -lt 10 ]; then
        wait_for_rate_limit 10
    fi
    
    reserve_api_calls 1
    "$@"
}
