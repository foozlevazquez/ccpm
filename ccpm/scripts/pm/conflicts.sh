#!/bin/bash
# Detect file ownership conflicts between agents

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/agent-registry.sh"

echo "⚠️ File Ownership Conflict Detection"
echo "====================================="
echo ""

check_dependencies || exit 1

# Find all epics with registries
conflicts_found=0

for registry in .claude/epics/*/agents.json; do
    [ -f "$registry" ] || continue
    
    epic_name=$(basename $(dirname "$registry"))
    
    # Check if coordination section exists
    has_coordination=$(jq 'has("coordination")' "$registry" 2>/dev/null)
    if [ "$has_coordination" != "true" ]; then
        continue
    fi
    
    # Get all work streams
    streams=$(jq -r '.coordination.work_streams | keys[]' "$registry" 2>/dev/null)
    
    if [ -z "$streams" ]; then
        continue
    fi
    
    echo "Epic: $epic_name"
    echo "$(printf '─%.0s' {1..60})"
    
    # Build file ownership map
    declare -A file_owners
    
    while IFS= read -r stream; do
        owner=$(jq -r --arg s "$stream" '.coordination.work_streams[$s].owner' "$registry")
        files=$(jq -r --arg s "$stream" '.coordination.work_streams[$s].files[]' "$registry" 2>/dev/null)
        
        while IFS= read -r file; do
            [ -z "$file" ] && continue
            
            # Check if file already claimed
            if [ -n "${file_owners[$file]}" ]; then
                echo "  ⚠️ CONFLICT:"
                echo "     File: $file"
                echo "     Claimed by: ${file_owners[$file]} (stream: ${stream_map[$file]})"
                echo "     Also claimed by: $owner (stream: $stream)"
                ((conflicts_found++))
            else
                file_owners["$file"]="$owner"
                stream_map["$file"]="$stream"
            fi
        done <<< "$files"
    done <<< "$streams"
    
    if [ $conflicts_found -eq 0 ]; then
        echo "  ✓ No conflicts detected"
    fi
    echo ""
    
    # Clear arrays for next epic
    unset file_owners
    unset stream_map
done

if [ $conflicts_found -eq 0 ]; then
    echo "✅ No file ownership conflicts found across all epics"
else
    echo "⚠️ Found $conflicts_found conflict(s)"
    echo ""
    echo "Resolution steps:"
    echo "  1. Review work stream file assignments"
    echo "  2. Coordinate with other agents"
    echo "  3. Release overlapping work streams"
    echo "  4. Re-claim with non-overlapping files"
fi
