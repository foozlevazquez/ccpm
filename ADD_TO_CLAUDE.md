# CCPM Integration Instructions for AI Assistants

**For:** Claude, Codex, GitHub Copilot, or any AI coding assistant  
**Purpose:** Enable CCPM (Claude Code Project Manager) in this repository  
**Last Updated:** 2025-11-04

---

## What is CCPM?

CCPM is a project management system designed specifically for AI-assisted development. It provides:

- **Epic & Task Management**: Break down features into manageable tasks
- **Multi-Agent Coordination**: Multiple AI agents can work in parallel safely
- **Git Worktree Integration**: Isolated workspaces for each epic
- **Concurrency Safety**: File locking, atomic operations, optimistic locking
- **Progress Tracking**: Real-time visibility into work status
- **GitHub Integration**: Automatic issue creation and sync

---

## Prerequisites

Before installing CCPM, ensure you have:

```bash
# Required tools
git --version        # Git 2.20+
gh --version         # GitHub CLI
jq --version         # JSON processor

# Optional but recommended
uuidgen --version    # For unique ID generation
```

Install missing tools:
```bash
# Ubuntu/Debian
sudo apt-get install git gh jq uuid-runtime

# macOS
brew install git gh jq
```

---

## Installation Steps

### 1. Clone CCPM Template

```bash
# Clone the CCPM template repository
git clone https://github.com/automazeio/ccpm.git ccpm-template
# Or fork it: gh repo fork automazeio/ccpm --clone
```

### 2. Copy CCPM into Your Repository

```bash
# Navigate to your project
cd /path/to/your/project

# Copy CCPM structure
cp -r /path/to/ccpm-template/ccpm ./
cp -r /path/to/ccpm-template/.claude ./

# Copy documentation (optional)
cp /path/to/ccpm-template/README.md ./CCPM_README.md
```

### 3. Initialize CCPM Structure

```bash
# Create required directories
mkdir -p .claude/epics
mkdir -p .claude/locks
mkdir -p ccpm/commands/pm
mkdir -p ccpm/scripts/{lib,pm}

# Set up gitignore for lock files
echo "" >> .gitignore
echo "# CCPM lock files" >> .gitignore
echo ".claude/locks/*.lock" >> .gitignore
echo ".claude/locks/github-rate-limit.json" >> .gitignore

# Make scripts executable
chmod +x ccpm/scripts/lib/*.sh
chmod +x ccpm/scripts/pm/*.sh
```

### 4. Configure GitHub Integration

```bash
# Authenticate GitHub CLI
gh auth login

# Set repository as default
gh repo set-default

# Enable issues if not already enabled
gh repo edit --enable-issues
```

### 5. Verify Installation

```bash
# Test CCPM commands availability
ls ccpm/commands/pm/

# Source a library to verify
source ccpm/scripts/lib/locking.sh
echo "✓ CCPM libraries loaded successfully"
```

---

## Quick Start Guide

### Initialize Your First Epic

1. **Create an epic from a feature idea:**

```
/pm:prd-parse my-feature-name

# Provide PRD content when prompted
```

2. **Decompose into tasks:**

```
/pm:epic-decompose my-feature-name
```

3. **Sync to GitHub:**

```
/pm:epic-sync my-feature-name
```

4. **Start working:**

```
/pm:epic-start my-feature-name
```

### One-Shot Epic Creation

For faster workflow:

```
/pm:epic-oneshot my-feature-name
```

This runs decompose + sync automatically.

---

## Available Commands

### Epic Management
- `/pm:prd-parse <name>` - Create epic from PRD
- `/pm:epic-decompose <name>` - Break into tasks
- `/pm:epic-sync <name>` - Sync to GitHub
- `/pm:epic-start <name>` - Create worktree and begin work
- `/pm:epic-oneshot <name>` - Decompose + sync in one step
- `/pm:epic-show <name>` - View epic details
- `/pm:epic-merge-agents <name>` - Merge agent worktrees

### Task Management
- `/pm:issue-start <number>` - Start work on a task
- `/pm:issue-sync <number>` - Sync task to GitHub

### Monitoring & Debug
- `/pm:agents` - View active agents and status
- `/pm:locks` - Show all active locks
- `/pm:conflicts` - Detect file ownership conflicts
- `/pm:deadlock-check` - Find potential deadlocks

---

## Multi-Agent Workflow

### Register as an Agent

```bash
source ccpm/scripts/lib/agent-registry.sh

# Register yourself
agent_id=$(register_agent "epic-name" "your-work-stream")

# Maintain heartbeat during work
heartbeat "epic-name" "$agent_id"

# Cleanup when done
unregister_agent "epic-name" "$agent_id"
```

### Monitor Activity

```bash
/pm:agents           # View all active agents
/pm:locks            # Check lock status
/pm:conflicts        # Detect file conflicts
/pm:deadlock-check   # Find deadlocks
```

---

## File Structure

After installation:

```
your-project/
├── .claude/
│   ├── epics/              # Epic and task files
│   └── locks/              # Lock files (gitignored)
├── ccpm/
│   ├── commands/pm/        # PM command definitions
│   ├── scripts/
│   │   ├── lib/            # Shared libraries
│   │   └── pm/             # PM command scripts
│   └── docs/               # Documentation
└── .gitignore              # Updated with CCPM ignores
```

---

## Best Practices

### For AI Assistants

1. **Register as an agent** when starting work
2. **Claim work streams** to avoid conflicts
3. **Check for conflicts** before major changes
4. **Clean up** when work is complete

### For Repository Setup

1. **Enable GitHub Issues** in settings
2. **Use worktrees** for epic isolation
3. **Keep .claude/ in version control** (except locks)

---

## Troubleshooting

### Clean Up Stale Locks

```bash
source ccpm/scripts/lib/locking.sh
cleanup_stale_locks
```

### Clean Up Stale Agents

```bash
source ccpm/scripts/lib/agent-registry.sh
cleanup_stale_agents "epic-name"
```

### Check Rate Limits

```bash
source ccpm/scripts/lib/github-rate-limit.sh
check_rate_limit
```

---

## Next Steps

1. ✅ Install CCPM in your repository
2. ✅ Create your first epic
3. 📖 Read documentation in `ccpm/docs/`
4. 🚀 Start building with AI-assisted development!

---

## Support

- **Documentation**: `ccpm/docs/` directory
- **GitHub**: https://github.com/automazeio/ccpm
- **Report Issues**: Use GitHub Issues

---

**Ready to use CCPM! 🚀**

*Add this file to any repository where you want AI assistants to have CCPM capabilities.*
