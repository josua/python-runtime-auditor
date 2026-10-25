# Report contract v1

`scan-summary.json` uses `SchemaVersion: 1` for new scans. Earlier inventory
reports without that field remain accepted by the analyzer.

`python-executables.json` is an array with `Path`, `ResolvedPath`, `FileVersion`,
`Kind`, `IsAlias` and `Bytes`. `FileVersion` may be null and may describe a
launcher/application rather than CPython. Files are matched by conventional
executable names; their contents are not executed or certified as Python.

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

`command-resolution.json` records priority in the auditor process, not a
universal system-wide ordering. Profiles, activation and shell functions can
change it. Empty extensionless applications are reported, not modified.

A `conda-meta` directory identifies a Conda environment candidate. Where no
stronger directory convention or environment metadata applies, the category is
`unclassified-runtime`; application ownership is not invented.

No output is a deletion plan. Coverage must be interpreted with inaccessible
directories, link targets, explicit exclusions and the final `Completed` flag.
