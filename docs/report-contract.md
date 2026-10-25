# Report contract v1

`scan-summary.json` uses `SchemaVersion: 1` for new scans. Earlier inventory
reports without that field remain accepted by the analyzer.

`python-executables.json` is an array with `Path`, `ResolvedPath`, `FileVersion`,
`Kind`, `IsAlias` and `Bytes`. `FileVersion` may be null and may describe a
launcher/application rather than CPython. Files are matched by conventional
executable names; their contents are not executed or certified as Python.

New scans also record optional `CreationTimeUtc` and `LastWriteTimeUtc`. The
analyzer retains them and adds `FileDateSource`, `RegisteredInstallDate` and
`InstallDateSource`. Older inventories without timestamps are enriched from
the **current metadata of their known executable paths at analysis time**;
inaccessible files retain unknown dates. No drive rescan or interpreter launch
is needed. Filesystem timestamps are not installation dates.

`RegisteredInstallDate` is an installer-supplied `InstallDate` (`yyyyMMdd`)
from a Windows uninstall registration with an explicit `InstallLocation`
containing that executable. The most specific directory wins. Matching never
uses a product name/version guess. The registration's application name and key
are retained as evidence. A value may reflect installation, maintenance or an
update; it is not certified as the original installation time. Store/portable
and other runtimes without matching registration keep an unknown install date.

`python-classification.json` adds `Category`, `RuntimeRoot`, `Evidence`,
`SuggestedAction`, `VenvConfiguration`, `BaseHome`, `ResolvedBaseHome` and
`BaseDirectoryAccessible`. Known directory conventions are heuristics. A
`pyvenv.cfg` relation is stronger evidence of a configured dependency, but it
does not prove that the environment currently runs or is still used.

`runtime-folders.json` groups base/managed/embedded/virtual-environment candidates
by directory. Aliases, templates, caches and backups are not additional runtime
folder groups. `ObservedDependentEnvironments` contains configuration paths
whose resolved home directory matches a runtime folder. `CleanupVerdict` remains
undetermined even when this list is empty.

Runtime groups add `FirstFileCreatedUtc` (the earliest executable creation
timestamp), `LastFileModifiedUtc` (the latest modification timestamp), the most
recent available `RegisteredInstallDate` and all `InstallDateSources`. The HTML
report sorts every table column; runtime/path views initially show newest file
creation timestamps first, with unknown values last. Date times are displayed
in the browser's local timezone; installer dates remain calendar dates.

`command-resolution.json` records priority in the auditor process, not a
universal system-wide ordering. Profiles, activation and shell functions can
change it. Empty extensionless applications are reported, not modified.

A `conda-meta` directory identifies a Conda environment candidate. Where no
stronger directory convention or environment metadata applies, the category is
`unclassified-runtime`; application ownership is not invented.

No output is a deletion plan. Coverage must be interpreted with inaccessible
directories, link targets, explicit exclusions and the final `Completed` flag.
