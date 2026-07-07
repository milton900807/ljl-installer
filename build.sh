#!/usr/bin/env bash
set -euo pipefail

INPUT="${1:-install.sh}"
OUTPUT="${2:-installer.obfuscated.sh}"

if [[ ! -f "$INPUT" ]]; then
  echo "ERROR: input installer not found: $INPUT"
  exit 1
fi

if ! command -v gzip >/dev/null 2>&1; then
  echo "ERROR: gzip is required"
  exit 1
fi

if ! command -v base64 >/dev/null 2>&1; then
  echo "ERROR: base64 is required"
  exit 1
fi

PAYLOAD="$(gzip -c "$INPUT" | base64 -w 0)"

cat > "$OUTPUT" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail

PAYLOAD='$PAYLOAD'

tmp="\$(mktemp)"
trap 'rm -f "\$tmp"' EXIT

printf '%s' "\$PAYLOAD" | base64 -d | gzip -d > "\$tmp"
chmod +x "\$tmp"
bash "\$tmp" "\$@"
SCRIPT

chmod +x "$OUTPUT"

echo "Wrote obfuscated installer:"
echo "  $OUTPUT"
echo
echo "Run with:"
echo "  ./$OUTPUT"
