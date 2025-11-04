#!/bin/bash
# Agent Registry Library
# Provides agent registration, discovery, and coordination functions

# Configuration
HEARTBEAT_INTERVAL=60  # seconds
STALE_THRESHOLD=300    # 5 minutes in seconds

# Generate unique agent ID
generate_agent_id() {
    echo "agent-$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "$RANDOM-$RANDOM-$RANDOM")"
}

# Get current UTC timestamp
get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Register a new agent
# Usage: register_agent <epic_name> <work_stream>
register_agent() {
    local epic_name="$1"
    local work_stream="$2"
    local registry_file=".claude/epics/${epic_name}/agents.json"
    
    # Generate agent ID
    local agent_id=$(generate_agent_id)
    local timestamp=$(get_timestamp)
    
    # Create registry directory if needed
    mkdir -p "$(dirname "$registry_file")"
    
    # Initialize registry if it doesn't exist
    if [ ! -f "$registry_file" ]; then
        echo '{"agents":{}}' > "$registry_file"
    fi
    
    # Add agent to registry using jq
    if command -v jq &> /dev/null; then
        local temp_file=$(mktemp)
        jq --arg id "$agent_id" \
           --arg started "$timestamp" \
           --arg heartbeat "$timestamp" \
           --arg stream "$work_stream" \
           '.agents[$id] = {
               "started": $started,
               "last_heartbeat": $heartbeat,
               "status": "active",
               "work_stream": $stream,
               "files_locked": [],
               "commits": 0
           }' "$registry_file" > "$temp_file"
        mv "$temp_file" "$registry_file"
    else
        # Fallback: simple JSON append (less safe)
        echo "⚠️ jq not found. Using basic JSON handling."
    fi
    
    echo "$agent_id"
}

# Update agent heartbeat
# Usage: heartbeat <epic_name> <agent_id>
heartbeat() {
    local epic_name="$1"
    local agent_id="$2"
    local registry_file=".claude/epics/${epic_name}/agents.json"
    local timestamp=$(get_timestamp)
    
    if [ ! -f "$registry_file" ]; then
        echo "❌ Registry not found: $registry_file" >&2
        return 1
    fi
    
    if command -v jq &> /dev/null; then
        local temp_file=$(mktemp)
        jq --arg id "$agent_id" \
           --arg heartbeat "$timestamp" \
           '.agents[$id].last_heartbeat = $heartbeat |
            .agents[$id].status = "active"' "$registry_file" > "$temp_file"
        mv "$temp_file" "$registry_file"
    fi
}

# Unregister an agent
# Usage: unregister_agent <epic_name> <agent_id>
unregister_agent() {
    local epic_name="$1"
    local agent_id="$2"
    local registry_file=".claude/epics/${epic_name}/agents.json"
    
    if [ ! -f "$registry_file" ]; then
        return 0
    fi
    
    if command -v jq &> /dev/null; then
        local temp_file=$(mktemp)
        jq --arg id "$agent_id" \
           'del(.agents[$id])' "$registry_file" > "$temp_file"
        mv "$temp_file" "$registry_file"
    fi
}

# Get all active agents
# Usage: get_active_agents <epic_name>
get_active_agents() {
    local epic_name="$1"
    local registry_file=".claude/epics/${epic_name}/agents.json"
    
    if [ ! -f "$registry_file" ]; then
        echo "[]"
        return
    fi
    
    if command -v jq &> /dev/null; then
        jq -r '.agents | to_entries[] | 
               select(.value.status == "active") | 
               "\(.key) - \(.value.work_stream) - \(.value.last_heartbeat)"' \
               "$registry_file"
    fi
}

# Cleanup stale agents (no heartbeat in 5+ minutes)
# Usage: cleanup_stale_agents <epic_name>
cleanup_stale_agents() {
    local epic_name="$1"
    local registry_file=".claude/epics/${epic_name}/agents.json"
    
    if [ ! -f "$registry_file" ]; then
        return 0
    fi
    
    local current_time=$(date +%s)
    local stale_count=0
    
    if command -v jq &> /dev/null; then
        # Get agents with stale heartbeats
        local stale_agents=$(jq -r --arg threshold "$STALE_THRESHOLD" \
            '.agents | to_entries[] | 
             select(
                (now - (.value.last_heartbeat | fromdateiso8601)) > ($threshold | tonumber)
             ) | .key' "$registry_file")
        
        # Mark stale agents
        for agent_id in $stale_agents; do
            local temp_file=$(mktemp)
            jq --arg id "$agent_id" \
               '.agents[$id].status = "stale"' "$registry_file" > "$temp_file"
            mv "$temp_file" "$registry_file"
            ((stale_count++))
        done
    fi
    
    [ $stale_count -gt 0 ] && echo "Marked $stale_count agents as stale"
}

# Increment commit count for agent
# Usage: increment_commits <epic_name> <agent_id>
increment_commits() {
    local epic_name="$1"
    local agent_id="$2"
    local registry_file=".claude/epics/${epic_name}/agents.json"
    
    if [ ! -f "$registry_file" ]; then
        return 1
    fi
    
    if command -v jq &> /dev/null; then
        local temp_file=$(mktemp)
        jq --arg id "$agent_id" \
           '.agents[$id].commits += 1' "$registry_file" > "$temp_file"
        mv "$temp_file" "$registry_file"
    fi
}

# Add file to agent's locked files
# Usage: add_locked_file <epic_name> <agent_id> <file_path>
add_locked_file() {
    local epic_name="$1"
    local agent_id="$2"
    local file_path="$3"
    local registry_file=".claude/epics/${epic_name}/agents.json"
    
    if [ ! -f "$registry_file" ]; then
        return 1
    fi
    
    if command -v jq &> /dev/null; then
        local temp_file=$(mktemp)
        jq --arg id "$agent_id" \
           --arg file "$file_path" \
           '.agents[$id].files_locked += [$file] | 
            .agents[$id].files_locked |= unique' "$registry_file" > "$temp_file"
        mv "$temp_file" "$registry_file"
    fi
}

# Remove file from agent's locked files
# Usage: remove_locked_file <epic_name> <agent_id> <file_path>
remove_locked_file() {
    local epic_name="$1"
    local agent_id="$2"
    local file_path="$3"
    local registry_file=".claude/epics/${epic_name}/agents.json"
    
    if [ ! -f "$registry_file" ]; then
        return 1
    fi
    
    if command -v jq &> /dev/null; then
        local temp_file=$(mktemp)
        jq --arg id "$agent_id" \
           --arg file "$file_path" \
           '.agents[$id].files_locked -= [$file]' "$registry_file" > "$temp_file"
        mv "$temp_file" "$registry_file"
    fi
}

# Check if jq is installed
check_dependencies() {
    if ! command -v jq &> /dev/null; then
        echo "❌ jq is not installed. Agent registry requires jq for JSON manipulation." >&2
        echo "   Install with: sudo apt-get install jq (or brew install jq on macOS)" >&2
        return 1
    fi
    return 0
}
