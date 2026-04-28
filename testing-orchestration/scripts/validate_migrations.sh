#!/bin/bash
# Validate Alembic migrations before commits.
# Detects: duplicate revision IDs, branches (unintended), orphan down_revision.
# Parametrizable: override MIGRATIONS_DIR via env var.

set -e

MIGRATIONS_DIR="${MIGRATIONS_DIR:-backend/migrations/versions}"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=== Validating Alembic Migrations ==="
echo "MIGRATIONS_DIR=$MIGRATIONS_DIR"
echo ""

if [ ! -d "$MIGRATIONS_DIR" ]; then
    echo -e "${RED}ERROR: $MIGRATIONS_DIR does not exist.${NC}"
    echo "Override with: MIGRATIONS_DIR=path/to/versions $0"
    exit 1
fi

# 1. Duplicate revision IDs
echo "[1/4] Checking for duplicate revision IDs..."
DUPLICATES=$(grep -h "^revision = " "$MIGRATIONS_DIR"/*.py 2>/dev/null | sort | uniq -d)

if [ -n "$DUPLICATES" ]; then
    echo -e "${RED}ERROR: Duplicate revision IDs found:${NC}"
    echo "$DUPLICATES"
    echo ""
    echo "Files with duplicates:"
    for dup in $(echo "$DUPLICATES" | sed "s/revision = '//g" | sed "s/'//g"); do
        grep -l "revision = '$dup'" "$MIGRATIONS_DIR"/*.py
    done
    exit 1
else
    echo -e "${GREEN}  No duplicate revision IDs found${NC}"
fi

# 2. Unintended branches (multiple migrations with same parent)
echo ""
echo "[2/4] Checking for unintended branches (multiple migrations with same parent)..."
BRANCH_DUPLICATES=$(grep -h "^down_revision = " "$MIGRATIONS_DIR"/*.py 2>/dev/null | grep -v "None" | sort | uniq -d)

if [ -n "$BRANCH_DUPLICATES" ]; then
    echo -e "${YELLOW}WARNING: Multiple migrations have the same parent (potential branch):${NC}"
    echo "$BRANCH_DUPLICATES"
    echo ""
    echo "This may be intentional for merge migrations, but verify:"
    for dup in $(echo "$BRANCH_DUPLICATES" | sed "s/down_revision = '//g" | sed "s/'//g"); do
        echo "  Parent '$dup' is referenced by:"
        grep -l "down_revision = '$dup'" "$MIGRATIONS_DIR"/*.py | sed 's/^/    /'
    done
else
    echo -e "${GREEN}  No unintended branches detected${NC}"
fi

# 3. Orphan down_revision (chain integrity)
echo ""
echo "[3/4] Checking down_revision chain integrity..."
REVS=$(grep -hE "^revision = " "$MIGRATIONS_DIR"/*.py 2>/dev/null | sed -E "s/.*'([^']+)'.*/\1/" | sort -u)
ORPHANS=""
for f in "$MIGRATIONS_DIR"/*.py; do
    [ ! -f "$f" ] && continue
    DR=$(grep "^down_revision = " "$f" 2>/dev/null | sed -E "s/.*'([^']+)'.*/\1/" | head -1)
    [ -z "$DR" ] || [ "$DR" = "None" ] && continue
    if ! echo "$REVS" | grep -qx "$DR"; then
        ORPHANS+="$f down_revision='$DR' (parent not found)\n"
    fi
done

if [ -n "$ORPHANS" ]; then
    echo -e "${RED}ERROR: Orphan down_revision references:${NC}"
    echo -e "$ORPHANS"
    echo "Fix: locate the parent revision file or correct the down_revision pointer."
    exit 1
else
    echo -e "${GREEN}  Chain integrity OK${NC}"
fi

# 4. Suggest unique ID for next migration
echo ""
echo "[4/4] Generating unique ID for new migrations..."
NEW_ID=$(python3 -c "import uuid; print(uuid.uuid4().hex[:12])")
echo -e "  Suggested unique ID for next migration: ${GREEN}$NEW_ID${NC}"
echo ""
echo "  To create a new migration with auto-generated ID:"
echo "    cd backend && flask db migrate -m 'your_migration_description'"
echo ""
echo "  Or use this ID manually:"
echo "    revision = '$NEW_ID'"
echo ""

echo -e "${GREEN}=== Migration validation complete ===${NC}"
