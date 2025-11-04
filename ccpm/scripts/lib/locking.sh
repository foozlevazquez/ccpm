#!/bin/bash
# File Locking Library for CCPM
# Provides distributed locking for concurrent agent operations

# Configuration
LOCK_DIR=".claude/locks"
LOCK_TIMEOUT=300  # 5 minutes default timeout
MAX_RETRIES=10
INITIAL_BACKOFF=1

# Ensure lock directory exists
init_locks() {
    mkdir -p "$LOCK_DIR"
    echo "*" > "$LOCK_DIR/.gitignore"
}

# Get current timestamp
get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Check if process is running
is_process_alive() {
    local pid="$1"
    kill -0 "$pid" 2>/dev/null
}

# Acquire a lock with exponential backoff
# Usage: acquire_lock <resource_name> [timeout_seconds]
acquire_lock() {
    local resource="$1"
    local timeout="${2:-$LOCK_TIMEOUT}"
    local lock_file="$LOCK_DIR/${resource}.lock"
    local agent_id="${AGENT_ID:-agent-$$}"
    local start_time=$(date +%s)
    local backoff=$INITIAL_BACKOFF
    local attempt=0
    
    init_locks
    
    while true; do
        # Try to create lock directory atomically
        if mkdir "$lock_file" 2>/dev/null; then
            # Lock acquired! Write metadata
            local timestamp=$(get_timestamp)
            local expires=$(date -u -d "+${timeout} seconds" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
            
            cat > "$lock_file/metadata.yaml" << EOF
---
agent_id: $agent_id
pid: $$
acquired: $timestamp
expires: $expires
operation: ${OPERATION:-unknown}
---
EOF
            echo "$lock_file"
            return 0
        fi
        
        # Lock exists, check if it's stale
        if [ -f "$lock_file/metadata.yaml" ]; then
            local lock_pid=$(grep "^pid:" "$lock_file/metadata.yaml" | cut -d: -f2 | tr -d ' ')
            
            # Check if owning process is dead
            if [ -n "$lock_pid" ] && ! is_process_alive "$lock_pid"; then
                echo "⚠️ Cleaning up stale lock from dead process $lock_pid" >&2
                rm -rf "$lock_file"
                continue
            fi
            
            # Check if lock expired
            local acquired=$(grep "^acquired:" "$lock_file/metadata.yaml" | cut -d' ' -f2-)
            if [ -n "$acquired" ]; then
                local acquired_epoch=$(date -d "$acquired" +%s 2>/dev/null || echo 0)
                local now_epoch=$(date +%s)
                local age=$((now_epoch - acquired_epoch))
                
                if [ $age -gt $timeout ]; then
                    echo "⚠️ Cleaning up expired lock (age: ${age}s)" >&2
                    rm -rf "$lock_file"
                    continue
                fi
            fi
        fi
        
        # Check timeout
        local elapsed=$(($(date +%s) - start_time))
        if [ $elapsed -ge $timeout ]; then
            echo "❌ Failed to acquire lock on $resource (timeout after ${elapsed}s)" >&2
            return 1
        fi
        
        # Exponential backoff with jitter
        ((attempt++))
        if [ $attempt -ge $MAX_RETRIES ]; then
            echo "❌ Failed to acquire lock on $resource (max retries)" >&2
            return 1
        fi
        
        local jitter=$((RANDOM % backoff))
        local sleep_time=$((backoff + jitter))
        echo "⏳ Lock held by another agent, retrying in ${sleep_time}s..." >&2
        sleep $sleep_time
        
        # Exponential backoff (cap at 32 seconds)
        backoff=$((backoff * 2))
        [ $backoff -gt 32 ] && backoff=32
    done
}

# Release a lock
# Usage: release_lock <resource_name>
release_lock() {
    local resource="$1"
    local lock_file="$LOCK_DIR/${resource}.lock"
    
    if [ ! -d "$lock_file" ]; then
        return 0  # Already released
    fi
    
    # Verify we own this lock
    if [ -f "$lock_file/metadata.yaml" ]; then
        local lock_pid=$(grep "^pid:" "$lock_file/metadata.yaml" | cut -d: -f2 | tr -d ' ')
        if [ "$lock_pid" != "$$" ]; then
            echo "⚠️ Warning: Attempting to release lock owned by PID $lock_pid" >&2
        fi
    fi
    
    rm -rf "$lock_file"
}

# Check if a lock exists
# Usage: check_lock <resource_name>
check_lock() {
    local resource="$1"
    local lock_file="$LOCK_DIR/${resource}.lock"
    
    if [ ! -d "$lock_file" ]; then
        echo "unlocked"
        return 1
    fi
    
    if [ -f "$lock_file/metadata.yaml" ]; then
        cat "$lock_file/metadata.yaml"
        return 0
    fi
    
    echo "locked (no metadata)"
    return 0
}

# Cleanup all stale locks
# Usage: cleanup_stale_locks
cleanup_stale_locks() {
    init_locks
    
    local cleaned=0
    for lock_file in "$LOCK_DIR"/*.lock; do
        [ -d "$lock_file" ] || continue
        
        if [ -f "$lock_file/metadata.yaml" ]; then
            local lock_pid=$(grep "^pid:" "$lock_file/metadata.yaml" | cut -d: -f2 | tr -d ' ')
            
            # Remove if process is dead
            if [ -n "$lock_pid" ] && ! is_process_alive "$lock_pid"; then
                echo "Removing stale lock: $(basename $lock_file)"
                rm -rf "$lock_file"
                ((cleaned++))
            fi
        fi
    done
    
    echo "Cleaned $cleaned stale locks"
}

# Setup cleanup trap
# Usage: setup_lock_cleanup <resource_name>
setup_lock_cleanup() {
    local resource="$1"
    trap "release_lock '$resource'" EXIT INT TERM
}

# Example usage guard
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    echo "File Locking Library"
    echo "Usage: source this file and call functions"
    echo ""
    echo "Functions:"
    echo "  acquire_lock <resource> [timeout]"
    echo "  release_lock <resource>"
    echo "  check_lock <resource>"
    echo "  cleanup_stale_locks"
    echo "  setup_lock_cleanup <resource>"
fi
