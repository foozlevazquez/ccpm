---
name: Multi-Agent Concurrency Expansion
status: open
created: 2025-11-04T04:16:21Z
progress: 0%
prd: N/A
github: https://github.com/foozlevazquez/ccpm/issues/1
---

# Epic: Multi-Agent Concurrency Expansion

## Overview

Enhance CCPM to support true multi-agent concurrent operations with proper coordination, locking, and conflict resolution mechanisms. Currently, the system assumes agents coordinate through advisory rules, but lacks enforcement and active coordination primitives needed for safe parallel execution.

## Problem Statement

The current CCPM system has several critical gaps when multiple AI agents work simultaneously:

### 1. No File-Level Locking Mechanism
Multiple agents can simultaneously modify the same files without coordination:
- `.claude/epics/*/epic.md` - Multiple agents updating task lists
- Task files (`001.md`, `002.md`) - Race conditions during rename operations
- Progress files - Concurrent updates to completion percentages

### 2. Epic Sync Race Conditions
The `/pm:epic-sync` command has multiple race-prone operations:
- Creating GitHub issues in parallel without coordination
- Renaming files from `001.md` → `{issue_number}.md` simultaneously
- Updating cross-references in `depends_on` and `conflicts_with` fields

### 3. Progress Tracking Conflicts
When multiple agents sync progress simultaneously:
- Frontmatter updates can overwrite each other
- Epic progress calculations become inconsistent
- `last_sync` timestamps may be incorrect

### 4. GitHub API Rate Limiting
No coordination for GitHub API calls across agents:
- Parallel issue creation can hit rate limits
- No shared rate limit tracking
- Failed operations don't coordinate retries

### 5. Missing Coordination Protocol
The `agent-coordination.md` rule file is purely advisory:
- No enforcement of file ownership
- Agents can't discover what others are doing
- No way to request exclusive access to shared resources

### 6. Worktree Conflicts
Multiple agents working in same worktree:
- Git commits can conflict
- No coordination of merge operations
- Branch state can become inconsistent

## Goals

1. **Data Safety**: Prevent data loss and corruption from concurrent operations
2. **Coordination**: Enable agents to discover and coordinate with each other
3. **Efficiency**: Maximize throughput while avoiding conflicts
4. **Observability**: Track agent activity and detect deadlocks
5. **Graceful Degradation**: Handle failures without blocking other agents

## Technical Approach

### Phase 1: Basic Safety (Prevents Data Loss)
Implement fundamental concurrency primitives to prevent data corruption.

### Phase 2: Coordination (Improves Efficiency)
Add active coordination mechanisms for agent discovery and resource management.

### Phase 3: Advanced (Maximizes Throughput)
Optimize for maximum parallel throughput with intelligent work distribution.

## Architecture

### File Locking System
```
.claude/locks/
├── epic-{name}.lock          # Epic-level lock
├── task-{issue}.lock         # Task-level lock
└── github-api.lock           # Rate limit coordination
```

Lock file format:
```yaml
---
agent_id: agent-{uuid}
pid: {process_id}
acquired: 2025-11-04T04:16:21Z
expires: 2025-11-04T04:21:21Z  # 5 minute timeout
operation: epic_sync
---
```

### Agent Registry
```
.claude/epics/{epic}/agents.json
```

Registry format:
```json
{
  "agents": {
    "agent-uuid-1": {
      "started": "2025-11-04T04:16:21Z",
      "last_heartbeat": "2025-11-04T04:18:21Z",
      "status": "active",
      "work_stream": "database-layer",
      "files_locked": ["001.md", "002.md"],
      "commits": 5
    }
  },
  "coordination": {
    "work_streams": {
      "database-layer": "agent-uuid-1",
      "api-layer": "agent-uuid-2"
    }
  }
}
```

### Version-Based Optimistic Locking
Add version field to frontmatter:
```yaml
---
name: Task Name
version: 3
updated: 2025-11-04T04:25:05Z
---
```

Before writing, verify version matches expected value.

### GitHub API Rate Limit Tracking
```
.claude/locks/github-rate-limit.json
```

Format:
```json
{
  "remaining": 4500,
  "limit": 5000,
  "reset": "2025-11-04T05:00:00Z",
  "last_updated": "2025-11-04T04:16:21Z"
}
```

## Success Criteria

### Phase 1
- [ ] File locking prevents concurrent modifications
- [ ] Atomic file operations (write-temp-rename pattern)
- [ ] Optimistic locking detects frontmatter conflicts
- [ ] Lock timeout and cleanup prevents deadlocks
- [ ] All critical operations protected by locks

### Phase 2
- [ ] Agent registration on epic start
- [ ] Heartbeat mechanism detects dead agents
- [ ] Work stream ownership prevents conflicts
- [ ] Shared rate limit prevents API throttling
- [ ] Agent discovery enables coordination

### Phase 3
- [ ] Multi-worktree per agent isolation
- [ ] Automatic conflict detection and reporting
- [ ] Work stealing balances load
- [ ] Coordinator merges agent branches
- [ ] Performance metrics and monitoring

## Implementation Plan

Three-phase approach prioritized by risk reduction and value delivery.

## Tasks Created

### Phase 1: Basic Safety (Prevents Data Loss)
- [ ] #2 - Implement File Locking System (parallel: true)
- [ ] #3 - Implement Atomic File Operations (parallel: true)
- [ ] #4 - Add Optimistic Locking to Frontmatter (parallel: false)
- [ ] #5 - Protect Critical Operations with Locks (parallel: false)

### Phase 2: Coordination (Improves Efficiency)
- [ ] #6 - Implement Agent Registry System (parallel: true)
- [ ] #7 - Implement Work Stream Ownership Tracking (parallel: false)
- [ ] #8 - Implement GitHub API Rate Limit Coordination (parallel: true)

### Phase 3: Advanced (Maximizes Throughput)
- [ ] #9 - Implement Multi-Worktree Per Agent (parallel: false)
- [ ] #10 - Add Monitoring and Debug Commands (parallel: true)

**Total tasks:** 9
**Parallel tasks:** 5 (can be worked on simultaneously)
**Sequential tasks:** 4 (have dependencies)
**Estimated total effort:** 44-56 hours
## Dependencies

- Existing CCPM command system
- Bash scripting for lock management
- GitHub CLI for API operations
- Git worktree functionality

## Risks & Mitigations

### Risk: Lock files become stale
**Mitigation**: Timeout-based expiration and cleanup scripts

### Risk: Agent crashes leave locks held
**Mitigation**: PID-based validation, lock cleanup on startup

### Risk: Clock skew between agents
**Mitigation**: Use monotonic timestamps, validate clock sync

### Risk: Performance overhead from locking
**Mitigation**: Fine-grained locks, read-write separation

### Risk: Complexity increase
**Mitigation**: Phased rollout, comprehensive testing

## Monitoring & Observability

### Metrics to Track
- Lock acquisition time
- Lock contention rate
- Agent uptime and crashes
- GitHub API usage
- Merge conflicts per epic

### Debug Tools
- Lock status viewer: `/pm:locks`
- Agent activity monitor: `/pm:agents`
- Conflict analyzer: `/pm:conflicts`

## Rollout Strategy

1. **Development**: Implement on test repository
2. **Testing**: Multi-agent stress testing
3. **Alpha**: Limited rollout with monitoring
4. **Beta**: Wider adoption with feedback
5. **GA**: Full release with documentation

## Documentation Updates

- Update AGENTS.md with coordination protocols
- Add CONCURRENCY.md with locking patterns
- Update command docs with new constraints
- Add troubleshooting guide for lock issues

## Future Enhancements

- Distributed locking with Redis/etcd
- Real-time agent communication (WebSockets)
- ML-based work distribution optimization
- Automatic deadlock detection and recovery
- Cross-repository coordination

---

*Epic created: 2025-11-04T04:16:21Z*
