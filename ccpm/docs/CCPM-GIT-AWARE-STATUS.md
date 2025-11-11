# CCPM Git-Aware Task Status Detection

**Date**: 2025-11-10
**Status**: 🚧 Proposed

## Problem Statement

Currently, CCPM task completion tracking has a critical workflow gap:

### Current Behavior
- Task status is **purely metadata-driven** from `.claude/epics/{epic}/task.md` frontmatter
- System reads `status:` field but **never checks actual git state**
- When work is completed in a worktree/branch, metadata **must be manually updated**
- No automatic detection of:
  - Commits made for a task
  - Work completed in worktrees
  - Branch merge status
  - Test completion

### The Problem Scenario

```bash
# Developer completes work in worktree
cd /home/ivan/git/epic-1st-reorg
git commit -m "Issue #268: Complete all acceptance criteria"
# ... 8 commits made for task 268 ...

# But task metadata remains stale
cat .claude/epics/1st-reorg/268.md
# status: open  ← Still says "open"!

# System reports task as incomplete
/pm:epic-status 1st-reorg
# Task 268: ⏸️ Open  ← Wrong! Work is done!
```

**Result**: User confusion, inaccurate status tracking, manual busywork.

## Proposed Solution

### Git-Aware Status Detection

Make CCPM intelligent by detecting task completion from actual git state:

#### Detection Signals

1. **Commit Analysis**
   - Scan git history for commits mentioning task number
   - Pattern: `Issue #268:`, `Task 268:`, `#268`
   - Count commits, check recency

2. **Worktree Detection**
   - Check `git worktree list` for epic worktrees
   - Scan worktree commits for task references
   - Detect when work exists but metadata is stale

3. **Branch Analysis**
   - Look for branches: `task-268`, `issue-268`, `268-feature-name`
   - Check branch ahead/behind status vs main
   - Detect merged branches (work complete)

4. **Completion Heuristics**
   - Has commits: **Work started**
   - Has recent commits (< 24h): **In progress**
   - Has commits + no recent activity: **Possibly complete**
   - Branch merged to main: **Completed**
   - Tests passing: **Validation complete**

## Implementation

### 1. New Command: `/pm:detect-completion`

Scans all tasks in an epic and auto-updates status based on git state.

**Usage:**
```bash
# Detect completion for specific epic
/pm:detect-completion 1st-reorg

# Detect for all epics
/pm:detect-completion
```

**Logic:**
```bash
#!/bin/bash
epic_name="$1"
epic_dir=".claude/epics/$epic_name"

# For each task file
for task_file in "$epic_dir"/[0-9]*.md; do
  task_num=$(basename "$task_file" .md)
  current_status=$(grep "^status:" "$task_file" | sed 's/^status: *//')

  # Scan all worktrees and branches for commits
  commits=$(git log --all --grep="Issue #$task_num:" --oneline | wc -l)
  last_commit=$(git log --all --grep="Issue #$task_num:" -1 --format="%ar")

  # Check if branch was merged
  merged=$(git branch --merged main | grep -E "task-$task_num|issue-$task_num")

  # Determine actual status
  if [ -n "$merged" ]; then
    actual_status="completed"
    confidence="high"
  elif [ "$commits" -gt 0 ] && [[ "$last_commit" == *"week"* ]]; then
    actual_status="completed"
    confidence="medium"
  elif [ "$commits" -gt 0 ]; then
    actual_status="in-progress"
    confidence="high"
  else
    actual_status="open"
    confidence="low"
  fi

  # Update if mismatch
  if [ "$current_status" != "$actual_status" ]; then
    echo "Task $task_num: Detected $actual_status ($commits commits, last: $last_commit)"
    echo "  Current metadata: $current_status"
    echo "  Should update? (y/n)"
    # ... update frontmatter ...
  fi
done
```

### 2. Enhanced `/pm:epic-status`

Modify to show git-detected status alongside metadata status.

**Output:**
```
📚 Epic Status: 1st-reorg
================================

Task 268: Extract Core Models
  Metadata: ⏸️ open
  Git State: ✅ completed (8 commits, last: 2 hours ago)
  ⚠️ Status mismatch detected! Run: /pm:detect-completion 1st-reorg
```

### 3. Auto-Update in `/pm:issue-sync`

**✅ IMPLEMENTED** - When syncing to GitHub, auto-detect completion BEFORE posting updates:

The `/pm:issue-sync` command now includes automatic git-aware detection as Step 1:

1. Scans git history for commits mentioning the issue
2. Determines actual status (completed/in-progress/open)
3. **Automatically updates task metadata if mismatch found**
4. Then proceeds with normal sync to GitHub

**No user prompt needed** - status is auto-corrected before sync.

Example:
```bash
/pm:issue-sync 268

# Output:
🔍 Git-detected status: completed (8 commits, last 2 hours ago)
📝 Updating task status: open → completed
✅ Status auto-updated from git state

☁️ Syncing to GitHub...
✅ Issue body updated
✅ Progress comment posted
🔒 Closing GitHub issue (task completed)
✅ GitHub issue #268 closed
```

**Benefit**: Just run `/pm:issue-sync` and the system:
1. Auto-detects completion from git commits
2. Updates local task status
3. Syncs progress to GitHub
4. **Automatically closes the issue** if completed

## Benefits

1. **Automatic Status Tracking** - No manual metadata updates needed
2. **Auto-Close on GitHub** - Issues automatically closed when work is complete
3. **Accurate Epic Progress** - Reflects actual work done, not stale metadata
4. **Developer Experience** - Focus on coding, not bookkeeping
5. **Audit Trail** - Git commits provide verifiable completion proof
6. **Worktree-Aware** - Detects work in any worktree/branch
7. **Full Automation** - One command does it all: detect, update, sync, close

## Implementation Phases

### Phase 1: Detection (Read-Only) ✅ COMPLETE
- ✅ Implement commit scanning
- ✅ Add git-aware status to `/pm:epic-status`
- ✅ Show mismatches as warnings

### Phase 2: Auto-Update (Interactive) ✅ COMPLETE
- ✅ Create `/pm:detect-completion` command
- ✅ Prompt before updating metadata
- ✅ Update frontmatter based on git state

### Phase 3: Full Automation ✅ COMPLETE
- ✅ Auto-detect in `/pm:issue-sync` (no prompt needed)
- ✅ Auto-update when confidence is high
- ⏳ Hook into CI/CD for continuous sync (future)

## Technical Details

### Git Commands Used

```bash
# Find all commits for a task
git log --all --grep="Issue #268:" --oneline

# Check if branch is merged
git branch --merged main | grep "task-268"

# Get commit count for task
git log --all --grep="Issue #268:" --oneline | wc -l

# Get last commit time for task
git log --all --grep="Issue #268:" -1 --format="%ar"

# List all worktrees
git worktree list

# Check commits in specific worktree
cd /path/to/worktree && git log --grep="Issue #268:"
```

### Frontmatter Updates

When auto-updating, preserve all fields and add detection metadata:

```yaml
---
name: Extract Core Models
status: completed  # ← Auto-updated from git
created: 2025-11-10T20:56:46Z
updated: 2025-11-10T23:30:00Z  # ← Auto-updated
github: https://github.com/foozlevazquez/ivacct-fastapi/issues/268
git_commits: 8  # ← New field
last_commit: 2025-11-10T23:15:00Z  # ← New field
detected_completion: true  # ← New field
detection_confidence: high  # ← New field
---
```

## Backward Compatibility

✅ Fully backward compatible:
- Detection is additive (doesn't break existing workflows)
- Manual status updates still work
- Only updates metadata when explicitly requested or auto-confirmed
- Can be disabled via config if needed

## Configuration

Add to `ccpm/settings.json`:

```json
{
  "git_detection": {
    "enabled": true,
    "auto_update": false,  // Prompt before updates
    "confidence_threshold": "medium",  // Only update if medium+ confidence
    "commit_patterns": [
      "Issue #%TASK%:",
      "Task %TASK%:",
      "#%TASK%"
    ],
    "branch_patterns": [
      "task-%TASK%",
      "issue-%TASK%",
      "%TASK%-*"
    ]
  }
}
```

## Testing

```bash
# 1. Create test scenario
cd /tmp/test-epic
git init
mkdir -p .claude/epics/test-epic
cat > .claude/epics/test-epic/1.md << 'EOF'
---
status: open
---
# Test Task 1
EOF

# 2. Make commits
git commit --allow-empty -m "Issue #1: Complete work"
git commit --allow-empty -m "Issue #1: Add tests"

# 3. Run detection
/pm:detect-completion test-epic
# Expected: Detects task 1 as completed (2 commits)

# 4. Verify status updated
cat .claude/epics/test-epic/1.md | grep "status:"
# Expected: status: completed
```

## References

- Original issue: Task status not reflecting git state
- Related: `.claude/ccpm/ccpm/scripts/pm/epic-status.sh`
- Related: `.claude/commands/pm/issue-sync.md`
- Related: `.claude/commands/pm/epic-status.md`

## Next Steps

1. ✅ Document the gap and proposed solution
2. ⏳ Implement `/pm:detect-completion` command
3. ⏳ Enhance `/pm:epic-status` with git-aware display
4. ⏳ Add auto-detection to `/pm:issue-sync`
5. ⏳ Create tests for detection logic
6. ⏳ Update documentation
