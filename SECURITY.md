# Security Policy

## Supported versions

Only the latest release of MacSift receives security fixes. If you're running
an older version, upgrade before reporting — the bug may already be fixed.

| Version | Supported |
|---------|-----------|
| 0.1.x   | ✅        |

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
- Any case where the `neverDeletePrefixes` safety guard can be bypassed.
- Any case where dry-run mode is shown enabled in the UI but a real delete
  actually runs.
- Any case where `FileManager.trashItem` is bypassed and `unlink` is called
  directly on user data.
- Any privilege escalation via the scanner subprocess invocations (`tmutil`).

Bugs that don't match those categories are welcome as regular GitHub issues.

## Response

I'll acknowledge within a few days and discuss a fix / disclosure timeline.
MacSift is a personal project, not a commercial product — there's no SLA.
I'll do my best.
