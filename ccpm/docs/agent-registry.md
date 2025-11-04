# Agent Registry System

## Overview

The Agent Registry provides a coordination mechanism for multiple AI agents working on the same epic. Agents register themselves, maintain heartbeats, and can discover other active agents to avoid conflicts.

## Quick Start

```bash
source ccpm/scripts/lib/agent-registry.sh

# Register agent
agent_id=$(register_agent "my-epic" "database-layer")

# Maintain heartbeat
heartbeat "my-epic" "$agent_id"

# View agents
/pm:agents

# Cleanup
unregister_agent "my-epic" "$agent_id"
```

## API Reference

- `register_agent <epic> <work_stream>` - Register new agent
- `heartbeat <epic> <agent_id>` - Update heartbeat
- `unregister_agent <epic> <agent_id>` - Remove agent
- `get_active_agents <epic>` - List active agents
- `cleanup_stale_agents <epic>` - Mark stale agents
- `increment_commits <epic> <agent_id>` - Track commits
- `add_locked_file <epic> <agent_id> <file>` - Track file locks

## Dependencies

Requires `jq`: `sudo apt-get install jq` or `brew install jq`
