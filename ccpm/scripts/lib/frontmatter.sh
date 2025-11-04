#!/bin/bash
# Frontmatter Library
# YAML frontmatter parsing and manipulation utilities

# Extract frontmatter from file
# Usage: extract_frontmatter <file_path>
extract_frontmatter() {
    local file="$1"
    
    [ -f "$file" ] || {
        echo "❌ File not found: $file" >&2
        return 1
    }
    
    # Extract content between first two "---" markers
    awk '/^---$/{if(++count==2)exit;next}count==1' "$file"
}

# Get frontmatter field value
# Usage: get_frontmatter_field <file_path> <field_name>
get_frontmatter_field() {
    local file="$1"
    local field="$2"
    
    extract_frontmatter "$file" | grep "^${field}:" | sed "s/^${field}: *//"
}

# Update frontmatter field
# Usage: update_frontmatter_field <file_path> <field_name> <value>
update_frontmatter_field() {
    local file="$1"
    local field="$2"
    local value="$3"
    
    [ -f "$file" ] || {
        echo "❌ File not found: $file" >&2
        return 1
    }
    
    # Use sed to update the field in place
    sed -i "/^${field}:/c\\${field}: ${value}" "$file"
}

# Extract content (everything after frontmatter)
# Usage: extract_content <file_path>
extract_content() {
    local file="$1"
    
    [ -f "$file" ] || {
        echo "❌ File not found: $file" >&2
        return 1
    }
    
    # Skip frontmatter (first two --- blocks) and output rest
    awk '/^---$/{if(++count==2){skip=0;next}}count>=2' "$file"
}

# Validate frontmatter format
# Usage: validate_frontmatter <file_path>
validate_frontmatter() {
    local file="$1"
    
    [ -f "$file" ] || {
        echo "❌ File not found: $file" >&2
        return 1
    }
    
    # Check if file starts with ---
    if ! head -1 "$file" | grep -q "^---$"; then
        echo "❌ Frontmatter must start with ---" >&2
        return 1
    fi
    
    # Check if there's a closing ---
    if ! head -20 "$file" | tail -n +2 | grep -q "^---$"; then
        echo "❌ Frontmatter must have closing ---" >&2
        return 1
    fi
    
    echo "✓ Frontmatter valid"
    return 0
}

# Create file with frontmatter
# Usage: create_with_frontmatter <file_path> <frontmatter_content> <body_content>
create_with_frontmatter() {
    local file="$1"
    local frontmatter="$2"
    local body="$3"
    
    cat > "$file" << EOF
---
$frontmatter
---

$body
EOF
}

# Example usage guard
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    echo "Frontmatter Library"
    echo "Usage: source this file and call functions"
    echo ""
    echo "Functions:"
    echo "  extract_frontmatter <file>"
    echo "  get_frontmatter_field <file> <field>"
    echo "  update_frontmatter_field <file> <field> <value>"
    echo "  extract_content <file>"
    echo "  validate_frontmatter <file>"
    echo "  create_with_frontmatter <file> <frontmatter> <body>"
fi

# ============================================================================
# Optimistic Locking with Version Control (Task #4)
# ============================================================================

# Add version field to frontmatter if not present
# Usage: ensure_version <file_path>
ensure_version() {
    local file="$1"
    
    [ -f "$file" ] || {
        echo "❌ File not found: $file" >&2
        return 1
    }
    
    # Check if version field exists
    if ! grep -q "^version:" "$file"; then
        # Add version: 1 after the opening ---
        sed -i '1 a version: 1' "$file"
    fi
}

# Get version from frontmatter
# Usage: get_version <file_path>
get_version() {
    local file="$1"
    get_frontmatter_field "$file" "version" || echo "0"
}

# Validate and update with optimistic locking
# Usage: optimistic_update <file_path> <expected_version> <update_function>
optimistic_update() {
    local file="$1"
    local expected_version="$2"
    local update_func="$3"
    
    [ -f "$file" ] || {
        echo "❌ File not found: $file" >&2
        return 1
    }
    
    # Source atomic operations
    source "$(dirname "${BASH_SOURCE[0]}")/atomic-ops.sh"
    
    # Get current version
    local current_version=$(get_version "$file")
    
    # Validate version
    if [ "$current_version" != "$expected_version" ]; then
        echo "❌ Version conflict detected!" >&2
        echo "   Expected version: $expected_version" >&2
        echo "   Current version:  $current_version" >&2
        echo "   File: $file" >&2
        echo "   Another process has modified this file." >&2
        return 1
    fi
    
    # Increment version
    local new_version=$((current_version + 1))
    
    # Define wrapper that applies update and increments version
    update_with_version() {
        local temp_file="$1"
        
        # Apply user's update
        $update_func "$temp_file" || return 1
        
        # Increment version
        sed -i "/^version:/c\\version: $new_version" "$temp_file"
    }
    
    # Use atomic update
    atomic_update "$file" update_with_version
}

# Atomic update frontmatter with optimistic locking
# Usage: optimistic_update_frontmatter <file_path> <key> <value>
optimistic_update_frontmatter() {
    local file="$1"
    local key="$2"
    local value="$3"
    
    [ -f "$file" ] || {
        echo "❌ File not found: $file" >&2
        return 1
    }
    
    # Source atomic operations
    source "$(dirname "${BASH_SOURCE[0]}")/atomic-ops.sh"
    
    # Get current version
    local current_version=$(get_version "$file")
    local new_version=$((current_version + 1))
    
    # Define update function
    update_field_and_version() {
        local temp_file="$1"
        
        # Update the field
        sed -i "/^${key}:/c\\${key}: ${value}" "$temp_file"
        
        # Increment version
        sed -i "/^version:/c\\version: $new_version" "$temp_file"
    }
    
    # Use atomic update
    atomic_update "$file" update_field_and_version
}

# Retry wrapper for optimistic updates
# Usage: retry_optimistic_update <max_retries> <file> <update_function>
retry_optimistic_update() {
    local max_retries="$1"
    local file="$2"
    local update_func="$3"
    local attempt=0
    
    while [ $attempt -lt $max_retries ]; do
        # Get current version
        local version=$(get_version "$file")
        
        # Try update
        if optimistic_update "$file" "$version" "$update_func"; then
            return 0
        fi
        
        ((attempt++))
        echo "⚠️ Retry attempt $attempt of $max_retries..." >&2
        sleep $((RANDOM % 3 + 1))  # Random backoff 1-3 seconds
    done
    
    echo "❌ Failed after $max_retries attempts" >&2
    return 1
}
