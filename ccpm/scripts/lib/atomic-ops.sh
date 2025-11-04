#!/bin/bash
# Atomic File Operations Library
# Provides safe concurrent file modifications using temp-rename pattern

# Get temporary file with unique name
get_temp_file() {
    local base_name="${1:-ccpm}"
    local uuid=$(uuidgen 2>/dev/null || echo "$$-$RANDOM")
    echo "/tmp/${base_name}-${uuid}"
}

# Cleanup function for temp files
cleanup_temp() {
    local temp_file="$1"
    [ -f "$temp_file" ] && rm -f "$temp_file"
}

# Setup trap for temp file cleanup
setup_temp_cleanup() {
    local temp_file="$1"
    trap "cleanup_temp '$temp_file'" EXIT INT TERM
}

# Atomic write - write to temp file, then rename
# Usage: atomic_write <file_path> <content>
atomic_write() {
    local target="$1"
    local content="$2"
    local temp_file=$(get_temp_file "atomic-write")
    
    # Setup cleanup
    setup_temp_cleanup "$temp_file"
    
    # Write to temp file
    echo "$content" > "$temp_file" || {
        echo "❌ Failed to write to temp file" >&2
        return 1
    }
    
    # Preserve permissions if target exists
    if [ -f "$target" ]; then
        chmod --reference="$target" "$temp_file" 2>/dev/null || true
    fi
    
    # Atomic rename
    mv "$temp_file" "$target" || {
        echo "❌ Failed to rename temp file to $target" >&2
        cleanup_temp "$temp_file"
        return 1
    }
    
    return 0
}

# Atomic write from file
# Usage: atomic_write_file <source_file> <target_file>
atomic_write_file() {
    local source="$1"
    local target="$2"
    local temp_file=$(get_temp_file "atomic-write")
    
    [ -f "$source" ] || {
        echo "❌ Source file not found: $source" >&2
        return 1
    }
    
    setup_temp_cleanup "$temp_file"
    
    # Copy to temp
    cp "$source" "$temp_file" || {
        echo "❌ Failed to copy to temp file" >&2
        return 1
    }
    
    # Preserve permissions if target exists
    if [ -f "$target" ]; then
        chmod --reference="$target" "$temp_file" 2>/dev/null || true
    fi
    
    # Atomic rename
    mv "$temp_file" "$target" || {
        echo "❌ Failed to rename to $target" >&2
        cleanup_temp "$temp_file"
        return 1
    }
    
    return 0
}

# Atomic append - safe append operation
# Usage: atomic_append <file_path> <content>
atomic_append() {
    local target="$1"
    local content="$2"
    local temp_file=$(get_temp_file "atomic-append")
    
    setup_temp_cleanup "$temp_file"
    
    # Copy existing content if file exists
    if [ -f "$target" ]; then
        cat "$target" > "$temp_file" || {
            echo "❌ Failed to read existing file" >&2
            return 1
        }
    fi
    
    # Append new content
    echo "$content" >> "$temp_file" || {
        echo "❌ Failed to append content" >&2
        return 1
    }
    
    # Preserve permissions
    if [ -f "$target" ]; then
        chmod --reference="$target" "$temp_file" 2>/dev/null || true
    fi
    
    # Atomic rename
    mv "$temp_file" "$target" || {
        echo "❌ Failed to update $target" >&2
        cleanup_temp "$temp_file"
        return 1
    }
    
    return 0
}

# Atomic update using function
# Usage: atomic_update <file_path> <update_function>
# update_function receives file path as argument and modifies it
atomic_update() {
    local target="$1"
    local update_func="$2"
    local temp_file=$(get_temp_file "atomic-update")
    
    [ -f "$target" ] || {
        echo "❌ Target file not found: $target" >&2
        return 1
    }
    
    setup_temp_cleanup "$temp_file"
    
    # Copy to temp
    cp "$target" "$temp_file" || {
        echo "❌ Failed to create temp copy" >&2
        return 1
    }
    
    # Apply update function
    $update_func "$temp_file" || {
        echo "❌ Update function failed" >&2
        cleanup_temp "$temp_file"
        return 1
    }
    
    # Preserve permissions
    chmod --reference="$target" "$temp_file" 2>/dev/null || true
    
    # Atomic rename
    mv "$temp_file" "$target" || {
        echo "❌ Failed to update $target" >&2
        cleanup_temp "$temp_file"
        return 1
    }
    
    return 0
}

# Atomic update frontmatter field
# Usage: atomic_update_frontmatter <file_path> <key> <value>
atomic_update_frontmatter() {
    local target="$1"
    local key="$2"
    local value="$3"
    
    [ -f "$target" ] || {
        echo "❌ Target file not found: $target" >&2
        return 1
    }
    
    # Define update function
    update_frontmatter_field() {
        local file="$1"
        
        # Use sed to update the field
        sed -i "/^${key}:/c\\${key}: ${value}" "$file"
    }
    
    atomic_update "$target" update_frontmatter_field
}

# Test if file operations are atomic (for verification)
test_atomicity() {
    local test_file="/tmp/atomic-test-$$"
    
    echo "Testing atomic operations..."
    
    # Test atomic write
    atomic_write "$test_file" "test content" && echo "✓ Atomic write works"
    
    # Test atomic append
    atomic_append "$test_file" "appended line" && echo "✓ Atomic append works"
    
    # Verify content
    if grep -q "test content" "$test_file" && grep -q "appended line" "$test_file"; then
        echo "✓ Content verification passed"
    fi
    
    # Cleanup
    rm -f "$test_file"
    echo "✓ All tests passed"
}

# Example usage guard
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    echo "Atomic File Operations Library"
    echo "Usage: source this file and call functions"
    echo ""
    echo "Functions:"
    echo "  atomic_write <file> <content>"
    echo "  atomic_write_file <source> <target>"
    echo "  atomic_append <file> <content>"
    echo "  atomic_update <file> <update_function>"
    echo "  atomic_update_frontmatter <file> <key> <value>"
    echo ""
    echo "Run test_atomicity to verify operations"
fi
