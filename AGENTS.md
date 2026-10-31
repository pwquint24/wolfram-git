# Wolfram Git Utilities

Utilities for managing Wolfram Language notebooks (`.nb`) in Git repositories.

---

## Architecture & Design Decisions

### 1. Script Organization & Naming Convention
- All utility scripts start with the `wolfram-git-` prefix:
  - `wolfram-git-filter.wls`: Git clean filter for notebook files.
  - `wolfram-git-export-formats.wls`: Companion format generator (Notebook to Markdown and VS Code notebooks).
  - `wolfram-git-md-to-org.sh`: Markdown → Org converter (pandoc wrapper that prepends the sci-wolfram prologue source block).
  - `wolfram-git-pre-commit`: Git pre-commit hook script.
  - `wolfram-git-install-hooks.sh`: Repository installer script.
  - `wolfram-git-kill-lsp.sh`: Utility to terminate lingering Wolfram LSP processes and release kernel licenses.
- **Location independence:** The utility scripts do **not** need to reside in a `scripts/` subfolder of target repositories. They can live in a centralized folder (e.g., `~/LocalDocuments/Scripts/` or wherever this repo is kept).
- `wolfram-git-install-hooks.sh` dynamically detects its own directory (`SCRIPT_DIR`) and configures the target git repository's hooks and filter paths pointing to that directory.

---

### 2. Git Clean Filter (`wolfram-git-filter.wls`)
- **Purpose:** Strips temporary cache, session data, window geometries, and non-essential cell options from `.nb` files when staged (`git add`), ensuring minimal, readable diffs in version control.
- **Implementation:**
  - Uses [`ResourceFunction["SaveReadableNotebook"]`](https://resources.wolframcloud.com/FunctionRepository/resources/SaveReadableNotebook/).
  - By default strips `ExpressionUUID`, `CellChangeTimes`, `WindowSize`, and `WindowMargins`.
  - Formats notebooks into human-readable, multiline indented structures.
  - Accepts input from standard input (`$ScriptInputString`) or as a file argument.
  - Output is written to standard output (`$Output`).
  - **Fail-safe fallback:** If cleaning fails or the input is not a valid notebook expression, the original raw content is output unchanged so no user data is ever corrupted or lost.

---

### 3. Companion Format Exporter (`wolfram-git-export-formats.wls`)
- **Purpose:** Converts Wolfram notebooks to companion formats — plain text Markdown (`.md`) and VS Code notebooks (`.vsnb`) — suitable for viewing in Git web interfaces (GitHub, GitLab), terminal diffs, and VS Code.
- **Cell Output Discarding:**
  - Automatically removes all output cells (`Output`, `Message`, `Print`, `Echo`) from the notebook prior to conversion.
  - Unwraps `CellGroupData` to preserve input and documentation cells while discarding output and graphics artifacts.
- **No External Images:**
  - Configures `GeneratedAssetLocation -> None` during export.
  - Any images present in text or input cells are stored inline as base64 data URIs (`data:image/png;base64,...`) rather than in detached `img/` folders.
- **VSNB generation:**
  - Emits the JSON VS Code notebook schema expected by Wolfram's `Import[..., "VSNB"]`: cells with `kind`, `value`, `languageId`, `outputs`, `metadata`, and `executionSummary`.
  - Code cells (`Input`, `Code`) use a vendored copy of [`mathematica2jupyter`](https://github.com/divenex/mathematica2jupyter) (`scripts/Mathematica2Jupyter.wl`) for robust `BoxData` → input-text extraction.
  - Markdown cells reuse the built-in Markdown exporter so `.vsnb` headings/styling match the `.md` companion.
- **Modularity:**
  - Supports an extensible converter association (`converters`), allowing other formats to be added easily in the future.

---

### 4. Git Pre-Commit Hook (`wolfram-git-pre-commit`)
- **Purpose:** Automatically generates and stages companion `.md`, `.vsnb`, and `.org` files whenever `.nb` files are staged for commit.
- **Configurable output formats:**
  - Reads `git config --get wolfram.exportFormats` (space-separated list of `md`, `vsnb`, `org`). Defaults to `md vsnb org` when unset.
  - Calls `wolfram-git-export-formats.wls` with only the needed formats. `md` is always produced when `org` is requested, because `org` is derived from the Markdown companion.
  - If `org` is requested, `wolfram-git-md-to-org.sh` converts the Markdown companion to Org and prepends the sci-wolfram prologue source block.
  - Companion files whose format is not in the configured list are discarded (removed from the working tree and, if already tracked, staged for removal).
- **Workflow:**
  - Finds all staged `.nb` files (`git diff --cached --name-only --diff-filter=ACM`).
  - **License Availability Check:** Runs a trivial invocation (`wolframscript -code '1+1'`). If no license is available (e.g., license processes exhausted by background LSP server), it automatically runs `wolfram-git-kill-lsp.sh` to release the license before retrying and continuing.
  - Calls `wolfram-git-export-formats.wls` for each staged notebook.
  - Stages the resulting companion files into the commit (`git add`).
  - Handles deletions (`git diff --cached --diff-filter=D`): if a `.nb` file is deleted from git, the corresponding tracked companion files are automatically staged for removal.
  - Path lookup: reads `git config --get wolfram.exporterPath` and `git config --get wolfram.killLspPath`, checks `PATH`, or falls back to adjacent script locations.

---

### 5. Installation & Setup (`wolfram-git-install-hooks.sh`)
- To configure any Git repository:
  ```bash
  cd /path/to/any/git-repo
  /path/to/wolfram-git-install-hooks.sh
  ```
- Automatically:
  1. Copies `wolfram-git-pre-commit` to `.git/hooks/pre-commit` and ensures executable permissions.
  2. Sets `git config filter.wolfram-nb.clean` to the absolute path of `wolfram-git-filter.wls`.
  3. Sets `git config filter.wolfram-nb.smudge cat`.
  4. Sets `git config wolfram.exporterPath` to the absolute path of `wolfram-git-export-formats.wls`.
  5. Sets `git config wolfram.killLspPath` to the absolute path of `wolfram-git-kill-lsp.sh`.
  6. Adds `*.nb filter=wolfram-nb` to `.gitattributes`.

---

### 6. Testing (`tests/run-tests.sh`)
- Automated integration test suite that creates an isolated sandbox Git repository in a subdirectory (`tests/test-sandbox`).
- Verifies:
  1. `wolfram-git-filter.wls` metadata and cache stripping.
  2. `wolfram-git-export-formats.wls` output cell removal for both Markdown and VSNB, plus a `.vsnb` → `Notebook` round-trip check.
  3. End-to-end Git integration via `wolfram-git-install-hooks.sh` and `wolfram-git-pre-commit`.
  4. Automatic staging of `.md`, `.vsnb`, and `.org` files on commit and removal on deletion.
  5. Configurable output formats via `wolfram.exportFormats` (including the Markdown-as-intermediate case for Org-only output).
  6. License exhaustion detection, automatic LSP termination trigger, and recovery.
