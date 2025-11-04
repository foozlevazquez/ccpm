#!/bin/bash
# Migration script to add version field to existing files

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/frontmatter.sh"

echo "🔄 Migrating files to add version field"
echo "========================================"
echo ""

# Find all epic and task files
file_count=0
migrated_count=0

for epic_dir in .claude/epics/*/; do
    [ -d "$epic_dir" ] || continue
    
    # Process epic.md
    if [ -f "${epic_dir}epic.md" ]; then
        ((file_count++))
        if ! grep -q "^version:" "${epic_dir}epic.md"; then
            ensure_version "${epic_dir}epic.md"
            echo "✓ Migrated: ${epic_dir}epic.md"
            ((migrated_count++))
        fi
    fi
    
    # Process task files
    for task_file in "${epic_dir}"[0-9]*.md; do
        [ -f "$task_file" ] || continue
        ((file_count++))
        
        if ! grep -q "^version:" "$task_file"; then
            ensure_version "$task_file"
            echo "✓ Migrated: $task_file"
            ((migrated_count++))
        fi
    done
done

echo ""
echo "Migration complete!"
echo "  Total files checked: $file_count"
echo "  Files migrated: $migrated_count"
echo "  Already had version: $((file_count - migrated_count))"
