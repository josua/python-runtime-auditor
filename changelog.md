# Changelog

## Unreleased

- Detect installed browsers and open reports in a Chromium application window,
  with dedicated profile/cache directories and ordinary-window fallbacks.
- Reopen an existing report without scanning via `open-audit-report.cmd` or `.ps1`.
- List browsers, choose a browser/portable executable, customize browser data
  location, and preview launch arguments without starting a browser.
- Clarify independent launch examples and include `-OpenReport` consistently.

## 0.1.0 — 2026-10-25

- Windows filesystem scanner with junction-cycle protection and coverage reports.
- CSV/JSON/JSONL inventory, classification and base-runtime dependency analysis.
- Command-routing inspection and empty extensionless-file findings.
- Offline searchable HTML report.
- Original implementation and documentation by SolGPT 6.1, requested by Philippe Jos.
