#!/bin/bash
#set -e  # Exit on error

OLD_HASH=$1
NEW_HASH=$2
APPLICATION_PATH=$3  # Example: cmd/router

# Get project root directory
PROJECT_ROOT=$(git rev-parse --show-toplevel)

# Step 1: Get all changed files between the two commits
CHANGED_FILES=$(mktemp)
git diff --name-only "$OLD_HASH" "$NEW_HASH" > "$CHANGED_FILES"

# Step 2: Extract dependencies and all source files at OLD_HASH
git checkout "$OLD_HASH" --quiet
OLD_DEPS=$(mktemp)
go list -mod=mod -deps -json "$APPLICATION_PATH/main.go" | jq -r '
  select(.Module) | "\(.Module.Path) \(.Module.Version)"' | sort | uniq > "$OLD_DEPS"

OLD_FILES=$(mktemp)
go list -mod=mod -deps -json "$APPLICATION_PATH/main.go" | jq -r '
  select(.Standard | not)
  | select(.Dir | startswith("'"$PROJECT_ROOT"'/"))
  | {dir: .Dir, files: (.GoFiles + .IgnoredGoFiles)}
  | .files[] as $file | .dir + "/" + $file' | sort | uniq > "$OLD_FILES"

# Step 3: Extract dependencies and all source files at NEW_HASH
git checkout "$NEW_HASH" --quiet
NEW_DEPS=$(mktemp)
go list -mod=mod -deps -json "$APPLICATION_PATH/main.go" | jq -r '
  select(.Module) | "\(.Module.Path) \(.Module.Version)"' | sort | uniq > "$NEW_DEPS"

NEW_FILES=$(mktemp)
go list -mod=mod -deps -json "$APPLICATION_PATH/main.go" | jq -r '
  select(.Standard | not)
  | select(.Dir | startswith("'"$PROJECT_ROOT"'/"))
  | {dir: .Dir, files: (.GoFiles + .IgnoredGoFiles)}
  | .files[] as $file | .dir + "/" + $file' | sort | uniq > "$NEW_FILES"

# Step 4: Compare dependency lists (detects added or removed dependencies)
DEPENDENCIES_CHANGED=false
if comm -3 "$OLD_DEPS" "$NEW_DEPS" | grep -q .; then
  DEPENDENCIES_CHANGED=true
fi

# Step 5: Compare all source files (detects added or removed files, including OS-specific)
SOURCE_FILES_CHANGED=false
if comm -3 "$OLD_FILES" "$NEW_FILES" | grep -q .; then
  SOURCE_FILES_CHANGED=true
fi

# Step 6: Check if any changed files (from git diff) intersect with NEW_FILES
while IFS= read -r FILE; do
  if grep -q "$FILE" "$NEW_FILES"; then
    SOURCE_FILES_CHANGED=true
    break
  fi
done < "$CHANGED_FILES"

# Step 7: Output summary message
if [ "$DEPENDENCIES_CHANGED" = true ] && [ "$SOURCE_FILES_CHANGED" = true ]; then
  echo "Source files and dependencies changed"
elif [ "$DEPENDENCIES_CHANGED" = true ]; then
  echo "Dependencies changed"
elif [ "$SOURCE_FILES_CHANGED" = true ]; then
  echo "Source files changed"
fi

# Step 8: Set GitHub Actions Output
if [ "$DEPENDENCIES_CHANGED" = true ] || [ "$SOURCE_FILES_CHANGED" = true ]; then
  echo "changed=true"
  echo "changed=true" >> "$GITHUB_OUTPUT"
else
  echo "changed=false"
  echo "changed=false" >> "$GITHUB_OUTPUT"
fi

# Cleanup temporary files
rm -f "$CHANGED_FILES" "$OLD_DEPS" "$NEW_DEPS" "$OLD_FILES" "$NEW_FILES"

