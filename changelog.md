# Changelog

## 0.3.1 — 2026-10-25

- Integrate the user-supplied Python snakes / magnifying-glass project mark in
  the README, banner, website favicon, offline report header and report favicon.
- Correct the supplied SVG namespace and intrinsic dimensions while preserving
  its artwork, and keep the report's project mark embedded inline.

## 0.3.0 — 2026-10-25

- Static package inventory per runtime, with names, versions, metadata paths,
  raw dependency declarations and estimated logical sizes from RECORD.
- Separate current-user package scopes, including Microsoft Store Python sites.
- Search/filter/sort packages, open an environment's packages from Runtime folders,
  and inspect package location coverage and metadata issues.
- Refresh package observations from an existing inventory without rescanning drives.
- Legacy egg-info support, bounded metadata reads, linked metadata exclusions and
  explicit unknown/partial size evidence; no Python, pip or startup code execution.
- Updated offline/public synthetic demo, documentation and focused regression tests.
- Readable Microsoft Store Python labels and a quick filter, without substituting
  file creation timestamps for unknown registry installation dates.

## 0.2.0 — 2026-10-25

- Detect installed browsers and open reports in a Chromium application window,
  with dedicated profile/cache directories and ordinary-window fallbacks.
- Reopen an existing report without scanning via `open-audit-report.cmd` or `.ps1`.
- List browsers, choose a browser/portable executable, customize browser data
  location, and preview launch arguments without starting a browser.
- Clarify independent launch examples and include `-OpenReport` consistently.
- Inline Tabler SVG icons in offline reports, with retained licensing.
- Sortable report columns, UTC file timestamps and separate installer registry
  dates with explicit sources; older inventories can be enriched without rescanning.
- Visual README, Skill Icons tiles, project banner and repository badges.
- Public GitHub Pages project website with a synthetic interactive demo,
  canonical/social metadata, SoftwareApplication structured data and sitemap.

## 0.1.0 — 2026-10-25

- Windows filesystem scanner with junction-cycle protection and coverage reports.
- CSV/JSON/JSONL inventory, classification and base-runtime dependency analysis.
- Command-routing inspection and empty extensionless-file findings.
- Offline searchable HTML report.
- Original implementation and documentation by SolGPT 6.1, requested by Philippe Jos.
