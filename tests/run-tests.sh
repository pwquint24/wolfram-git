#!/usr/bin/env bash
# run-tests.sh: Automated test suite for Wolfram git utilities
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

TEST_SANDBOX="$SCRIPT_DIR/test-sandbox"
rm -rf "$TEST_SANDBOX"
mkdir -p "$TEST_SANDBOX"

echo "=== Running Wolfram Git Utilities Test Suite ==="

# Ensure license is available before running tests
"$ROOT_DIR/scripts/wolfram-git-kill-lsp.sh" >/dev/null 2>&1 || true

# 1. Test clean filter directly
echo "[1/6] Testing wolfram-git-filter.wls on raw notebook string..."
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
echo "[2/6] Testing wolfram-git-export-formats.wls..."
SAMPLE_NB="$TEST_SANDBOX/sample.nb"
cat << 'EOF' > "$SAMPLE_NB"
Notebook[{
  Cell["Sample Title", "Title"],
  Cell[CellGroupData[{
    Cell["2 + 2", "Input"],
    Cell[CellGroupData[{
      Cell["some print output", "Print"],
      Cell["4", "Output"]
    }, Open]]
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
if grep -q "some print output" "$TEST_SANDBOX/sample.md"; then
  echo "FAIL: Print cell was not discarded in markdown export!"
  exit 1
fi
if ! grep -q "2 + 2" "$TEST_SANDBOX/sample.md"; then
  echo "FAIL: Input cell missing in markdown export!"
  exit 1
fi
if [ ! -f "$TEST_SANDBOX/sample.vsnb" ]; then
  echo "FAIL: sample.vsnb was not generated!"
  exit 1
fi
if grep -q '"value":"4"' "$TEST_SANDBOX/sample.vsnb"; then
  echo "FAIL: Output cell was not discarded in vsnb export!"
  exit 1
fi
if grep -q "some print output" "$TEST_SANDBOX/sample.vsnb"; then
  echo "FAIL: Print cell was not discarded in vsnb export!"
  exit 1
fi
if ! grep -q '"value":"2 + 2"' "$TEST_SANDBOX/sample.vsnb"; then
  echo "FAIL: Input cell missing in vsnb export!"
  exit 1
fi
# Verify the vsnb round-trips back to a valid Wolfram Notebook
VSNB_ROUNDTRIP=$(cd "$TEST_SANDBOX" && wolframscript -code 'If[MatchQ[Import["sample.vsnb", {"VSNB", "Notebook"}], Notebook[{__Cell}]], "OK", "BAD"]' 2>/dev/null)
if [ "$VSNB_ROUNDTRIP" != "OK" ]; then
  echo "FAIL: sample.vsnb did not round-trip to a valid Wolfram Notebook!"
  exit 1
fi
echo "PASS: wolfram-git-export-formats.wls generated clean markdown and vsnb without output cells."

# Optional test: Real-world notebook conversion if Kalman_ARMA_Stock_Forecasting.nb exists
if [ -f "$SCRIPT_DIR/Kalman_ARMA_Stock_Forecasting.nb" ]; then
  echo "Testing real-world notebook conversion on Kalman_ARMA_Stock_Forecasting.nb..."
  cp "$SCRIPT_DIR/Kalman_ARMA_Stock_Forecasting.nb" "$TEST_SANDBOX/kalman.nb"
  "$ROOT_DIR/scripts/wolfram-git-export-formats.wls" "$TEST_SANDBOX/kalman.nb"
  if grep -q 'First\[\$Failed\]' "$TEST_SANDBOX/kalman.md"; then
    echo "FAIL: Kalman markdown contains First[\$Failed] error artifact!"
    exit 1
  fi
  if grep -q 'During evaluation' "$TEST_SANDBOX/kalman.md"; then
    echo "FAIL: Kalman markdown contains output or print cell artifacts!"
    exit 1
  fi
  if grep -q 'During evaluation' "$TEST_SANDBOX/kalman.vsnb"; then
    echo "FAIL: Kalman vsnb contains output or print cell artifacts!"
    exit 1
  fi
  if ! grep -q 'kalmanTrendFilter' "$TEST_SANDBOX/kalman.md"; then
    echo "FAIL: Expected function name missing in Kalman markdown export!"
    exit 1
  fi
  if ! grep -q 'kalmanTrendFilter' "$TEST_SANDBOX/kalman.vsnb"; then
    echo "FAIL: Expected function name missing in Kalman vsnb export!"
    exit 1
  fi
  echo "PASS: Real-world notebook Kalman_ARMA_Stock_Forecasting.nb converted cleanly."
fi

# 3. Test git repo integration (using wolfram-git-install-hooks.sh)
echo "[3/6] Testing git integration using installer in test sandbox..."
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
    Cell["Sqrt[16]", "Input", CellLabel -> "In[1]:=", ExpressionUUID -> "int-uuid-2"],
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

# Verify companion files were generated and committed
if [ ! -f "notebook1.md" ]; then
  echo "FAIL: notebook1.md was not created!"
  exit 1
fi
if [ ! -f "notebook1.vsnb" ]; then
  echo "FAIL: notebook1.vsnb was not created!"
  exit 1
fi
if [ ! -f "notebook1.org" ]; then
  echo "FAIL: notebook1.org was not created!"
  exit 1
fi
if ! grep -q "import-sci-wolfram-image-package" "notebook1.org"; then
  echo "FAIL: sci-wolfram prologue block missing in notebook1.org!"
  exit 1
fi
if grep -q "In\[1\]:=" "notebook1.org"; then
  echo "FAIL: In[1]:= label was not stripped in notebook1.org!"
  exit 1
fi
COMMITTED_FILES=$(git log -1 --name-only --pretty="")
if ! echo "$COMMITTED_FILES" | grep -q "notebook1.md"; then
  echo "FAIL: notebook1.md was not included in the git commit!"
  exit 1
fi
if ! echo "$COMMITTED_FILES" | grep -q "notebook1.vsnb"; then
  echo "FAIL: notebook1.vsnb was not included in the git commit!"
  exit 1
fi
if ! echo "$COMMITTED_FILES" | grep -q "notebook1.org"; then
  echo "FAIL: notebook1.org was not included in the git commit!"
  exit 1
fi
echo "PASS: Git filter and pre-commit hook integrated seamlessly."

# 4. Test notebook deletion workflow
echo "[4/6] Testing notebook deletion workflow..."
git rm -q notebook1.nb
git commit -m "Remove notebook1" -q
if git ls-files | grep -q "notebook1.md"; then
  echo "FAIL: notebook1.md should have been removed from git index!"
  exit 1
fi
if git ls-files | grep -q "notebook1.vsnb"; then
  echo "FAIL: notebook1.vsnb should have been removed from git index!"
  exit 1
fi
if git ls-files | grep -q "notebook1.org"; then
  echo "FAIL: notebook1.org should have been removed from git index!"
  exit 1
fi
echo "PASS: Notebook deletion removes companion files."

# 5. Test configurable output formats
echo "[5/6] Testing configurable output formats (org only)..."
git config wolfram.exportFormats "org"
cat << 'EOF' > notebook2.nb
Notebook[{
  Cell["Org Only", "Title"],
  Cell["2 + 2", "Input"]
}]
EOF
git add notebook2.nb
git commit -m "Add notebook2" -q

if [ ! -f "notebook2.org" ]; then
  echo "FAIL: notebook2.org was not created!"
  exit 1
fi
if [ -f "notebook2.md" ]; then
  echo "FAIL: notebook2.md should have been discarded!"
  exit 1
fi
if [ -f "notebook2.vsnb" ]; then
  echo "FAIL: notebook2.vsnb should not have been created!"
  exit 1
fi
COMMITTED_FILES2=$(git log -1 --name-only --pretty="")
if ! echo "$COMMITTED_FILES2" | grep -q "notebook2.org"; then
  echo "FAIL: notebook2.org was not included in the git commit!"
  exit 1
fi
if echo "$COMMITTED_FILES2" | grep -q "notebook2.md"; then
  echo "FAIL: notebook2.md should not have been committed!"
  exit 1
fi
if echo "$COMMITTED_FILES2" | grep -q "notebook2.vsnb"; then
  echo "FAIL: notebook2.vsnb should not have been committed!"
  exit 1
fi
git config --unset wolfram.exportFormats
echo "PASS: Configurable output formats honored (org only, markdown discarded)."

# 6. Test license recovery mechanism
echo "[6/6] Testing license exhaustion detection & kill-lsp trigger..."
TRIGGER_LOG="$TEST_SANDBOX/kill_lsp_called.txt"
MOCK_KILL="$TEST_SANDBOX/mock-kill-lsp.sh"
cat << EOF > "$MOCK_KILL"
#!/usr/bin/env bash
echo "kill-lsp-triggered" > "$TRIGGER_LOG"
EOF
chmod +x "$MOCK_KILL"

REAL_WOLFRAMSCRIPT="$(which wolframscript)"
MOCK_DIR="$TEST_SANDBOX/bin"
mkdir -p "$MOCK_DIR"
MOCK_WS="$MOCK_DIR/wolframscript"
FLAG_FILE="$TEST_SANDBOX/ws_called"
cat << EOF > "$MOCK_WS"
#!/usr/bin/env bash
if [ ! -f "$FLAG_FILE" ]; then
  touch "$FLAG_FILE"
  echo "Simulated license failure" >&2
  exit 255
else
  exec "$REAL_WOLFRAMSCRIPT" "\$@"
fi
EOF
chmod +x "$MOCK_WS"

cd "$TEST_SANDBOX"
git config wolfram.killLspPath "$MOCK_KILL"
echo 'Notebook[{Cell["License Test", "Title"]}]' > lic_test.nb
git add lic_test.nb
PATH="$MOCK_DIR:$PATH" git commit -m "License recovery commit" -q

if [ ! -f "$TRIGGER_LOG" ]; then
  echo "FAIL: kill-lsp was not triggered when wolframscript failed!"
  exit 1
fi
echo "PASS: License failure correctly triggered kill-lsp and recovered."

# Clean up sandbox
rm -rf "$TEST_SANDBOX"

echo "=== All Tests Passed Successfully! ==="
