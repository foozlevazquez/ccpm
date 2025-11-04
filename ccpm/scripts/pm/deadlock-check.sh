#!/bin/bash
# Check for potential deadlock conditions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/locking.sh"

echo "🔍 Deadlock Detection"
echo "====================="
echo ""

init_locks

# Check if any locks exist
if [ ! -d "$LOCK_DIR" ] || [ -z "$(ls -A $LOCK_DIR/*.lock 2>/dev/null)" ]; then
    echo "✅ No locks present - no deadlock possible"
    exit 0
fi

# Collect lock ownership
declare -A lock_owners  # lock -> agent_id
declare -A agent_locks  # agent_id -> list of locks

for lock_dir in "$LOCK_DIR"/*.lock; do
    [ -d "$lock_dir" ] || continue
    
    resource=$(basename "$lock_dir" .lock)
    
    if [ -f "$lock_dir/metadata.yaml" ]; then
        agent_id=$(grep "^agent_id:" "$lock_dir/metadata.yaml" | cut -d: -f2 | xargs)
        pid=$(grep "^pid:" "$lock_dir/metadata.yaml" | cut -d: -f2 | xargs)
        
        # Only count locks from alive processes
        if [ -n "$pid" ] && is_process_alive "$pid"; then
            lock_owners["$resource"]="$agent_id"
            agent_locks["$agent_id"]+="$resource "
        fi
    fi
done

deadlock_risk=0

# Check for agents holding multiple locks
for agent_id in "${!agent_locks[@]}"; do
    lock_count=$(echo "${agent_locks[$agent_id]}" | wc -w)
    
    if [ $lock_count -gt 1 ]; then
        echo "⚠️ Agent $agent_id holds $lock_count locks:"
        for lock in ${agent_locks[$agent_id]}; do
            echo "   - $lock"
        done
        echo "   Risk: Potential resource hoarding"
        ((deadlock_risk++))
        echo ""
    fi
done

# Check for long-held locks (> 2 minutes)
current_time=$(date +%s)
old_lock_threshold=120

for lock_dir in "$LOCK_DIR"/*.lock; do
    [ -d "$lock_dir" ] || continue
    
    resource=$(basename "$lock_dir" .lock)
    
    if [ -f "$lock_dir/metadata.yaml" ]; then
        acquired=$(grep "^acquired:" "$lock_dir/metadata.yaml" | cut -d' ' -f2-)
        
        if [ -n "$acquired" ]; then
            acquired_epoch=$(date -d "$acquired" +%s 2>/dev/null || echo 0)
            age=$((current_time - acquired_epoch))
            
            if [ $age -gt $old_lock_threshold ]; then
                agent_id=$(grep "^agent_id:" "$lock_dir/metadata.yaml" | cut -d: -f2 | xargs)
                echo "⚠️ Long-held lock:"
                echo "   Resource: $resource"
                echo "   Agent: $agent_id"
                echo "   Age: ${age}s"
                ((deadlock_risk++))
                echo ""
            fi
        fi
    fi
done

# Summary
if [ $deadlock_risk -eq 0 ]; then
    echo "✅ No deadlock risks detected"
else
    echo "⚠️ Found $deadlock_risk potential deadlock condition(s)"
    echo ""
    echo "Actions:"
    echo "  /pm:agents - View agent activity"
    echo "  /pm:locks - Check lock details"
    echo "  cleanup_stale_locks - Remove stale locks"
fi
