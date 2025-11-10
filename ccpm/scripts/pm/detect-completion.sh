#!/bin/bash

# CCPM Git-Aware Task Completion Detection
# Automatically detects task completion from git state and updates metadata

set -e

epic_name="$1"

# Check if in git repo
if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo "❌ Not a git repository"
  exit 1
fi

# Function to update task frontmatter
update_task_status() {
  local task_file="$1"
  local new_status="$2"
  local commit_count="$3"
  local last_commit_date="$4"

  local current_datetime=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local temp_file=$(mktemp)

  awk -v new_status="$new_status" \
      -v updated="$current_datetime" \
      -v commits="$commit_count" \
      -v last_commit="$last_commit_date" '
    BEGIN { in_frontmatter=0; frontmatter_ended=0; added_git_fields=0 }
    /^---$/ {
      if (in_frontmatter == 0) {
        in_frontmatter = 1
        print
        next
      } else {
        # Add git detection fields before ending frontmatter if not already added
        if (!added_git_fields) {
          print "git_commits: " commits
          if (last_commit != "") {
            print "last_commit: " last_commit
          }
          print "detected_completion: true"
        }
        frontmatter_ended = 1
        print
        next
      }
    }
    in_frontmatter && !frontmatter_ended {
      if ($0 ~ /^status:/) {
        print "status: " new_status
      } else if ($0 ~ /^updated:/) {
        print "updated: " updated
      } else if ($0 ~ /^git_commits:/) {
        print "git_commits: " commits
        added_git_fields = 1
      } else if ($0 ~ /^last_commit:/) {
        if (last_commit != "") {
          print "last_commit: " last_commit
        }
      } else if ($0 ~ /^detected_completion:/) {
        print "detected_completion: true"
      } else {
        print
      }
      next
    }
    { print }
  ' "$task_file" > "$temp_file"

  mv "$temp_file" "$task_file"
}

# Function to detect task completion from git
detect_task_completion() {
  local task_num="$1"
  local task_file="$2"

  # Read current status
  local current_status=$(grep "^status:" "$task_file" | head -1 | sed 's/^status: *//')

  # Search for commits across all branches/worktrees
  local commit_count=0
  local commits_output=$(git log --all --grep="Issue #$task_num:" --grep="Task $task_num:" --grep="Task#$task_num" --oneline 2>/dev/null || true)
  commit_count=$(echo "$commits_output" | grep -c "." || echo "0")

  # Get last commit info
  local last_commit_date=$(git log --all --grep="Issue #$task_num:" -1 --format="%ci" 2>/dev/null || echo "")
  local last_commit_relative=$(git log --all --grep="Issue #$task_num:" -1 --format="%ar" 2>/dev/null || echo "")

  # Check if branch is merged
  local merged_branch=$(git branch --merged main 2>/dev/null | grep -E "task-$task_num|issue-$task_num|$task_num-" | head -1 | xargs || echo "")

  # Determine actual status
  local actual_status="unknown"
  local confidence="low"
  local reason=""

  if [ -n "$merged_branch" ]; then
    actual_status="completed"
    confidence="high"
    reason="Branch '$merged_branch' merged to main"
  elif [ "$commit_count" -gt 0 ] && [ -n "$last_commit_relative" ]; then
    # Check if last commit was > 1 week ago
    if echo "$last_commit_relative" | grep -qE "week|month|year"; then
      actual_status="completed"
      confidence="medium"
      reason="$commit_count commits, last $last_commit_relative"
    else
      actual_status="in-progress"
      confidence="high"
      reason="$commit_count commits, last $last_commit_relative"
    fi
  elif [ "$commit_count" -gt 0 ]; then
    actual_status="in-progress"
    confidence="medium"
    reason="$commit_count commits found"
  else
    actual_status="open"
    confidence="low"
    reason="No commits found"
  fi

  # Return as delimited string
  echo "$current_status|$actual_status|$confidence|$commit_count|$last_commit_date|$last_commit_relative|$reason"
}

# Main logic
if [ -z "$epic_name" ]; then
  echo "🔍 Scanning all epics..."
  echo ""

  for epic_dir in .claude/epics/*/; do
    [ -d "$epic_dir" ] || continue
    epic_name=$(basename "$epic_dir")

    # Skip if no tasks
    task_count=$(ls "$epic_dir"/[0-9]*.md 2>/dev/null | wc -l)
    if [ "$task_count" -eq 0 ]; then
      continue
    fi

    echo "Epic: $epic_name ($task_count tasks)"

    # Process this epic (call self with epic name)
    bash "$0" "$epic_name" --batch
    echo ""
  done
  exit 0
fi

# Process specific epic
epic_dir=".claude/epics/$epic_name"
epic_file="$epic_dir/epic.md"

if [ ! -d "$epic_dir" ]; then
  echo "❌ Epic not found: $epic_name"
  echo ""
  echo "Available epics:"
  for dir in .claude/epics/*/; do
    [ -d "$dir" ] && echo "  • $(basename "$dir")"
  done
  exit 1
fi

if [ ! -f "$epic_file" ]; then
  echo "❌ Epic file not found: $epic_file"
  exit 1
fi

# Check if in batch mode (called from parent)
batch_mode="false"
if [ "$2" = "--batch" ]; then
  batch_mode="true"
fi

if [ "$batch_mode" = "false" ]; then
  echo "🔍 Scanning epic: $epic_name"
  echo ""
fi

# Scan all tasks
declare -a tasks_to_update
correct_count=0
mismatch_count=0

for task_file in "$epic_dir"/[0-9]*.md; do
  [ -f "$task_file" ] || continue

  task_num=$(basename "$task_file" .md)

  # Detect completion
  result=$(detect_task_completion "$task_num" "$task_file")
  IFS='|' read -r current_status actual_status confidence commit_count last_commit_date last_commit_relative reason <<< "$result"

  # Compare
  if [ "$current_status" != "$actual_status" ]; then
    echo "⚠️  Task $task_num: Status Mismatch"
    echo "    Current: $current_status"
    echo "    Detected: $actual_status ($confidence confidence)"
    echo "    Reason: $reason"
    if [ "$commit_count" -gt 0 ]; then
      echo "    Commits: $commit_count"
      [ -n "$last_commit_relative" ] && echo "    Last commit: $last_commit_relative"
    fi
    echo ""

    tasks_to_update+=("$task_num|$task_file|$current_status|$actual_status|$confidence|$commit_count|$last_commit_date")
    ((mismatch_count++))
  else
    if [ "$batch_mode" = "false" ]; then
      echo "✅ Task $task_num: Correct ($current_status)"
    fi
    ((correct_count++))
  fi
done

# Summary
if [ "$batch_mode" = "true" ]; then
  if [ $mismatch_count -gt 0 ]; then
    echo "  ⚠️  $mismatch_count mismatch(es) found"
  else
    echo "  ✅ All statuses correct"
  fi
  exit 0
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Summary:"
echo "  ✅ Correct: $correct_count"
echo "  ⚠️  Mismatches: $mismatch_count"
echo ""

# If no mismatches, done
if [ ${#tasks_to_update[@]} -eq 0 ]; then
  echo "✅ All task statuses are up to date!"
  exit 0
fi

# Prompt for updates
echo "Update options:"
echo "  [a] Update all high-confidence tasks automatically"
echo "  [i] Review and update interactively"
echo "  [n] Don't update (just report)"
echo ""
read -p "Choose action (a/i/n): " action

case "$action" in
  a)
    echo ""
    echo "Updating high-confidence tasks..."
    updated=0
    for task_data in "${tasks_to_update[@]}"; do
      IFS='|' read -r task_num task_file current actual confidence commits last_commit <<< "$task_data"

      if [ "$confidence" = "high" ]; then
        update_task_status "$task_file" "$actual" "$commits" "$last_commit"
        echo "✅ Updated task $task_num: $current → $actual"
        ((updated++))
      else
        echo "⏭️  Skipped task $task_num (confidence: $confidence)"
      fi
    done
    echo ""
    echo "Updated $updated task(s)"
    ;;

  i)
    echo ""
    updated=0
    for task_data in "${tasks_to_update[@]}"; do
      IFS='|' read -r task_num task_file current actual confidence commits last_commit <<< "$task_data"

      echo ""
      echo "Task $task_num:"
      echo "  Current: $current"
      echo "  Detected: $actual ($confidence confidence)"
      echo "  Commits: $commits"
      read -p "  Update? (y/n): " update

      if [ "$update" = "y" ]; then
        update_task_status "$task_file" "$actual" "$commits" "$last_commit"
        echo "  ✅ Updated"
        ((updated++))
      else
        echo "  ⏭️  Skipped"
      fi
    done
    echo ""
    echo "Updated $updated task(s)"
    ;;

  n|*)
    echo "Skipping updates"
    exit 0
    ;;
esac

# Recalculate epic progress if any updates made
if [ "${updated:-0}" -gt 0 ]; then
  echo ""
  echo "Recalculating epic progress..."

  total=$(find "$epic_dir" -name "[0-9]*.md" | wc -l)
  completed=$(grep -l "^status: completed" "$epic_dir"/[0-9]*.md 2>/dev/null | wc -l || echo "0")
  closed=$(grep -l "^status: closed" "$epic_dir"/[0-9]*.md 2>/dev/null | wc -l || echo "0")
  completed=$((completed + closed))

  if [ $total -gt 0 ]; then
    progress=$((completed * 100 / total))

    # Update epic frontmatter
    if [ -f "$epic_file" ]; then
      # Use sed to update progress
      sed -i "s/^progress: .*/progress: $progress%/" "$epic_file"
      echo "✅ Updated epic progress: $progress% ($completed/$total tasks)"
    fi
  fi
fi

echo ""
echo "🔍 Detection complete!"
