# CCPM Bidirectional Sync Enhancement

**Date**: 2025-11-10
**Status**: ✅ Implemented

## Summary

Enhanced the CCPM (Claude Code Project Manager) system to automatically synchronize issue descriptions between local `.claude/epics/` task files and GitHub issues, in addition to the existing progress comments functionality.

## Changes Made

### 1. Enhanced `/pm:issue-sync` Command

**Before**: Only posted progress updates as GitHub comments

**After**: Now performs **bidirectional sync**:
- ✅ Updates GitHub issue body/description with current task file content
- ✅ Posts progress updates as comments (existing functionality)
- ✅ Appends structured progress tracking section to issue body
- ✅ Preserves local-only sections (analysis, implementation details)
- ✅ Adds CCPM management marker to identify managed issues

**New Step Added** (Step 6):
```markdown
### 6. Sync Issue Body/Description
- Read local task file: `.claude/epics/{epic_name}/$ARGUMENTS.md`
- Format issue body with task description + progress tracking
- Update GitHub issue using: `gh issue edit $ARGUMENTS --body-file`
- Add marker: *This issue is managed by CCPM*
```

### 2. Enhanced `/pm:sync` Command

**Updated for bidirectional description sync**:

**Pull from GitHub** (Step 2):
- If GitHub issue body changed → update local task file body
- Preserve local frontmatter during updates
- Preserve local-only sections

**Push to GitHub** (Step 3):
- Update issue body with task description
- Post update comments for significant changes
- Sync both body and comments

## How It Works

### Issue Body Format

When syncing, the GitHub issue body includes:

```markdown
{Original task description from local file}

---
## 📊 Progress Tracking

**Status**: {status}
**Completion**: {completion}%
**Started**: {started_date}
**Last Updated**: {current_datetime}

### ✅ Completed Acceptance Criteria
- Criterion 1
- Criterion 2

### 🔄 In Progress
- Criterion 3

### ⏸️ Pending
- Criterion 4

---
*This issue is managed by CCPM. Last synced: {current_datetime}*
```

### Bidirectional Sync Flow

```
┌─────────────────┐          ┌──────────────────┐
│  Local Task     │  ←────→  │  GitHub Issue    │
│  (.md file)     │          │  (body + comments)│
└─────────────────┘          └──────────────────┘
        ↓                            ↓
    Frontmatter                  Metadata
    Description                  Description
    Details                      Progress tracking
    Analysis                     Comments
```

**Local → GitHub**: `/pm:issue-sync <number>`
- Updates issue body with task description
- Posts progress comment with details

**GitHub → Local**: `/pm:sync`
- Pulls issue body changes to local file
- Preserves local frontmatter and analysis

## Usage

### Sync Single Issue

```bash
# Sync issue #268 (push local changes to GitHub)
/pm:issue-sync 268
```

Output:
```
☁️ Synced updates to GitHub Issue #268

📝 Sync operations:
   ✅ Issue body updated with current task description
   ✅ Progress comment posted
   ✅ Local frontmatter updated

🔗 View on GitHub:
   Issue: gh issue view 268
   Web: https://github.com/org/repo/issues/268
```

### Sync All Issues (Bidirectional)

```bash
# Sync entire epic (pull from GitHub + push local changes)
/pm:sync 1st-reorg

# Sync all epics
/pm:sync
```

## Benefits

1. **Single Source of Truth**: Task descriptions stay synchronized between local files and GitHub
2. **Transparent Progress**: Stakeholders see current status directly in GitHub issues
3. **Audit Trail**: Progress updates posted as comments preserve history
4. **Collaboration**: External contributors can view/edit issue descriptions, changes sync back
5. **No Manual Updates**: Automated sync eliminates manual copy-paste
6. **Preserve Context**: Local analysis and implementation details remain local-only

## Technical Details

### Files Modified

- `.claude/commands/pm/issue-sync.md` - Added step 6 for issue body sync
- `.claude/commands/pm/sync.md` - Enhanced bidirectional body sync

### GitHub CLI Commands Used

```bash
# Update issue body
gh issue edit <number> --body-file <temp_file>

# Post progress comment
gh issue comment <number> --body-file <temp_file>

# Pull issue data
gh issue view <number> --json state,title,body,updatedAt
```

## Backward Compatibility

✅ Fully backward compatible:
- Existing progress comment functionality unchanged
- Issue body sync is additive (doesn't break existing workflows)
- Local files without GitHub URLs are unaffected
- Manual GitHub edits are preserved and can sync back

## Next Steps

Consider adding:
1. Conflict resolution UI for simultaneous local/GitHub changes
2. Selective sync (description-only or comments-only mode)
3. Sync dry-run mode to preview changes
4. Automated sync on git commit hooks
5. Sync notifications in GitHub Actions

## Testing

To test the enhancement:

```bash
# 1. Make local task file changes
vim .claude/epics/my-epic/123.md

# 2. Sync to GitHub
/pm:issue-sync 123

# 3. Verify issue updated
gh issue view 123 --web

# 4. Edit issue on GitHub

# 5. Pull changes back
/pm:sync my-epic

# 6. Verify local file updated
cat .claude/epics/my-epic/123.md
```

## References

- Original Commands: `.claude/commands/pm/issue-sync.md`, `.claude/commands/pm/sync.md`
- Backup: `.claude/commands/pm/issue-sync.md.backup`
- GitHub Operations: `.claude/ccpm/ccpm/rules/github-operations.md`
- Frontmatter Ops: `.claude/ccpm/ccpm/rules/frontmatter-operations.md`
