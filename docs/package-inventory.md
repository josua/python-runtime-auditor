# Packages by environment

The auditor reads installed distribution metadata without launching Python, pip
or package code. This is an independent implementation of the public
[PyPA installed-project format](https://packaging.python.org/en/latest/specifications/recording-installed-packages/)
and [core metadata format](https://packaging.python.org/en/latest/specifications/core-metadata/).

## Find the environment containing a package

Open **Packages** and search for `open-webui`, `torch` or `transformers`. Each row
retains its environment, distribution version and metadata path. Use the
environment selector to narrow the results, or **View packages** in Runtime
folders. Same-name packages, including different versions, are never merged.
All column headings sort; estimated sizes sort numerically, with unknowns last.
Runtime folders also provides a **Microsoft Store** quick filter and explicit
Store labels. Store package paths and executable file versions identify those
rows; missing installer registry dates remain unknown, so sorting by installation
date can put them after older installations with known dates.

**Package coverage** lists examined locations and their status. **Package
issues** explains unreadable, linked, oversized or malformed metadata. Zero
metadata entries means none were found in the examined locations; it does not
prove that Python cannot import anything.

## Refresh packages without scanning drives

For an existing analyzed report, these **two steps form one refresh**. Replace
the example report path with yours:

```powershell
.\scripts\inventory-python-packages.ps1 -ReportDirectory 'D:\python-audits\my-scan'
.\scripts\new-audit-report.ps1 -ReportDirectory 'D:\python-audits\my-scan'
```

Then open its `report.html`. The package stage uses `runtime-folders.json`; it
does not repeat executable discovery. A normal full audit also includes this
stage automatically. Package observations reflect refresh time, which can differ
from the earlier executable scan time.

## Location coverage

For each known runtime the inventory examines `Lib\site-packages`,
`site-packages`, and `lib\python3.*\site-packages` layouts used by some Windows
application bundles. This does not add Linux/WSL support.

It also discovers conventional current-user sites under `%APPDATA%\Python`,
`PYTHONUSERBASE` when set, and Microsoft Store Python's
`%LOCALAPPDATA%\Packages\PythonSoftwareFoundation.Python.3.*\LocalCache\local-packages`.
These appear as **separate shared user-site candidates**. They are not silently
assigned to every interpreter with a similar version. User-site discovery reads
these bounded locations even when executable discovery used narrower `-Roots`.
Use `-SkipUserSitePackages` with the main launcher, analyzer or package inventory
to omit them. The package inventory also accepts `-UserSiteRoots` for explicit
user-site directories (an empty array disables automatic discovery).

Base-site inheritance, `include-system-site-packages`, `.pth`, `.start`,
`PYTHONPATH`, custom startup hooks, archives and editable project sources are
not resolved. Other users' profiles are not searched for user sites. Linked
package metadata and linked package-location ancestors are skipped with issues;
there is no recursive package-content scan. Presence is not a successful import
test. `Requires-Dist` entries retain their raw markers/extras and are not an
evaluated or resolved dependency graph.

## What the size means

`EstimatedBytes` sums nonnegative sizes declared in CSV `RECORD` entries, without
opening the referenced files. Quoted CSV fields are supported. Duplicate paths,
malformed rows and values that overflow a signed 64-bit sum are excluded and
reported. Individual metadata reads are limited to 4 MiB and RECORD to 32 MiB.

- **Complete**: every unique accepted RECORD entry supplies a usable size and
  no malformed/duplicate entries were encountered. This is completeness of the
  *declarations*, not a filesystem integrity guarantee.
- **Partial**: some usable sizes, but blank or invalid declarations remain.
  RECORD itself and bytecode commonly have blank sizes.
- **Unavailable**: no usable size declaration. Unknown stays null; a valid
  zero-byte declaration stays zero.

These are logical declared bytes, **not measured disk allocation, integrity
checks or reclaimable space**. Unlisted/modified files, caches, external editable
sources and files shared by packages can change the relationship to disk usage.
Legacy `.egg-info` / `PKG-INFO` entries usually have no estimate. Names and
versions come from metadata; missing values are not guessed from folder names.

## Outputs (package schema v1)

| File | Data |
| --- | --- |
| `python-packages.json` / `.csv` | One row per metadata location and environment; name, version, summary, requirements, metadata path and size evidence |
| `package-environments.json` | Scope IDs/roots/categories, entry counts, known size totals, scanned locations and issue counts |
| `package-locations.json` | Each candidate location, environment ID, status and metadata entry count |
| `package-issues.json` | Path, operation and failure/exclusion reason |
| `package-summary.json` | Schema version, UTC refresh date, elapsed time, counts and scope/size limits |

The HTML generator also accepts older reports without these files. It shows an
explicit package-inventory-unavailable message instead of inventing empty results.
Real reports remain private and ignored by Git. Only synthetic data is published.
