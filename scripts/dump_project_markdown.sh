#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: dump_project_markdown.sh [-r ROOT_DIR] [-o OUTPUT_MD]

Create a single Markdown file containing the project's text files with clear
per-file separators and language-aware code fences, respecting .gitignore.

Options:
  -r, --root   Project root directory (default: current directory)
  -o, --out    Output Markdown file path (default: project_dump.md, created under root)
  -h, --help   Show this help and exit

Notes:
- Prefers ripgrep (rg) for file discovery; falls back to 'git ls-files'.
  Either ripgrep must be installed or ROOT_DIR must be a Git repo.
- Binary files are skipped.
EOF
}

ROOT_DIR="$(pwd)"
OUTPUT_PATH="project_dump.md"

while [ $# -gt 0 ]; do
  case "$1" in
    -r|--root)
      [ $# -ge 2 ] || { echo "Missing argument for $1" >&2; exit 1; }
      ROOT_DIR="$2"
      shift 2
      ;;
    -o|--out)
      [ $# -ge 2 ] || { echo "Missing argument for $1" >&2; exit 1; }
      OUTPUT_PATH="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

# Normalize ROOT_DIR
if [ ! -d "$ROOT_DIR" ]; then
  echo "Root directory does not exist: $ROOT_DIR" >&2
  exit 1
fi
ROOT_DIR="$(cd "$ROOT_DIR" && pwd)"

# Normalize OUTPUT_PATH (make absolute if relative)
case "$OUTPUT_PATH" in
  /*) : ;; # absolute already
  *) OUTPUT_PATH="$ROOT_DIR/$OUTPUT_PATH" ;;
esac

mkdir -p "$(dirname "$OUTPUT_PATH")"

# Collect files respecting .gitignore
FILE_LIST="$(mktemp)"
cleanup() {
  rm -f "$FILE_LIST" "$TMP_OUT"
}
trap cleanup EXIT

if command -v rg >/dev/null 2>&1; then
  # ripgrep respects .gitignore by default
  ( cd "$ROOT_DIR" && rg --files --hidden --follow --glob '!.git' ) > "$FILE_LIST"
elif [ -d "$ROOT_DIR/.git" ] && command -v git >/dev/null 2>&1; then
  # git files incl. untracked, excluding standard ignores
  ( cd "$ROOT_DIR" && git ls-files -co --exclude-standard ) > "$FILE_LIST"
else
  echo "Error: Need ripgrep (rg) installed or a Git repo to honor .gitignore." >&2
  exit 1
fi

# Temporary output to avoid partial writes
TMP_OUT="$(mktemp)"

# Header
{
  echo "# Project Source Dump"
  echo
  echo "- Root: $ROOT_DIR"
  echo "- Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo
  echo "---"
  echo
} >> "$TMP_OUT"

guess_lang() {
  # Echo a Markdown code fence language based on file extension
  # Falls back to empty (no language hint)
  file="$1"
  ext="${file##*.}"
  case "$ext" in
    lua) echo "lua" ;;
    md|markdown) echo "markdown" ;;
    txt|text|license|licence) echo "text" ;;
    sh|bash|zsh) echo "bash" ;;
    js|jsx|mjs|cjs) echo "javascript" ;;
    ts|tsx) echo "typescript" ;;
    json) echo "json" ;;
    yml|yaml) echo "yaml" ;;
    html|htm) echo "html" ;;
    css|scss|sass|less) echo "css" ;;
    py) echo "python" ;;
    go) echo "go" ;;
    rs) echo "rust" ;;
    java) echo "java" ;;
    kt|kts) echo "kotlin" ;;
    c) echo "c" ;;
    h) echo "c" ;;
    cpp|cxx|cc) echo "cpp" ;;
    hpp|hh|hxx) echo "cpp" ;;
    m) echo "objective-c" ;;
    mm) echo "objective-c++" ;;
    swift) echo "swift" ;;
    rb) echo "ruby" ;;
    php) echo "php" ;;
    *) echo "" ;;
  esac
}

is_text_file() {
  # Heuristic: grep -Iq returns success for text files
  # Using LC_ALL=C for consistent behavior across locales
  LC_ALL=C grep -Iq . -- "$1"
}

# Compute absolute path to skip if output resides under root
SKIP_ABS="$OUTPUT_PATH"

while IFS= read -r rel; do
  # Skip empty lines
  [ -n "$rel" ] || continue

  abs="$ROOT_DIR/$rel"

  # Skip non-regular files
  if [ ! -f "$abs" ]; then
    continue
  fi

  # Skip the output file itself if it lives in the tree
  if [ "$abs" = "$SKIP_ABS" ]; then
    continue
  fi

  # Skip binaries
  if ! is_text_file "$abs"; then
    continue
  fi

  # Decide on fence; if file contains triple backticks, use tildes
  fence='```'
  if grep -q '```' -- "$abs"; then
    fence='~~~'
  fi

  lang="$(guess_lang "$rel")"

  {
    echo "## File: $rel"
    echo
    if [ -n "$lang" ]; then
      echo "${fence}${lang}"
    else
      echo "${fence}"
    fi
    cat -- "$abs"
    echo
    echo "${fence}"
    echo
    echo "---"
    echo
  } >> "$TMP_OUT"
done < "$FILE_LIST"

mv -f "$TMP_OUT" "$OUTPUT_PATH"

echo "Wrote Markdown to: $OUTPUT_PATH"


