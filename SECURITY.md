# Security Policy

## Supported versions

Only the latest release of MacSift receives security fixes. If you're running
an older version, upgrade before reporting — the bug may already be fixed.

| Version | Supported |
|---------|-----------|
| 0.2.x   | ✅        |
| 0.1.x   | ❌        |

## Reporting a vulnerability

MacSift touches the filesystem and can delete data. If you find a bug that
could lead to data loss, privilege escalation, or unintended deletion:

**Please do not open a public GitHub issue.** Instead, report it privately:

- Open a [private security advisory](https://github.com/Lcharvol/MacSift/security/advisories/new)
  on GitHub, or
- Email the repository owner through their GitHub profile.

Include:
1. A short description of the issue and its impact.
2. A reproducer — the smallest scenario that triggers the problem.
3. The macOS version and `swift --version` output you tested on.
4. Whether you've tried to verify the issue on the latest `main`.

## What counts as a security issue

- Any path traversal / directory escape that could cause MacSift to delete
  files outside its scanned roots.
- Any case where the `neverDeletePrefixes` safety guard can be bypassed —
  including via unusual path encodings (double slashes, `..`, single-dot
  segments, or case-insensitive volumes).
- Any case where dry-run mode is shown enabled in the UI but a real delete
  actually runs.
- Any case where `FileManager.trashItem` / `NSWorkspace.recycle` is bypassed
  and `unlink` is called directly on user data.
- Any privilege escalation via the scanner subprocess invocations (`tmutil`,
  `ditto`).
- Any way to make the in-app update pipeline download from an untrusted
  host, run an arbitrary subprocess, or stage a bundle whose
  `CFBundleIdentifier` isn't `com.macsift.app`.

Bugs that don't match those categories are welcome as regular GitHub issues.

## Known limitations

MacSift is ad-hoc signed (no paid Apple Developer ID) and the in-app
update pipeline trusts GitHub's TLS for authenticity. Specifically:

- **Compromised-repo risk.** If the `Lcharvol/MacSift` repository itself
  is compromised (stolen token, social engineering), an attacker could
  publish a malicious release. The in-app update flow validates the
  download URL is on an allowed GitHub host, verifies the byte count
  matches the release metadata, and checks the extracted bundle's
  `CFBundleIdentifier` — but it does NOT verify a cryptographic
  signature against a pinned public key. Proper mitigation requires
  Sparkle-style signed appcast and is tracked as future work.
  Until then: if you're paranoid, build from source (Option B in the
  README) or manually verify the release on github.com before running
  the downloaded `.app`.
- **TOCTOU during cleanup.** Between the `fileExists` check and the
  `trashItem` / `NSWorkspace.recycle` call, a racing process running
  as the same user could swap the file with a symlink to somewhere
  else. The racing process already has user-level privileges, so
  there's no escalation, but the trashed target may differ from what
  the UI showed. Fully fixing this requires kernel-level transactional
  support that macOS doesn't expose.
- **File paths in `~/Library/Logs/MacSift/macsift.log`.** The log
  intentionally records scan/clean summaries and per-file failure
  reasons. Anyone who reads that file (it's user-owned, not
  world-readable) sees the paths MacSift touched. The unified `os_log`
  stream, in contrast, marks those messages `.private` so file paths
  don't leak to Console.app.

## Response

I'll acknowledge within a few days and discuss a fix / disclosure timeline.
MacSift is a personal project, not a commercial product — there's no SLA.
I'll do my best.
