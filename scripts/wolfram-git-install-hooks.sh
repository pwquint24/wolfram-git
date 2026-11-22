#!/usr/bin/env bash
# wolfram-git-install-hooks.sh: Setup git filter and pre-commit hook for Wolfram git utilities

set -e

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$REPO_ROOT" ]; then
  echo "Error: Not inside a git repository."
  exit 1
fi

# Determine where the utility scripts reside (same directory as this installer)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

HOOKS_DIR="$REPO_ROOT/.git/hooks"
mkdir -p "$HOOKS_DIR"

# 1. Install pre-commit hook
echo "Installing pre-commit hook..."
cp "$SCRIPT_DIR/wolfram-git-pre-commit" "$HOOKS_DIR/pre-commit"
chmod +x "$HOOKS_DIR/pre-commit"
git config wolfram.exporterPath "$SCRIPT_DIR/wolfram-git-export-formats.wls"
git config wolfram.killLspPath "$SCRIPT_DIR/wolfram-git-kill-lsp.sh"

# 2. Configure git clean filter for .nb files
echo "Configuring git filter 'wolfram-nb'..."
git config filter.wolfram-nb.clean "$SCRIPT_DIR/wolfram-git-filter.wls"
git config filter.wolfram-nb.smudge "cat"
git config filter.wolfram-nb.required true

# 3. Ensure .gitattributes exists
GITATTRIBUTES="$REPO_ROOT/.gitattributes"
if ! grep -q "filter=wolfram-nb" "$GITATTRIBUTES" 2>/dev/null; then
  echo "Adding filter to .gitattributes..."
  echo "*.nb filter=wolfram-nb" >> "$GITATTRIBUTES"
fi

echo To set export formats use git config wolfram.exportFormats "md vsnb org"
echo "Done! Wolfram git utilities configured successfully."
