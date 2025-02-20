#!/bin/bash
set -e  # Exit on error

OLD_HASH=$1
NEW_HASH=$2
APPLICATION_PATH=$3  # Example: cmd/router

# Get project root directory
PROJECT_ROOT=$(git rev-parse --show-toplevel)

# Step 1: Get all changed files between the two commits
CHANGED_FILES=()
while IFS= read -r line; do
  CHANGED_FILES+=("$line")
done < <(git diff --name-only "$OLD_HASH" "$NEW_HASH")

# Step 2: Extract dependencies and all source files at OLD_HASH
git checkout "$OLD_HASH" --quiet
OLD_DEPS=()
while IFS= read -r line; do
  OLD_DEPS+=("$line")
done < <(go list -mod=mod -deps -json "$APPLICATION_PATH/main.go" | jq -r '
  select(.Module) | "\(.Module.Path) \(.Module.Version)"' | sort | uniq)

OLD_FILES=()
while IFS= read -r line; do
  OLD_FILES+=("$line")
done < <(go list -mod=mod -deps -json "$APPLICATION_PATH/main.go" | jq -r '
  select(.Standard | not)
  | select(.Dir | startswith("'"$PROJECT_ROOT"'/"))
  | {dir: .Dir, files: (.GoFiles + .IgnoredGoFiles)}
  | .files[] as $file | .dir + "/" + $file' | sort | uniq)

# Step 3: Extract dependencies and all source files at NEW_HASH
git checkout "$NEW_HASH" --quiet
NEW_DEPS=()
while IFS= read -r line; do
  NEW_DEPS+=("$line")
done < <(go list -mod=mod -deps -json "$APPLICATION_PATH/main.go" | jq -r '
  select(.Module) | "\(.Module.Path) \(.Module.Version)"' | sort | uniq)

NEW_FILES=()
while IFS= read -r line; do
  NEW_FILES+=("$line")
done < <(go list -mod=mod -deps -json "$APPLICATION_PATH/main.go" | jq -r '
  select(.Standard | not)
  | select(.Dir | startswith("'"$PROJECT_ROOT"'/"))
  | {dir: .Dir, files: (.GoFiles + .IgnoredGoFiles)}
  | .files[] as $file | .dir + "/" + $file' | sort | uniq)

# Step 4: Compare dependency lists (detects added or removed dependencies)
DEPENDENCIES_CHANGED=false
if comm -3 <(printf "%s\n" "${OLD_DEPS[@]}" | sort) <(printf "%s\n" "${NEW_DEPS[@]}" | sort) | grep -q .; then
  DEPENDENCIES_CHANGED=true
fi

# Step 5: Compare all source files (detects added or removed files, including OS-specific)
SOURCE_FILES_CHANGED=false
if comm -3 <(printf "%s\n" "${OLD_FILES[@]}" | sort) <(printf "%s\n" "${NEW_FILES[@]}" | sort) | grep -q .; then
  SOURCE_FILES_CHANGED=true
fi

# Step 6: Check if any changed files (from git diff) intersect with NEW_FILES
for FILE in "${CHANGED_FILES[@]}"; do
  if printf "%s\n" "${NEW_FILES[@]}" | grep -q "$FILE"; then
    SOURCE_FILES_CHANGED=true
    break
  fi
done

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
  echo "changed=true" >> "$GITHUB_ENV"  # Store in GITHUB_ENV for debugging
  echo "changed=true" >> "$GITHUB_OUTPUT"  # Set GitHub Actions output
else
  echo "changed=false" >> "$GITHUB_ENV"
  echo "changed=false" >> "$GITHUB_OUTPUT"
fi
