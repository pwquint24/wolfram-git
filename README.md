# Wolfram Git Utilities

A collection of git utilities for working with Wolfram Language notebooks (`.nb`) in git repositories.

---

## Features

1. **Git Clean Filter for Notebooks (`wolfram-git-filter.wls`)**
   - Automatically cleans `.nb` files when staged (`git add`).
   - Uses Wolfram Research's [`ResourceFunction["SaveReadableNotebook"]`](https://resources.wolframcloud.com/FunctionRepository/resources/SaveReadableNotebook/) to strip transient cache data, window dimensions/margins, cell change timestamps, and internal UUIDs.
   - Formats notebooks into human-readable, multiline indented structures to produce clean, legible git diffs.
   - Falls back safely to original content if processing fails.

2. **Pre-Commit Companion Formats Generator (`wolfram-git-pre-commit` & `wolfram-git-export-formats.wls`)**
   - Automatically runs before each commit (`git commit`).
   - Inspects all staged `.nb` files and generates companion formats:
     - `.md` — Markdown for viewing/diffing in Git web UIs and terminals.
     - `.vsnb` — VS Code notebooks for use with the [official Wolfram Language extension](https://marketplace.visualstudio.com/items?itemName=WolframResearch.wolfram).
     - `.org` — Org mode files for use with sci-wolfram (generated from `.md` via `pandoc`, with the sci-wolfram prologue block prepended).
   - **Automatic license check**: Checks license availability via `wolframscript -code '1+1'`. If licenses are exhausted (e.g. by a background LSP server), it automatically triggers `wolfram-git-kill-lsp.sh` to free a license before proceeding.
   - **Discards output cells** (`Output`, `Message`, `Print`, `Echo`) prior to conversion so that only source content and documentation are rendered.
   - **Zero external image folders**: Images in text/input cells are embedded inline as data URIs (`data:image/png;base64,...`) via `GeneratedAssetLocation -> None`, keeping git repositories free of detached asset directories.
   - Automatically stages the generated companion files into the commit (`git add`).
   - If a notebook is deleted from git, the companion files are automatically staged for removal.
   - **Modular architecture**: Additional formats can be registered in `wolfram-git-export-formats.wls` via the `converters` association.
   - **Configurable output formats**: Set `git config wolfram.exportFormats "md vsnb org"` to control which companions are produced (default: all three). When `org` is requested without `md`, Markdown is still generated as an intermediate and then discarded.

3. **LSP Process Terminator (`wolfram-git-kill-lsp.sh` & `~/LocalDocuments/Scripts/wolfram-git-kill-lsp`)**
   - Convenient script to terminate lingering Wolfram LSP server instances and release Wolfram kernel licenses.

---

## Directory Structure

```
wolfram-git/
├── scripts/
│   ├── wolfram-git-filter.wls          # Git clean filter (wolframscript)
│   ├── wolfram-git-export-formats.wls  # Extensible notebook converter (wolframscript)
│   ├── wolfram-git-md-to-org.sh        # Markdown → Org converter (pandoc wrapper)
│   ├── Mathematica2Jupyter.wl          # Vendored notebook→VS Code converter (code-cell text extraction)
│   ├── wolfram-git-pre-commit          # Git pre-commit hook script
│   ├── wolfram-git-install-hooks.sh    # Automated installer for any repo
│   └── wolfram-git-kill-lsp.sh         # Utility to terminate Wolfram LSP processes
├── tests/
│   └── run-tests.sh                    # Automated integration test suite
├── .gitignore
├── AGENTS.md
└── README.md
```

> **Note:** The scripts do **not** need to reside in a `scripts/` subfolder of target repositories. They can live together in any directory (such as `~/LocalDocuments/Scripts/` or this repository). `wolfram-git-install-hooks.sh` automatically configures git to point to its own directory.

---

## Quick Setup (Automated)

To install the filter and pre-commit hook in any repository:

```bash
cd /path/to/your/git-repo
/path/to/wolfram-git-install-hooks.sh
```

For example, using the scripts in this project:

```bash
cd /path/to/your/git-repo
/Users/andrewpatrick/LocalDocuments/VSCode/Wolfram/wolfram-git/scripts/wolfram-git-install-hooks.sh
```

This script automatically:
1. Copies `wolfram-git-pre-commit` into `.git/hooks/pre-commit` and marks it executable.
2. Configures `git config filter.wolfram-nb.clean` to point to `wolfram-git-filter.wls`.
3. Sets `git config filter.wolfram-nb.smudge cat`.
4. Appends `*.nb filter=wolfram-nb` to `.gitattributes`.
5. Records the path to `wolfram-git-export-formats.wls` in `git config wolfram.exporterPath`.
6. Records the path to `wolfram-git-kill-lsp.sh` in `git config wolfram.killLspPath`.

---

## Manual Setup

If you prefer to configure manually:

1. **Configure the Git Filter**:
   ```bash
   git config filter.wolfram-nb.clean "/path/to/wolfram-git-filter.wls"
   git config filter.wolfram-nb.smudge "cat"
   git config filter.wolfram-nb.required true
   ```

2. **Add to `.gitattributes`**:
   ```gitattributes
   *.nb filter=wolfram-nb
   ```

3. **Install the Pre-Commit Hook**:
   ```bash
   cp /path/to/wolfram-git-pre-commit .git/hooks/pre-commit
   chmod +x .git/hooks/pre-commit
   git config wolfram.exporterPath "/path/to/wolfram-git-export-formats.wls"
   ```

---

## How It Works in Practice

1. You create or edit `analysis.nb` in Mathematica or Wolfram.
2. You stage the file:
   ```bash
   git add analysis.nb
   ```
   *The clean filter runs transparently in the background, stripping UUIDs, timestamps, and window dimensions before writing to git's object store.*
3. You commit:
   ```bash
   git commit -m "Add analysis"
   ```
   *The pre-commit hook intercepts the commit, strips all output cells, exports `analysis.md` (with inline data URIs if images are present), `analysis.vsnb` (a VS Code notebook), and `analysis.org` (converted from `analysis.md`, with the sci-wolfram prologue prepended), stages the requested companions, and includes them in the commit.*

---

## Running the Tests

To verify all components:

```bash
./tests/run-tests.sh
```

This runs a full end-to-end integration test in an isolated sandbox repository:
- Validates metadata and cache stripping via `wolfram-git-filter.wls`.
- Validates output cell removal via `wolfram-git-export-formats.wls` for both Markdown and VSNB, including a `.vsnb` → `Notebook` round-trip check.
- Validates installer and automated companion generation/staging via `wolfram-git-pre-commit`.
- Validates companion removal on notebook deletion.
- Validates configurable output formats via `wolfram.exportFormats`, including the Markdown-as-intermediate case for Org-only output.

---

## Credits

`.vsnb` (VS Code notebook) generation uses a vendored copy of [mathematica2jupyter](https://github.com/divenex/mathematica2jupyter) (© 2025 [divenex](https://github.com/divenex)) for robust Wolfram input-cell text extraction.
