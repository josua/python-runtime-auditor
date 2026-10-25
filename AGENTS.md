# Project guidance

- Keep authored filenames lowercase English kebab-case. `AGENTS.md`, `LICENSE`
  and Python's `pyvenv.cfg` are tool/format exceptions.
- This release targets Windows and PowerShell 7.2+. Do not claim Linux/WSL coverage.
- Inspect the existing implementation and preserve the read-only default.
- Do not execute discovered interpreters or add uninstall/PATH mutations implicitly.
- Distinguish filename matches, file-version metadata, inferred ownership and
  observed `pyvenv.cfg` dependencies. No observed dependent does not mean unused.
- Never commit real inventory reports, machine paths, credentials or binaries.
- Run `pwsh -NoProfile -File tests/run-tests.ps1` after meaningful changes.
- Preserve the attribution in `authors.md` and the report footer.
