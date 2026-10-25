# Contributing

Keep the scanner and analyzer read-only. New classifiers should state their
evidence and have a test; path heuristics must not become claims of verified
ownership or non-use. Do not add implicit interpreter execution or deletion.

Use lowercase English kebab-case filenames, preserve upstream format names,
and run `pwsh -NoProfile -File tests/run-tests.ps1` before proposing a change.

When reporting a bug, include PowerShell/Windows versions, the command, and a
small redacted example. Do not upload a full private inventory by default.

Document AI assistance and human contributions accurately. The initial code was
written by SolGPT 6.1; future contributions should carry their own attribution.
