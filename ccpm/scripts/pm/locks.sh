#!/bin/bash
# View all active locks

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/locking.sh"

echo "🔒 Active Locks Status"
echo "======================"
echo ""

init_locks

# Check if any locks exist
if [ ! -d "$LOCK_DIR" ] || [ -z "$(ls -A $LOCK_DIR/*.lock 2>/dev/null)" ]; then
    echo "No active locks found."
    echo ""
    echo "Locks are created when agents acquire resources."
    echo "Use acquire_lock() from locking.sh library."
    exit 0
fi

# Display lock information
lock_count=0
stale_count=0
current_time=$(date +%s)

printf "%-30s %-15s %-10s %-20s %s\n" "RESOURCE" "AGENT ID" "PID" "ACQUIRED" "AGE"
printf "%-30s %-15s %-10s %-20s %s\n" "$(printf '─%.0s' {1..30})" "$(printf '─%.0s' {1..15})" "$(printf '─%.0s' {1..10})" "$(printf '─%.0s' {1..20})" "$(printf '─%.0s' {1..10})"

for lock_dir in "$LOCK_DIR"/*.lock; do
    [ -d "$lock_dir" ] || continue
    
    resource=$(basename "$lock_dir" .lock)
    ((lock_count++))
    
    if [ -f "$lock_dir/metadata.yaml" ]; then
        agent_id=$(grep "^agent_id:" "$lock_dir/metadata.yaml" | cut -d: -f2 | xargs | cut -c1-15)
        pid=$(grep "^pid:" "$lock_dir/metadata.yaml" | cut -d: -f2 | xargs)
        acquired=$(grep "^acquired:" "$lock_dir/metadata.yaml" | cut -d' ' -f2-)
        
        # Calculate age
        if [ -n "$acquired" ]; then
            acquired_epoch=$(date -d "$acquired" +%s 2>/dev/null || echo 0)
            age_seconds=$((current_time - acquired_epoch))
            age="${age_seconds}s"
        else
            age="unknown"
        fi
        
        # Check if process is alive
        if [ -n "$pid" ] && ! is_process_alive "$pid"; then
            status="⚠️ STALE"
            ((stale_count++))
        else
            status=""
        fi
        
        printf "%-30s %-15s %-10s %-20s %s %s\n" \
            "$resource" "$agent_id" "$pid" "$acquired" "$age" "$status"
    else
        printf "%-30s %-15s %-10s %-20s %s\n" \
            "$resource" "unknown" "-" "-" "-"
    fi
done

echo ""
echo "Summary:"
echo "  Total locks: $lock_count"
echo "  Stale locks: $stale_count"

if [ $stale_count -gt 0 ]; then
    echo ""
    echo "⚠️ Stale locks detected! Run cleanup:"
    echo "   source ccpm/scripts/lib/locking.sh && cleanup_stale_locks"
fi
