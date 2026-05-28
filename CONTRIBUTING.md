# Contributing to MacSift

Thanks for thinking about contributing. MacSift is a small, opinionated
project — small enough that it's worth reading this whole file before
opening a PR. It will save both of us time.

## TL;DR

```bash
git clone https://github.com/Lcharvol/MacSift.git
cd MacSift
swift test         # 220+ tests, must stay green
./build-app.sh     # produces MacSift.app at the repo root
open MacSift.app
```

PRs should target `main`, keep `swift test` green, and respect the
conventions in [`CLAUDE.md`](CLAUDE.md) — that file is where the
*why* lives.

## Ground rules

- **Read [`CLAUDE.md`](CLAUDE.md) first.** It documents the performance
  rules, safety invariants, and style choices that are *not* obvious from
  reading the code. Several past PRs were rejected because they undid
  optimizations or safety checks that aren't visible without context.
- **The bar is "safe and transparent."** MacSift's promise to users is
  that nothing gets permanently deleted and every action is shown. A PR
  that lowers that bar — even by accident — won't land.
- **Small, focused PRs.** One change per PR. Unrelated cleanup is a
  separate PR.
- **No new dependencies.** The app is intentionally dependency-free
  (zero runtime, zero build-time) outside the Swift standard library
  and Apple frameworks. If you think you need a dependency, open an
  issue first to discuss.

## Before you open a PR

If your change is more than a one-line fix, please open an issue first
so we can agree on the approach. Use the
[bug report](https://github.com/Lcharvol/MacSift/issues/new?template=bug_report.yml)
or
[feature request](https://github.com/Lcharvol/MacSift/issues/new?template=feature_request.yml)
template. PRs that match a discussed issue land much faster than
surprise PRs.

Good first issues are labeled
[`good first issue`](https://github.com/Lcharvol/MacSift/labels/good%20first%20issue).

## Development setup

### Prerequisites

- **macOS 15 (Sequoia) or later** to run the app. macOS 26 (Tahoe) is
  the target for Liquid Glass features but everything still works on 15.
- **Xcode 26 command-line tools** — `xcode-select --install`. Swift 6.0+
  is required (the project pins `swift-tools-version: 6.0`).
- **No Xcode project file.** MacSift is built with SwiftPM. You can open
  `Package.swift` in Xcode if you prefer that workflow, but the source
  of truth is `swift build` / `swift test` from the command line.

### Common commands

```bash
swift build                              # type-check only (fast)
swift test                               # full suite (~1 second)
swift test --filter FileGrouper          # one suite
./build-app.sh                           # debug .app bundle
./build-app.sh release                   # release-optimized build
```

`build-app.sh` produces a proper `.app` bundle (with `Info.plist` and
`AppIcon.icns`) from the SwiftPM build output and ad-hoc signs it for
stable Full Disk Access identity. See the script for what each step does.

### Project layout

```
MacSift/
├── App/         # MacSiftApp entry point + AppState
├── Models/      # ScannedFile, ScanResult, FileGroup — pure Sendable structs
├── Services/    # DiskScanner, CategoryClassifier, FileGrouper, CleaningEngine, …
├── ViewModels/  # ScanViewModel, CleaningViewModel — @MainActor classes
├── Views/       # SwiftUI views
└── Utilities/   # Formatting, descriptions, bundle-id helpers
```

Keep it flat. No subframeworks, no per-category subfolders.

## Style and conventions

These are the rules that catch the most reviewer comments. The longer
explanations live in [`CLAUDE.md`](CLAUDE.md); the short list is here.

- **MVVM, strictly.** Views render state and call methods. They never
  reach into services.
- **Models are `struct` + `Sendable`.** No reference types in the data
  flow.
- **ViewModels are `@MainActor final class`.** Heavy work hops off the
  main actor via `Task.detached`.
- **Use the `compatGlassEffect` / `compatGlassButtonStyle` helpers**
  instead of `.glassEffect` / `.buttonStyle(.glass)` directly — those
  only exist on macOS 26.
- **No `design: .rounded` fonts.** System semibold is the house style.
- **No gradients.** Use `.tint`, `.accentColor`, and system materials.
- **No `.contextMenu` on row views in lists.** It's expensive at scale.
  Put per-row actions in the inspector panel instead.
- **Use `.monospacedDigit()` on numbers that update frequently.**
- **`@Published` mutations in tight loops freeze the UI.** Build the new
  value locally, then assign once.

## Safety invariants (do not weaken)

These are non-negotiable. If your PR changes one of them, expect a long
review and a high bar.

- **Deletions go to the Trash via `FileManager.trashItem`.** Never
  permanent removal.
- **Dry run is on by default for first-time users.**
- **Destructive cleaning requires an explicit alert confirmation** when
  Dry Run is off.
- **`CleaningEngine.neverDeletePrefixes`** blocks `/System`, `/usr`,
  `/bin`, `/sbin`. Add to it before adding new scanned roots.
- **The classifier never flags installed apps' Application Support
  folders** as `.appData`. Only orphaned ones.

## Tests

- **All tests must pass** (`swift test`). Currently 220+ tests across
  37+ suites.
- **Tests use Swift Testing** (`@Test`, `@Suite`, `#expect`), not
  XCTest. New tests follow the same style.
- **Integration tests use real temp directories** under
  `FileManager.default.temporaryDirectory`. Never touch the real home
  or the real Trash from a test.
- **If you add a new file category**, add a `CategoryClassifier` test
  for both the positive case and at least one negative ("this should
  NOT match").
- **If you touch the scanner, the engine, or `FileGrouper`**, run the
  performance suite (`swift test --filter "Scan Performance"`) and
  confirm it still passes.
- **If you change a user-facing string**, update all three
  `.lproj/Localizable.strings` files (`en`, `fr`, `zh-Hans`). Tests
  that assert against strings should pin a locale explicitly
  (`L10n.setLanguage(.english)`) so they don't depend on the host
  machine.

## Commit messages

Loosely conventional, lowercase, imperative mood:

```
feat: per-app inspector with reveal-in-Finder
fix: app crashed on launch in release builds (#6)
perf: avoid sorting in View.body for category switches
docs: CHANGELOG entry for 0.4.1
polish: align toolbar icon weights
```

Allowed prefixes: `feat`, `fix`, `perf`, `polish`, `chore`, `docs`,
`refactor`, `test`, `build`. Keep the subject line under 70 chars.
Body is optional but welcome — explain the *why*, not the *what*.

## Opening the PR

PRs use [`pull_request_template.md`](.github/pull_request_template.md).
The checklist is short on purpose:

- `swift test` passes locally
- `swift build` is clean — no new warnings
- UI changes tested on macOS 26 Tahoe (Sequoia fallback verified if the
  change touches a Liquid Glass API)
- Safety-relevant changes were reviewed against `CleaningEngine.swift`
- `CHANGELOG.md` updated under `[Unreleased]`
- No gradients, no `design: .rounded`, no per-row context menus

If your PR fixes a known issue, reference it (`Fixes #6`) so it
auto-closes on merge.

## Release process

You probably don't need to do this — it's documented for completeness.

1. Move `[Unreleased]` entries in [`CHANGELOG.md`](CHANGELOG.md) under
   a new `[X.Y.Z] — YYYY-MM-DD` heading and commit.
2. `swift test` — must be green.
3. `git tag -a vX.Y.Z -m "MacSift X.Y.Z — <one-line summary>"`
4. `./build-app.sh release`
5. `ditto -c -k --keepParent MacSift.app /tmp/MacSift.zip` and copy to
   both `MacSift.zip` (versionless deep-link) and `MacSift-X.Y.Z.zip`.
6. `git push origin main vX.Y.Z`
7. `gh release create vX.Y.Z /tmp/MacSift.zip /tmp/MacSift-X.Y.Z.zip ...`
8. Bump the Homebrew cask version at
   [`Lcharvol/homebrew-macsift`](https://github.com/Lcharvol/homebrew-macsift).

SemVer applies: patch for bug-fix-only, minor for new features, major
for breaking changes to user-facing behavior or removed categories.

## Reporting a security issue

Please **don't** open a public issue for security-relevant bugs (the
classifier flagging something it shouldn't, a deletion path that
escapes the Trash, a way to bypass the dry-run check, etc.). Email
[charvolin0@gmail.com](mailto:charvolin0@gmail.com) instead and I'll
respond within a few days. Once a fix is shipped we can credit you in
the changelog.

## License

By contributing, you agree that your contributions are licensed under
the [MIT License](LICENSE) that covers the rest of the project.

---

Thanks again. The full set of conventions, performance lessons, and
historical context is in [`CLAUDE.md`](CLAUDE.md) — that file pays for
itself every time you go to change something non-trivial.
