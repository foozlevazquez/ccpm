#!/bin/bash
# Merge agent worktree branches back to main epic branch

EPIC_NAME="${1:-}"

if [ -z "$EPIC_NAME" ]; then
    echo "Usage: epic-merge-agents <epic_name>"
    exit 1
fi

echo "🔀 Merging Agent Worktrees: $EPIC_NAME"
echo "======================================="
echo ""

# Find all agent branches for this epic
agent_branches=$(git branch -a | grep "epic/$EPIC_NAME/agent-" | sed 's/remotes\/origin\///' | sort -u)

if [ -z "$agent_branches" ]; then
    echo "No agent branches found for epic: $EPIC_NAME"
    exit 0
fi

# Switch to main epic branch
main_branch="epic/$EPIC_NAME"
git checkout "$main_branch" 2>/dev/null

if [ $? -ne 0 ]; then
    echo "❌ Main epic branch not found: $main_branch"
    exit 1
fi

echo "Main branch: $main_branch"
echo ""

# Merge each agent branch
merged_count=0
conflict_count=0

while IFS= read -r agent_branch; do
    agent_branch=$(echo "$agent_branch" | xargs)
    [ -z "$agent_branch" ] && continue
    
    echo "Merging: $agent_branch"
    
    # Try merge
    if git merge --no-ff "$agent_branch" -m "Merge agent work: $agent_branch"; then
        echo "  ✓ Merged successfully"
        ((merged_count++))
    else
        echo "  ❌ Merge conflict detected"
        git merge --abort
        ((conflict_count++))
    fi
    
    echo ""
done <<< "$agent_branches"

# Summary
echo "Merge Summary:"
echo "  Successful: $merged_count"
echo "  Conflicts: $conflict_count"

if [ $conflict_count -gt 0 ]; then
    echo ""
    echo "⚠️ Manual conflict resolution needed for $conflict_count branch(es)"
fi
