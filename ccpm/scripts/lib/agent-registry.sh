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

# ============================================================================
# Work Stream Ownership Tracking (Task #7)
# ============================================================================

# Claim a work stream
# Usage: claim_work_stream <epic_name> <agent_id> <stream_name> <files_pattern>
claim_work_stream() {
    local epic_name="$1"
    local agent_id="$2"
    local stream_name="$3"
    local files="$4"
    local registry_file=".claude/epics/${epic_name}/agents.json"
    local timestamp=$(get_timestamp)
    
    if [ ! -f "$registry_file" ]; then
        echo "❌ Registry not found: $registry_file" >&2
        return 1
    fi
    
    if command -v jq &> /dev/null; then
        # Check if stream already claimed
        local current_owner=$(jq -r --arg stream "$stream_name" \
            '.coordination.work_streams[$stream] // empty | .owner' "$registry_file" 2>/dev/null)
        
        if [ -n "$current_owner" ] && [ "$current_owner" != "$agent_id" ]; then
            echo "❌ Work stream '$stream_name' already claimed by $current_owner" >&2
            return 1
        fi
        
        # Check for file conflicts
        if check_file_conflicts "$epic_name" "$files" "$stream_name"; then
            echo "❌ File conflicts detected" >&2
            return 1
        fi
        
        # Claim the stream
        local temp_file=$(mktemp)
        jq --arg stream "$stream_name" \
           --arg agent "$agent_id" \
           --arg files_str "$files" \
           --arg started "$timestamp" \
           '.coordination.work_streams[$stream] = {
               "owner": $agent,
               "status": "in-progress",
               "files": ($files_str | split(",")),
               "started": $started
           }' "$registry_file" > "$temp_file"
        mv "$temp_file" "$registry_file"
        
        echo "✓ Claimed work stream: $stream_name"
    fi
}

# Release a work stream
# Usage: release_work_stream <epic_name> <agent_id> <stream_name>
release_work_stream() {
    local epic_name="$1"
    local agent_id="$2"
    local stream_name="$3"
    local registry_file=".claude/epics/${epic_name}/agents.json"
    
    if [ ! -f "$registry_file" ]; then
        return 0
    fi
    
    if command -v jq &> /dev/null; then
        # Verify ownership before releasing
        local owner=$(jq -r --arg stream "$stream_name" \
            '.coordination.work_streams[$stream].owner' "$registry_file" 2>/dev/null)
        
        if [ "$owner" != "$agent_id" ]; then
            echo "⚠️ Cannot release stream owned by $owner" >&2
            return 1
        fi
        
        local temp_file=$(mktemp)
        jq --arg stream "$stream_name" \
           'del(.coordination.work_streams[$stream])' "$registry_file" > "$temp_file"
        mv "$temp_file" "$registry_file"
    fi
}

# Check for file conflicts between work streams
# Usage: check_file_conflicts <epic_name> <new_files> [exclude_stream]
check_file_conflicts() {
    local epic_name="$1"
    local new_files="$2"
    local exclude_stream="${3:-}"
    local registry_file=".claude/epics/${epic_name}/agents.json"
    
    [ -f "$registry_file" ] || return 0
    
    if command -v jq &> /dev/null; then
        # Get all claimed files from other streams
        local claimed_files=$(jq -r --arg exclude "$exclude_stream" \
            '.coordination.work_streams | to_entries[] |
             select(.key != $exclude) |
             .value.files[]' "$registry_file" 2>/dev/null)
        
        # Convert new_files comma-separated to array
        IFS=',' read -ra new_file_arr <<< "$new_files"
        
        # Check for overlaps
        for new_file in "${new_file_arr[@]}"; do
            new_file=$(echo "$new_file" | xargs)  # trim whitespace
            
            while IFS= read -r claimed_file; do
                # Simple pattern matching (can be enhanced)
                if [[ "$new_file" == "$claimed_file" ]] || \
                   [[ "$new_file" == *"$claimed_file"* ]] || \
                   [[ "$claimed_file" == *"$new_file"* ]]; then
                    echo "Conflict: $new_file overlaps with claimed file $claimed_file" >&2
                    return 1
                fi
            done <<< "$claimed_files"
        done
    fi
    
    return 0
}

# Get owner of a work stream
# Usage: get_stream_owner <epic_name> <stream_name>
get_stream_owner() {
    local epic_name="$1"
    local stream_name="$2"
    local registry_file=".claude/epics/${epic_name}/agents.json"
    
    [ -f "$registry_file" ] || return 1
    
    if command -v jq &> /dev/null; then
        jq -r --arg stream "$stream_name" \
            '.coordination.work_streams[$stream].owner // empty' "$registry_file"
    fi
}

# List all work streams
# Usage: list_work_streams <epic_name>
list_work_streams() {
    local epic_name="$1"
    local registry_file=".claude/epics/${epic_name}/agents.json"
    
    [ -f "$registry_file" ] || {
        echo "No work streams registered"
        return 0
    }
    
    if command -v jq &> /dev/null; then
        echo "Work Streams:"
        jq -r '.coordination.work_streams | to_entries[] |
               "\(.key) - Owner: \(.value.owner) - Status: \(.value.status)"' \
               "$registry_file" 2>/dev/null || echo "No work streams"
    fi
}

# Mark work stream as completed
# Usage: complete_work_stream <epic_name> <agent_id> <stream_name>
complete_work_stream() {
    local epic_name="$1"
    local agent_id="$2"
    local stream_name="$3"
    local registry_file=".claude/epics/${epic_name}/agents.json"
    
    if [ ! -f "$registry_file" ]; then
        return 1
    fi
    
    if command -v jq &> /dev/null; then
        local temp_file=$(mktemp)
        jq --arg stream "$stream_name" \
           '.coordination.work_streams[$stream].status = "completed"' \
           "$registry_file" > "$temp_file"
        mv "$temp_file" "$registry_file"
    fi
}

# Initialize coordination section if not exists
# Usage: init_coordination <epic_name>
init_coordination() {
    local epic_name="$1"
    local registry_file=".claude/epics/${epic_name}/agents.json"
    
    [ -f "$registry_file" ] || {
        mkdir -p "$(dirname "$registry_file")"
        echo '{"agents":{},"coordination":{"work_streams":{}}}' > "$registry_file"
        return 0
    }
    
    if command -v jq &> /dev/null; then
        # Add coordination section if missing
        local has_coordination=$(jq 'has("coordination")' "$registry_file")
        if [ "$has_coordination" = "false" ]; then
            local temp_file=$(mktemp)
            jq '.coordination = {"work_streams": {}}' "$registry_file" > "$temp_file"
            mv "$temp_file" "$registry_file"
        fi
    fi
}
