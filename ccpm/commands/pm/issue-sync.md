---
allowed-tools: Bash, Read, Write, LS
---

# Issue Sync

Bidirectional sync between local task files and GitHub issues: updates issue body/description and posts progress comments.

## Usage
```
/pm:issue-sync <issue_number>
```

## Required Rules

**IMPORTANT:** Before executing this command, read and follow:
- `.claude/rules/datetime.md` - For getting real current date/time

## Preflight Checklist

Before proceeding, complete these validation steps.
Do not bother the user with preflight checks progress ("I'm not going to ..."). Just do them and move on.

0. **Repository Protection Check:**
   Follow `/rules/github-operations.md` - check remote origin:
   ```bash
   remote_url=$(git remote get-url origin 2>/dev/null || echo "")
   if [[ "$remote_url" == *"automazeio/ccpm"* ]]; then
     echo "❌ ERROR: Cannot sync to CCPM template repository!"
     echo "Update your remote: git remote set-url origin https://github.com/YOUR_USERNAME/YOUR_REPO.git"
     exit 1
   fi
   ```

1. **GitHub Authentication:**
   - Run: `gh auth status`
   - If not authenticated, tell user: "❌ GitHub CLI not authenticated. Run: gh auth login"

2. **Issue Validation:**
   - Run: `gh issue view $ARGUMENTS --json state`
   - If issue doesn't exist, tell user: "❌ Issue #$ARGUMENTS not found"
   - If issue is closed and completion < 100%, warn: "⚠️ Issue is closed but work incomplete"

3. **Local Updates Check:**
   - Check if `.claude/epics/*/updates/$ARGUMENTS/` directory exists
   - If not found, tell user: "❌ No local updates found for issue #$ARGUMENTS. Run: /pm:issue-start $ARGUMENTS"
   - Check if progress.md exists
   - If not, tell user: "❌ No progress tracking found. Initialize with: /pm:issue-start $ARGUMENTS"

4. **Check Last Sync:**
   - Read `last_sync` from progress.md frontmatter
   - If synced recently (< 5 minutes), ask: "⚠️ Recently synced. Force sync anyway? (yes/no)"
   - Calculate what's new since last sync

5. **Verify Changes:**
   - Check if there are actual updates to sync
   - If no changes, tell user: "ℹ️ No new updates to sync since {last_sync}"
   - Exit gracefully if nothing to sync

## Instructions

You are synchronizing local development progress to GitHub as issue comments for: **Issue #$ARGUMENTS**

### 1. Auto-Detect Completion from Git State

**Before syncing, check if git commits indicate task completion:**

Find the task file:
```bash
# Find task file in epics
task_file=$(find .claude/epics -name "$ARGUMENTS.md" -type f | head -1)
epic_name=$(dirname "$task_file" | xargs basename)
task_num="$ARGUMENTS"
```

Detect status from git commits:
```bash
# Count commits for this issue
commits=$(git log --all --grep="Issue #$task_num:" --grep="Task $task_num:" --oneline 2>/dev/null | wc -l)

# Get last commit info
last_commit_rel=$(git log --all --grep="Issue #$task_num:" -1 --format="%ar" 2>/dev/null || echo "")

# Check if branch merged
merged_branch=$(git branch --merged main 2>/dev/null | grep -E "task-$task_num|issue-$task_num" | head -1 | xargs || echo "")

# Read current metadata status
current_status=$(grep "^status:" "$task_file" | head -1 | sed 's/^status: *//')
```

Determine git-detected status:
```bash
git_status="unknown"

if [ -n "$merged_branch" ]; then
  git_status="completed"
  reason="Branch merged to main"
elif [ "$commits" -gt 0 ] && echo "$last_commit_rel" | grep -qE "week|month|year"; then
  git_status="completed"
  reason="$commits commits, last $last_commit_rel"
elif [ "$commits" -gt 0 ]; then
  git_status="in-progress"
  reason="$commits commits, active work"
fi
```

**Auto-update if mismatch detected:**
```bash
if [ "$current_status" != "$git_status" ] && [ "$git_status" != "unknown" ]; then
  echo "🔍 Git-detected status: $git_status ($reason)"
  echo "📝 Updating task status: $current_status → $git_status"

  # Update task frontmatter
  current_datetime=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Use sed or awk to update status and updated fields
  sed -i "s/^status: .*/status: $git_status/" "$task_file"
  sed -i "s/^updated: .*/updated: $current_datetime/" "$task_file"

  # Add git detection metadata if not present
  if ! grep -q "^git_commits:" "$task_file"; then
    sed -i "/^updated:/a git_commits: $commits" "$task_file"
  else
    sed -i "s/^git_commits: .*/git_commits: $commits/" "$task_file"
  fi

  echo "✅ Status auto-updated from git state"
fi
```

**Why this matters:**
- Ensures sync reflects actual work completion
- Eliminates manual status updates
- Git commits are the source of truth

### 2. Gather Local Updates
Collect all local updates for the issue:
- Read from `.claude/epics/{epic_name}/updates/$ARGUMENTS/`
- Check for new content in:
  - `progress.md` - Development progress
  - `notes.md` - Technical notes and decisions
  - `commits.md` - Recent commits and changes
  - Any other update files

### 3. Update Progress Tracking Frontmatter
Get current datetime: `date -u +"%Y-%m-%dT%H:%M:%SZ"`

Update the progress.md file frontmatter:
```yaml
---
issue: $ARGUMENTS
started: [preserve existing date]
last_sync: [Use REAL datetime from command above]
completion: [calculated percentage 0-100%]
---
```

### 4. Determine What's New
Compare against previous sync to identify new content:
- Look for sync timestamp markers
- Identify new sections or updates
- Gather only incremental changes since last sync

### 5. Format Update Comment
Create comprehensive update comment:

```markdown
## 🔄 Progress Update - {current_date}

### ✅ Completed Work
{list_completed_items}

### 🔄 In Progress
{current_work_items}

### 📝 Technical Notes
{key_technical_decisions}

### 📊 Acceptance Criteria Status
- ✅ {completed_criterion}
- 🔄 {in_progress_criterion}
- ⏸️ {blocked_criterion}
- □ {pending_criterion}

### 🚀 Next Steps
{planned_next_actions}

### ⚠️ Blockers
{any_current_blockers}

### 💻 Recent Commits
{commit_summaries}

---
*Progress: {completion}% | Synced from local updates at {timestamp}*
```

### 6. Post Progress Comment to GitHub
Use GitHub CLI to add comment:
```bash
gh issue comment $ARGUMENTS --body-file {temp_comment_file}
```

### 7. Sync Issue Body/Description
Update the GitHub issue body with current task file content:

**Read local task file**: `.claude/epics/{epic_name}/$ARGUMENTS.md`

**Format issue body** with structured sections:
```markdown
{task_file_body_content}

---
## 📊 Progress Tracking

**Status**: {status}
**Completion**: {completion}%
**Started**: {started_date}
**Last Updated**: {current_datetime}

### ✅ Completed Acceptance Criteria
{list_completed_criteria}

### 🔄 In Progress
{list_in_progress_criteria}

### ⏸️ Pending
{list_pending_criteria}

---
*This issue is managed by CCPM. Last synced: {current_datetime}*
```

**Update GitHub issue**:
```bash
# Create temporary file with formatted body
cat > /tmp/issue_body_$ARGUMENTS.md << 'EOF'
{formatted_body}
EOF

# Update the issue body
gh issue edit $ARGUMENTS --body-file /tmp/issue_body_$ARGUMENTS.md

# Clean up
rm /tmp/issue_body_$ARGUMENTS.md
```

**Important**:
- Preserve the original task description from the local file
- Append the progress tracking section
- Don't overwrite manually added GitHub-specific content (if any)
- Add a marker to indicate CCPM management

### 8. Update Local Task File
Get current datetime: `date -u +"%Y-%m-%dT%H:%M:%SZ"`

Update the task file frontmatter with sync information:
```yaml
---
name: [Task Title]
status: open
created: [preserve existing date]
updated: [Use REAL datetime from command above]
github: https://github.com/{org}/{repo}/issues/$ARGUMENTS
---
```

### 9. Handle Completion
If task is complete, update all relevant frontmatter:

**Task file frontmatter**:
```yaml
---
name: [Task Title]
status: closed
created: [existing date]
updated: [current date/time]
github: https://github.com/{org}/{repo}/issues/$ARGUMENTS
---
```

**Progress file frontmatter**:
```yaml
---
issue: $ARGUMENTS
started: [existing date]
last_sync: [current date/time]
completion: 100%
---
```

**Epic progress update**: Recalculate epic progress based on completed tasks and update epic frontmatter:
```yaml
---
name: [Epic Name]
status: in-progress
created: [existing date]
progress: [calculated percentage based on completed tasks]%
prd: [existing path]
github: [existing URL]
---
```

### 10. Completion Comment
If task is complete:
```markdown
## ✅ Task Completed - {current_date}

### 🎯 All Acceptance Criteria Met
- ✅ {criterion_1}
- ✅ {criterion_2}
- ✅ {criterion_3}

### 📦 Deliverables
- {deliverable_1}
- {deliverable_2}

### 🧪 Testing
- Unit tests: ✅ Passing
- Integration tests: ✅ Passing
- Manual testing: ✅ Complete

### 📚 Documentation
- Code documentation: ✅ Updated
- README updates: ✅ Complete

This task is ready for review and can be closed.

---
*Task completed: 100% | Synced at {timestamp}*
```

### 11. Output Summary
```
☁️ Synced updates to GitHub Issue #$ARGUMENTS

🔍 Git-aware detection:
   {If status was auto-updated, show: "✅ Status auto-updated: open → completed (8 commits)"}
   {Otherwise: "ℹ️ Status matches git state"}

📝 Sync operations:
   ✅ Issue body updated with current task description
   ✅ Progress comment posted
   ✅ Local frontmatter updated

📊 Update summary:
   Progress items: {progress_count}
   Technical notes: {notes_count}
   Commits referenced: {commit_count}

📊 Current status:
   Task completion: {task_completion}%
   Epic progress: {epic_progress}%
   Completed criteria: {completed}/{total}

🔗 View on GitHub:
   Issue: gh issue view $ARGUMENTS
   Comments: gh issue view $ARGUMENTS --comments
   Web: https://github.com/{org}/{repo}/issues/$ARGUMENTS
```

### 12. Frontmatter Maintenance
- Always update task file frontmatter with current timestamp
- Track completion percentages in progress files
- Update epic progress when tasks complete
- Maintain sync timestamps for audit trail

### 13. Incremental Sync Detection

**Prevent Duplicate Comments:**
1. Add sync markers to local files after each sync:
   ```markdown
   <!-- SYNCED: 2024-01-15T10:30:00Z -->
   ```
2. Only sync content added after the last marker
3. If no new content, skip sync with message: "No updates since last sync"

### 14. Comment Size Management

**Handle GitHub's Comment Limits:**
- Max comment size: 65,536 characters
- If update exceeds limit:
  1. Split into multiple comments
  2. Or summarize with link to full details
  3. Warn user: "⚠️ Update truncated due to size. Full details in local files."

### 15. Error Handling

**Common Issues and Recovery:**

1. **Network Error:**
   - Message: "❌ Failed to post comment: network error"
   - Solution: "Check internet connection and retry"
   - Keep local updates intact for retry

2. **Rate Limit:**
   - Message: "❌ GitHub rate limit exceeded"
   - Solution: "Wait {minutes} minutes or use different token"
   - Save comment locally for later sync

3. **Permission Denied:**
   - Message: "❌ Cannot comment on issue (permission denied)"
   - Solution: "Check repository access permissions"

4. **Issue Locked:**
   - Message: "⚠️ Issue is locked for comments"
   - Solution: "Contact repository admin to unlock"

### 16. Epic Progress Calculation

When updating epic progress:
1. Count total tasks in epic directory
2. Count tasks with `status: closed` in frontmatter
3. Calculate: `progress = (closed_tasks / total_tasks) * 100`
4. Round to nearest integer
5. Update epic frontmatter only if percentage changed

### 17. Post-Sync Validation

After successful sync:
- [ ] Verify comment posted on GitHub
- [ ] Confirm frontmatter updated with sync timestamp
- [ ] Check epic progress updated if task completed
- [ ] Validate no data corruption in local files

This creates a transparent audit trail of development progress that stakeholders can follow in real-time for Issue #$ARGUMENTS, while maintaining accurate frontmatter across all project files.
