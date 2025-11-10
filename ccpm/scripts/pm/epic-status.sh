#!/bin/bash

echo "Getting status..."
echo ""
echo ""

epic_name="$1"

if [ -z "$epic_name" ]; then
  echo "❌ Please specify an epic name"
  echo "Usage: /pm:epic-status <epic-name>"
  echo ""
  echo "Available epics:"
  for dir in .claude/epics/*/; do
    [ -d "$dir" ] && echo "  • $(basename "$dir")"
  done
  exit 1
else
  # Show status for specific epic
  epic_dir=".claude/epics/$epic_name"
  epic_file="$epic_dir/epic.md"

  if [ ! -f "$epic_file" ]; then
    echo "❌ Epic not found: $epic_name"
    echo ""
    echo "Available epics:"
    for dir in .claude/epics/*/; do
      [ -d "$dir" ] && echo "  • $(basename "$dir")"
    done
    exit 1
  fi

  echo "📚 Epic Status: $epic_name"
  echo "================================"
  echo ""

  # Extract metadata
  status=$(grep "^status:" "$epic_file" | head -1 | sed 's/^status: *//')
  progress=$(grep "^progress:" "$epic_file" | head -1 | sed 's/^progress: *//')
  github=$(grep "^github:" "$epic_file" | head -1 | sed 's/^github: *//')

  # Count tasks
  total=0
  open=0
  closed=0
  blocked=0

  # Check if we should show git-aware status
  git_aware=false
  if git rev-parse --git-dir > /dev/null 2>&1; then
    git_aware=true
  fi

  # Use find to safely iterate over task files
  declare -a mismatches
  for task_file in "$epic_dir"/[0-9]*.md; do
    [ -f "$task_file" ] || continue
    ((total++))

    task_num=$(basename "$task_file" .md)
    task_status=$(grep "^status:" "$task_file" | head -1 | sed 's/^status: *//')
    deps=$(grep "^depends_on:" "$task_file" | head -1 | sed 's/^depends_on: *\[//' | sed 's/\]//')

    # Git-aware detection
    if [ "$git_aware" = true ]; then
      commits=$(git log --all --grep="Issue #$task_num:" --oneline 2>/dev/null | wc -l || echo "0")
      if [ "$commits" -gt 0 ]; then
        last_commit_rel=$(git log --all --grep="Issue #$task_num:" -1 --format="%ar" 2>/dev/null || echo "")
        merged_branch=$(git branch --merged main 2>/dev/null | grep -E "task-$task_num|issue-$task_num" | head -1 | xargs || echo "")

        # Determine git-detected status
        git_status="unknown"
        if [ -n "$merged_branch" ]; then
          git_status="completed"
        elif echo "$last_commit_rel" | grep -qE "week|month|year"; then
          git_status="completed"
        else
          git_status="in-progress"
        fi

        # Track mismatch
        if [ "$task_status" != "$git_status" ]; then
          mismatches+=("$task_num|$task_status|$git_status|$commits|$last_commit_rel")
        fi
      fi
    fi

    if [ "$task_status" = "closed" ] || [ "$task_status" = "completed" ]; then
      ((closed++))
    elif [ -n "$deps" ] && [ "$deps" != "depends_on:" ]; then
      ((blocked++))
    else
      ((open++))
    fi
  done

  # Display progress bar
  if [ $total -gt 0 ]; then
    percent=$((closed * 100 / total))
    filled=$((percent * 20 / 100))
    empty=$((20 - filled))

    echo -n "Progress: ["
    [ $filled -gt 0 ] && printf '%0.s█' $(seq 1 $filled)
    [ $empty -gt 0 ] && printf '%0.s░' $(seq 1 $empty)
    echo "] $percent%"
  else
    echo "Progress: No tasks created"
  fi

  echo ""
  echo "📊 Breakdown:"
  echo "  Total tasks: $total"
  echo "  ✅ Completed: $closed"
  echo "  🔄 Available: $open"
  echo "  ⏸️ Blocked: $blocked"

  [ -n "$github" ] && echo ""
  [ -n "$github" ] && echo "🔗 GitHub: $github"

  # Show git-aware mismatches if any
  if [ ${#mismatches[@]} -gt 0 ]; then
    echo ""
    echo "⚠️  Git-Detected Status Mismatches:"
    echo ""
    for mismatch in "${mismatches[@]}"; do
      IFS='|' read -r task_num current git commits last_rel <<< "$mismatch"
      echo "  Task $task_num:"
      echo "    Metadata: $current"
      echo "    Git-detected: $git ($commits commits, last: $last_rel)"
    done
    echo ""
    echo "💡 Run '/pm:detect-completion $epic_name' to auto-update from git state"
  fi
fi

exit 0
