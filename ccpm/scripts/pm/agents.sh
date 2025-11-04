#!/bin/bash
# View active agents in current epic

# Source the agent registry library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/agent-registry.sh"

# Check dependencies
check_dependencies || exit 1

echo "🤖 Agent Registry Status"
echo "======================="
echo ""

# Find all epics with registries
epics_found=0
total_agents=0

for registry in .claude/epics/*/agents.json; do
    [ -f "$registry" ] || continue
    
    epic_name=$(basename $(dirname "$registry"))
    epics_found=$((epics_found + 1))
    
    echo "Epic: $epic_name"
    echo "$(printf '─%.0s' {1..60})"
    
    # Check if registry has agents
    agent_count=$(jq '.agents | length' "$registry" 2>/dev/null || echo 0)
    
    if [ "$agent_count" -eq 0 ]; then
        echo "  No agents registered"
        echo ""
        continue
    fi
    
    total_agents=$((total_agents + agent_count))
    
    # Display agents with formatted table
    printf "%-25s %-20s %-10s %-20s\n" "AGENT ID" "WORK STREAM" "STATUS" "LAST HEARTBEAT"
    printf "%-25s %-20s %-10s %-20s\n" "$(printf '─%.0s' {1..25})" "$(printf '─%.0s' {1..20})" "$(printf '─%.0s' {1..10})" "$(printf '─%.0s' {1..20})"
    
    jq -r '.agents | to_entries[] | 
           "\(.key)|\(.value.work_stream // "none")|\(.value.status)|\(.value.last_heartbeat)"' \
           "$registry" | while IFS='|' read -r id stream status heartbeat; do
        # Truncate long IDs
        short_id=$(echo "$id" | cut -c1-25)
        short_stream=$(echo "$stream" | cut -c1-20)
        
        # Color status
        case "$status" in
            active)
                status_display="✅ $status"
                ;;
            stale)
                status_display="⚠️  $status"
                ;;
            dead)
                status_display="❌ $status"
                ;;
            *)
                status_display="   $status"
                ;;
        esac
        
        printf "%-25s %-20s %-10s %-20s\n" "$short_id" "$short_stream" "$status_display" "$heartbeat"
    done
    
    echo ""
    
    # Show summary stats
    active_count=$(jq '[.agents[] | select(.status == "active")] | length' "$registry")
    stale_count=$(jq '[.agents[] | select(.status == "stale")] | length' "$registry")
    total_commits=$(jq '[.agents[].commits] | add' "$registry")
    
    echo "  Summary:"
    echo "    Active: $active_count  |  Stale: $stale_count  |  Total Commits: ${total_commits:-0}"
    echo ""
done

if [ $epics_found -eq 0 ]; then
    echo "No agent registries found."
    echo ""
    echo "Agents are registered when you start work on an epic:"
    echo "  /pm:issue-start <issue_number>"
    echo ""
else
    echo "Total: $total_agents agents across $epics_found epic(s)"
    echo ""
    echo "Commands:"
    echo "  Clean up stale agents: source ccpm/scripts/lib/agent-registry.sh && cleanup_stale_agents <epic_name>"
fi
