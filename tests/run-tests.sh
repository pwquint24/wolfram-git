#!/usr/bin/env bash
# run-tests.sh: Automated test suite for Wolfram git utilities
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

TEST_SANDBOX="$SCRIPT_DIR/test-sandbox"
rm -rf "$TEST_SANDBOX"
mkdir -p "$TEST_SANDBOX"

echo "=== Running Wolfram Git Utilities Test Suite ==="

# 1. Test clean filter directly
echo "[1/4] Testing wolfram-git-filter.wls on raw notebook string..."
FILTER_OUTPUT=$(echo 'Notebook[{Cell["Hello Test","Text",CellChangeTimes->{3.8e9},ExpressionUUID->"test-uuid-999"]}]' | "$ROOT_DIR/scripts/wolfram-git-filter.wls")
if echo "$FILTER_OUTPUT" | grep -q "test-uuid-999"; then
  echo "FAIL: ExpressionUUID was not stripped!"
  exit 1
fi
if ! echo "$FILTER_OUTPUT" | grep -q 'Cell\["Hello Test", "Text"\]'; then
  echo "FAIL: Cleaned notebook content unexpected!"
  exit 1
fi
echo "PASS: wolfram-git-filter.wls stripped metadata correctly."

# 2. Test exporter script directly
echo "[2/4] Testing wolfram-git-export-formats.wls..."
SAMPLE_NB="$TEST_SANDBOX/sample.nb"
cat << 'EOF' > "$SAMPLE_NB"
Notebook[{
  Cell["Sample Title", "Title"],
  Cell[CellGroupData[{
    Cell["2 + 2", "Input"],
    Cell["4", "Output"]
  }, Open]]
}]
EOF

"$ROOT_DIR/scripts/wolfram-git-export-formats.wls" "$SAMPLE_NB"
if [ ! -f "$TEST_SANDBOX/sample.md" ]; then
  echo "FAIL: sample.md was not generated!"
  exit 1
fi
if grep -q "4" "$TEST_SANDBOX/sample.md"; then
  echo "FAIL: Output cell was not discarded in markdown export!"
  exit 1
fi
if ! grep -q "2 + 2" "$TEST_SANDBOX/sample.md"; then
  echo "FAIL: Input cell missing in markdown export!"
  exit 1
fi
echo "PASS: wolfram-git-export-formats.wls generated clean markdown without output cells."

# 3. Test git repo integration (using wolfram-git-install-hooks.sh)
echo "[3/4] Testing git integration using installer in test sandbox..."
cd "$TEST_SANDBOX"
git init -q
git config user.name "Test User"
git config user.email "test@example.com"

# Run the installer from outside the repo
"$ROOT_DIR/scripts/wolfram-git-install-hooks.sh"
git add .gitattributes
git commit -m "init" -q

cat << 'EOF' > notebook1.nb
Notebook[{
  Cell["Integration Title", "Title", ExpressionUUID -> "int-uuid-1"],
  Cell[CellGroupData[{
    Cell["Sqrt[16]", "Input", ExpressionUUID -> "int-uuid-2"],
    Cell["4", "Output", ExpressionUUID -> "int-uuid-3"]
  }, Open]]
}, WindowSize -> {800, 600}]
EOF

git add notebook1.nb

# Verify staged content is stripped
STAGED_CONTENT=$(git show :notebook1.nb)
if echo "$STAGED_CONTENT" | grep -q "int-uuid"; then
  echo "FAIL: Staged notebook contains ExpressionUUID!"
  exit 1
fi
if echo "$STAGED_CONTENT" | grep -q "WindowSize"; then
  echo "FAIL: Staged notebook contains WindowSize!"
  exit 1
fi

git commit -m "Add notebook1" -q

# Verify notebook1.md was generated and committed
if [ ! -f "notebook1.md" ]; then
  echo "FAIL: notebook1.md was not created!"
  exit 1
fi
COMMITTED_FILES=$(git log -1 --name-only --pretty="")
if ! echo "$COMMITTED_FILES" | grep -q "notebook1.md"; then
  echo "FAIL: notebook1.md was not included in the git commit!"
  exit 1
fi
echo "PASS: Git filter and pre-commit hook integrated seamlessly."

# 4. Test notebook deletion workflow
echo "[4/4] Testing notebook deletion workflow..."
git rm -q notebook1.nb
git commit -m "Remove notebook1" -q
if git ls-files | grep -q "notebook1.md"; then
  echo "FAIL: notebook1.md should have been removed from git index!"
  exit 1
fi
echo "PASS: Notebook deletion removes companion markdown."

# Clean up sandbox
rm -rf "$TEST_SANDBOX"

echo "=== All Tests Passed Successfully! ==="
