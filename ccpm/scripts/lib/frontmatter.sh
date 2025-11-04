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
