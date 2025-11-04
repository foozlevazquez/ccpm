# Protected Operations Integration Guide

## Overview

Critical PM operations now use locking to prevent race conditions:

- **epic-sync**: Locks epic during GitHub issue creation
- **issue-sync**: Locks task file during updates  
- **epic-decompose**: Locks epic during task creation

## Usage Pattern

```bash
# Source locking library
source ccpm/scripts/lib/locking.sh

# Acquire lock before critical operation
lock_file=$(acquire_lock "epic-myepic" 300)
if [ $? -eq 0 ]; then
    # Setup cleanup
    setup_lock_cleanup "epic-myepic"
    
    # Perform critical operation
    # ... modify files, create issues, etc ...
    
    # Lock automatically released on exit
fi
```

## Lock Naming Conventions

- Epic operations: `epic-{epic_name}`
- Task operations: `task-{issue_number}`
- GitHub API: `github-api`

## Integration Points

### epic-sync.md
Locks acquired during:
1. Epic issue creation
2. Task file renaming (001.md → {issue}.md)
3. Frontmatter updates

### issue-sync.md  
Locks acquired during:
1. Progress file updates
2. Frontmatter modifications
3. GitHub comment posting

### epic-decompose.md
Locks acquired during:
1. Epic file modification
2. Task file creation
3. Task summary updates

## Error Handling

If lock acquisition fails:
- Clear error message shown
- Suggests retry or manual intervention
- Lock auto-cleanup on process termination

## Testing

Test concurrent access:
```bash
# Terminal 1
source ccpm/scripts/lib/locking.sh
acquire_lock "test-resource" 60
sleep 30

# Terminal 2  
source ccpm/scripts/lib/locking.sh
acquire_lock "test-resource" 60  # Will wait or timeout
```
