---
allowed-tools: Bash, Read, Write, Edit
---

# Detect Completion

Automatically detect task completion from git state and update task metadata accordingly.

## Usage
```
/pm:detect-completion [epic_name]
```

If `epic_name` provided, detect for that epic only. Otherwise, detect for all epics.

## Problem

Task status in `.claude/epics/` files becomes stale when:
- Work is completed in worktrees but metadata not updated
- Commits are made but task status remains "open"
- Branches are merged but tasks not marked completed

This command bridges the gap between actual git state and CCPM metadata.

## Instructions

### 1. Determine Scope

If epic name provided:
```bash
epic_name="$ARGUMENTS"
epic_dir=".claude/epics/$epic_name"
```

Otherwise, scan all epics:
```bash
for epic_dir in .claude/epics/*/; do
  # ... process each epic ...
done
```

### 2. For Each Task in Epic

Scan all task files:
```bash
for task_file in "$epic_dir"/[0-9]*.md; do
  [ -f "$task_file" ] || continue
  task_num=$(basename "$task_file" .md)

  # Read current metadata status
  current_status=$(grep "^status:" "$task_file" | head -1 | sed 's/^status: *//')

  # Detect actual status from git
  # ... (see step 3)
done
```

### 3. Detect Status from Git

Use multiple signals to determine actual task status:

#### Signal 1: Commit Count
```bash
# Search all branches and worktrees for commits mentioning this task
commit_count=$(git log --all --grep="Issue #$task_num:" --grep="Task $task_num:" --grep="#$task_num[^0-9]" --oneline 2>/dev/null | wc -l)
```

#### Signal 2: Last Commit Time
```bash
last_commit_date=$(git log --all --grep="Issue #$task_num:" --grep="Task $task_num:" -1 --format="%ci" 2>/dev/null)
last_commit_relative=$(git log --all --grep="Issue #$task_num:" -1 --format="%ar" 2>/dev/null)
```

#### Signal 3: Branch Merge Status
```bash
# Check if task branch exists and is merged
merged_branch=$(git branch --merged main 2>/dev/null | grep -E "task-$task_num|issue-$task_num|$task_num-" | head -1)
```

#### Signal 4: Worktree Analysis
```bash
# Check all worktrees for commits
while IFS= read -r worktree_path; do
  if [ -d "$worktree_path" ]; then
    wt_commits=$(cd "$worktree_path" && git log --grep="Issue #$task_num:" --oneline 2>/dev/null | wc -l)
    ((commit_count += wt_commits))
  fi
done < <(git worktree list | awk '{print $1}')
```

### 4. Determine Actual Status

Apply heuristics to determine what status should be:

```bash
actual_status="unknown"
confidence="low"

# High confidence: Branch merged
if [ -n "$merged_branch" ]; then
  actual_status="completed"
  confidence="high"
  reason="Branch '$merged_branch' merged to main"

# Medium confidence: Has commits but old
elif [ "$commit_count" -gt 0 ] && [ -n "$last_commit_relative" ]; then
  # Check if last commit was > 1 week ago
  if [[ "$last_commit_relative" =~ (week|month|year) ]]; then
    actual_status="completed"
    confidence="medium"
    reason="$commit_count commits, last $last_commit_relative"
  else
    actual_status="in-progress"
    confidence="high"
    reason="$commit_count commits, last $last_commit_relative"
  fi

# Low confidence: Has commits but very recent
elif [ "$commit_count" -gt 0 ]; then
  actual_status="in-progress"
  confidence="medium"
  reason="$commit_count commits found"

# No commits found
else
  actual_status="open"
  confidence="low"
  reason="No commits found"
fi
```

### 5. Compare and Report

Compare detected status with current metadata:

```bash
if [ "$current_status" != "$actual_status" ]; then
  echo "⚠️  Task $task_num: Status Mismatch Detected"
  echo "    Current metadata: $current_status"
  echo "    Git-detected: $actual_status"
  echo "    Confidence: $confidence"
  echo "    Reason: $reason"
  echo "    Commits: $commit_count"
  if [ -n "$last_commit_relative" ]; then
    echo "    Last commit: $last_commit_relative"
  fi
  echo ""

  # Add to update list
  tasks_to_update+=("$task_num|$task_file|$current_status|$actual_status|$confidence|$commit_count|$last_commit_date")
else
  echo "✅ Task $task_num: Status correct ($current_status)"
fi
```

### 6. Prompt for Updates

After scanning all tasks, prompt user to update mismatched ones:

```bash
if [ ${#tasks_to_update[@]} -eq 0 ]; then
  echo "✅ All task statuses are up to date!"
  exit 0
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Found ${#tasks_to_update[@]} task(s) with status mismatches"
echo ""
echo "Update options:"
echo "  [a] Update all high-confidence tasks automatically"
echo "  [i] Review and update interactively"
echo "  [n] Don't update (just report)"
echo ""
read -p "Choose action (a/i/n): " action
```

### 7. Update Task Metadata

For each task to update:

#### Option A: Auto-update high confidence
```bash
if [ "$action" = "a" ]; then
  for task_data in "${tasks_to_update[@]}"; do
    IFS='|' read -r task_num task_file current actual confidence commits last_commit <<< "$task_data"

    # Only update high confidence
    if [ "$confidence" = "high" ]; then
      update_task_status "$task_file" "$actual" "$commits" "$last_commit"
      echo "✅ Updated task $task_num: $current → $actual"
    else
      echo "⏭️  Skipped task $task_num (confidence: $confidence)"
    fi
  done
fi
```

#### Option I: Interactive update
```bash
if [ "$action" = "i" ]; then
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
    else
      echo "  ⏭️  Skipped"
    fi
  done
fi
```

### 8. Update Function

Helper function to update task frontmatter:

```bash
update_task_status() {
  local task_file="$1"
  local new_status="$2"
  local commit_count="$3"
  local last_commit_date="$4"

  # Get current datetime
  current_datetime=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Read existing frontmatter
  local temp_file=$(mktemp)

  # Update status and updated fields, add git metadata
  awk -v new_status="$new_status" \
      -v updated="$current_datetime" \
      -v commits="$commit_count" \
      -v last_commit="$last_commit_date" '
    BEGIN { in_frontmatter=0; frontmatter_ended=0 }
    /^---$/ {
      if (in_frontmatter == 0) {
        in_frontmatter = 1
        print
        next
      } else {
        frontmatter_ended = 1
        # Add git detection fields before ending frontmatter
        print "git_commits: " commits
        if (last_commit != "") {
          print "last_commit: " last_commit
        }
        print "detected_completion: true"
        print
        next
      }
    }
    in_frontmatter && !frontmatter_ended {
      if ($0 ~ /^status:/) {
        print "status: " new_status
      } else if ($0 ~ /^updated:/) {
        print "updated: " updated
      } else if ($0 !~ /^git_commits:/ && $0 !~ /^last_commit:/ && $0 !~ /^detected_completion:/) {
        print
      }
      next
    }
    { print }
  ' "$task_file" > "$temp_file"

  mv "$temp_file" "$task_file"
}
```

### 9. Output Summary

```
🔍 Completion Detection Complete

Scanned: 12 tasks
✅ Correct: 8 tasks
⚠️  Mismatches: 4 tasks

Updated:
  ✅ Task 268: open → completed (8 commits)
  ✅ Task 270: open → in-progress (3 commits)
  ⏭️  Task 271: Skipped (low confidence)

Epic progress recalculated:
  1st-reorg: 75% complete (9/12 tasks)
```

### 10. Recalculate Epic Progress

After updating tasks, recalculate epic completion:

```bash
# Count tasks
total=$(find "$epic_dir" -name "[0-9]*.md" | wc -l)
completed=$(grep -l "^status: completed" "$epic_dir"/[0-9]*.md 2>/dev/null | wc -l)
completed=$((completed + $(grep -l "^status: closed" "$epic_dir"/[0-9]*.md 2>/dev/null | wc -l)))

if [ $total -gt 0 ]; then
  progress=$((completed * 100 / total))

  # Update epic frontmatter
  epic_file="$epic_dir/epic.md"
  if [ -f "$epic_file" ]; then
    sed -i "s/^progress: .*/progress: $progress%/" "$epic_file"
    echo "Updated epic progress: $progress%"
  fi
fi
```

## Configuration

Behavior can be configured in `ccpm/settings.json`:

```json
{
  "git_detection": {
    "enabled": true,
    "auto_update_threshold": "high",
    "commit_patterns": [
      "Issue #%TASK%:",
      "Task %TASK%:",
      "#%TASK%[^0-9]"
    ],
    "branch_patterns": [
      "task-%TASK%",
      "issue-%TASK%",
      "%TASK%-*"
    ],
    "stale_threshold_days": 7
  }
}
```

## Error Handling

1. **No git repository**: Warn and exit
   ```bash
   if ! git rev-parse --git-dir > /dev/null 2>&1; then
     echo "❌ Not a git repository"
     exit 1
   fi
   ```

2. **Epic not found**: List available epics
   ```bash
   if [ ! -d "$epic_dir" ]; then
     echo "❌ Epic not found: $epic_name"
     echo "Available epics:"
     ls -1 .claude/epics/
     exit 1
   fi
   ```

3. **No tasks in epic**: Warn
   ```bash
   if [ $(ls "$epic_dir"/[0-9]*.md 2>/dev/null | wc -l) -eq 0 ]; then
     echo "ℹ️  No tasks found in epic: $epic_name"
     exit 0
   fi
   ```

## Integration

This command integrates with:
- `/pm:epic-status` - Show git-detected status alongside metadata
- `/pm:issue-sync` - Auto-detect before syncing to GitHub
- `/pm:epic-refresh` - Auto-detect when refreshing epic state

## Examples

### Example 1: Detect for specific epic
```bash
/pm:detect-completion 1st-reorg

🔍 Scanning epic: 1st-reorg

⚠️  Task 268: Status Mismatch Detected
    Current metadata: open
    Git-detected: completed
    Confidence: high
    Reason: 8 commits, last 2 hours ago

✅ Task 267: Status correct (completed)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Found 1 task(s) with status mismatches

Update? (y/n): y

✅ Updated task 268: open → completed
Updated epic progress: 100%
```

### Example 2: Detect for all epics
```bash
/pm:detect-completion

🔍 Scanning all epics...

Epic: 1st-reorg (2 tasks)
  ✅ All statuses correct

Epic: auth-system (5 tasks)
  ⚠️  3 mismatches found

[... interactive updates ...]
```

## Benefits

1. **Eliminates manual status updates** - Git is source of truth
2. **Accurate epic progress** - Reflects actual work done
3. **Better developer experience** - Focus on code, not metadata
4. **Audit trail** - Git commits prove completion
5. **Worktree-aware** - Detects work anywhere in repo
