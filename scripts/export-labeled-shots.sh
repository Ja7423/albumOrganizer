#!/bin/bash
# Exports the screenshots the user filed by hand (placement = 'user') as a labeled set for
# `classification-eval`. See doc/classification.md §7.1.
#
#   scripts/export-labeled-shots.sh [library.sqlite] [output.json]
#
# Defaults: the booted simulator's database, and eval/labeled-shots.json (gitignored: the OCR text
# can contain personal information, so never commit the output).
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
bundle_id="com.chiawei.albumOrganizer"

if [[ -n "${1:-}" ]]; then
    database="$1"
else
    container="$(xcrun simctl get_app_container booted "$bundle_id" data)"
    database="$container/Library/Application Support/library.sqlite"
fi
output="${2:-$repo_root/eval/labeled-shots.json}"

if [[ ! -f "$database" ]]; then
    echo "database not found: $database" >&2
    exit 1
fi
mkdir -p "$(dirname "$output")"

# The right answer is the built-in folder the user chose, or null (未分類) when they took it out of
# every folder. Custom folders are skipped: no classifier layer can answer them yet. Screenshots
# without text are skipped too: neither layer ever looks at them.
# Read-only, so the app may keep running (WAL).
sqlite3 -readonly "file:$database?mode=ro" <<'SQL' > "$output"
SELECT json_group_array(json_object(
    'id', s.id,
    'expected', f.builtIn,
    'text', (SELECT group_concat(json_extract(b.value, '$.text'), char(10)) FROM json_each(r.blocks) AS b),
    'barcodes', json_array_length(r.barcodes),
    'blocks', json(r.blocks)
))
FROM shot AS s
JOIN recognition AS r ON r.shotID = s.id
LEFT JOIN folder AS f ON f.id = s.folderID
WHERE s.placement = 'user'
  AND (s.folderID IS NULL OR f.builtIn IS NOT NULL)
  AND r.state = 'done'
  AND json_array_length(r.blocks) > 0;
SQL

count="$(sqlite3 :memory: "SELECT json_array_length(readfile('$output'));" 2>/dev/null || echo "?")"
echo "exported $count labeled screenshots to $output"
