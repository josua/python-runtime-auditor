# Report browser launcher

`-OpenReport` now opens the completed offline report through `open-audit-report.ps1`.
It does not start a web server, install a PWA or rescan Python installations.
The CMD auditor already passes `-OpenReport`. The separate `open-audit-report.cmd`
reopens the latest completed HTML report under this repository's `reports` folder.

## Choose one command

These examples are **independent alternatives**. Run only the one you need.

**Discover browsers, without opening anything:**

```powershell
.\open-audit-report.ps1 -ListBrowsers
```

**Reopen the latest local report, automatically choosing a viewer:**

```powershell
.\open-audit-report.ps1
```

**Open an existing report in a Chrome application window:**

```powershell
.\open-audit-report.ps1 -ReportPath 'D:\python-audits\my-scan\report.html' -Browser chrome
```

**Use a portable Chromium installation not registered with Windows:**

```powershell
.\open-audit-report.ps1 -ReportPath 'D:\python-audits\my-scan\report.html' -BrowserPath 'D:\Tools\Chromium\chrome.exe'
```

**Choose another disk for the dedicated browser profile and cache:**

```powershell
.\open-audit-report.ps1 -BrowserDataDirectory 'D:\python-auditor-browser-data'
```

**Keep the ordinary Windows HTML association:**

```powershell
.\open-audit-report.ps1 -Browser default
```

**Run a new audit and open its report using Edge:**

```powershell
.\start-python-runtime-auditor.ps1 -Roots 'C:\Dev' -OpenReport -ReportBrowser edge
```

**Preview a launch command without starting a browser or creating a profile:**

```powershell
.\open-audit-report.ps1 -ReportPath 'D:\python-audits\my-scan\report.html' -Browser chrome -WhatIf -PassThru
```

Replace example paths with your own. `-ReportBrowserPath` and
`-BrowserDataDirectory` are also supported by the auditor when using `-OpenReport`.
An explicit browser or executable path reports a failure rather than silently
switching to a different browser. Automatic selection retries other candidates.

## Discovery and launch behavior

Discovery reads both user and machine `App Paths` and `StartMenuInternet`
registrations in the 32-bit and 64-bit registry views, common installation
directories, and executable entries on PATH. It checks that files exist and
deduplicates paths. It does not execute browsers to discover them or scan whole
drives. Arbitrary portable locations need `-BrowserPath`.

| Browser | Automatic order | Launch mode |
| --- | --- | --- |
| Microsoft Edge | 1 | Chromium `--app` window |
| Google Chrome | 2 | Chromium `--app` window |
| Chromium | 3 | Chromium `--app` window |
| Brave | 4 | Chromium `--app` window |
| Firefox | 5 | Ordinary `--new-window` window |
| Vivaldi | 6 | Ordinary URL opening; app mode not assumed |
| Opera | 7 | Ordinary URL opening; app mode not assumed |
| Windows default HTML application | Last resort | Whatever the HTML association provides |

Chromium-family app launches use `--user-data-dir`, `--disk-cache-dir`, a 64 MiB
disk-cache size hint, `--disable-sync`, `--no-first-run`,
`--no-default-browser-check`, `--disable-features=Translate` and `--app` with the
report's `file:` URI. `Translate` replaces the obsolete `TranslateUI` feature name
in current Chromium; vendor-specific prompts may still differ. Profiles
are separated by browser name and a hash of the executable path, so different
channels/installations do not share a profile. Reopening uses the same dedicated
profile. Close its windows before manually moving/removing its data directory.
Fallback windows can use an existing personal browser session.

The launcher detects process-start failures and nonzero exits within 1.5 seconds.
A successful process start or a zero exit can mean the URL was forwarded to an
existing browser instance; it is **not** a rendering or app-mode verification.
Browser policy, startup prompts and future flag changes may affect presentation.
It never closes existing browser sessions or changes the default browser.

## Sources and verification

- [Windows application registration](https://learn.microsoft.com/en-us/windows/win32/shell/app-registration)
  documents the per-user and machine App Paths locations.
- [Chromium command-line switches](https://www.chromium.org/developers/how-tos/run-chromium-with-flags/)
  and [user data directories](https://chromium.googlesource.com/chromium/src/+/main/docs/user_data_dir.md)
  describe flags and profile separation.
- [Brave command-line flags](https://support.brave.app/hc/en-us/articles/360044860011-How-Do-I-Use-Command-Line-Flags-in-Brave)
  includes the application-mode switch.
- [Firefox command-line parameters](https://firefox-source-docs.mozilla.org/browser/CommandLineParameters.html)
  documents `--new-window`; the launcher does not assume Chromium flags work in Firefox.
- [Chrome launcher flags](https://github.com/GoogleChrome/chrome-launcher/blob/main/docs/chrome-flags-for-tools.md)
  documents the replacement of `TranslateUI` by `Translate`.

Automated tests cover safe local-URI conversion, command extraction, profile
separation, preview mode, automatic retry and explicit-choice failures without
starting browsers. A process launch alone does not certify UI compatibility for
every browser version.
