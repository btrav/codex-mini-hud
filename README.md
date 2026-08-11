<h1 align="center">codex-mini-hud</h1>

<p align="center">
  A Claude-style, one-line instrument strip built into the Codex CLI.
</p>

> [!IMPORTANT]
> This is an unofficial community project. It is not affiliated with,
> endorsed by, or supported by OpenAI. Codex and OpenAI are trademarks of
> their respective owners.

```text
✦Codex✦ ▓▓▓▓▓░░░░░  53% · ▮▯▯▯▯ ~55m · 120h 10m · +1079 -239 · ♨3d · ⟳1 · G5.6 · high
```

`codex-mini-hud` is a small, auditable patch against a pinned official Codex
release. It installs as a separate `codex-hud` command. Your official `codex`
command remains untouched and available as an immediate fallback.

## Quick start

1. Clone this repository, then download the archive and adjacent `.sha256` file
   for your Mac from [GitHub Releases](https://github.com/btrav/codex-mini-hud/releases).
   Choose `aarch64-apple-darwin` for Apple Silicon or `x86_64-apple-darwin` for Intel.
2. From the repository checkout, install the downloaded archive:

   ```bash
   ./install.sh --archive ~/Downloads/codex-mini-hud-<version>-<architecture>.tar.gz
   ```

3. Confirm the installed package, then start Codex with the HUD:

   ```bash
   ~/.local/bin/codex-hud --hud-doctor
   ~/.local/bin/codex-hud
   ```

   Add `~/.local/bin` to your `PATH` if you want to run `codex-hud` directly.

The installer validates the checksum, architecture, and canonical Codex package
contents before switching the active package. It never replaces `codex`.

## What it shows

- `✦Codex✦` — bright identity marker that stays visible on dark backgrounds
- Ten-cell context bar — percentage of the current model context used
- Five-cell allowance battery — the signed-in user/seat's primary rate-limit
  bucket, with a reset countdown when allowance is low
- CLI runtime — wall-clock time since the `codex-hud` process started
- `+added -removed` — cumulative edit churn observed from Codex turn diffs
- `♨3d` — signed-in account streak, with a local calendar-day fallback
- `⟳1` — context compactions in the current or resumed thread
- Compact model name and a separate reasoning-effort field
- Conditional `fast`, `!full access!`, and `!credits!` signals

Context colors follow green below 70%, amber from 70–89%, and red from 90%.
Allowance is green at 25% or more remaining, amber at 11–24%, and red at 10%
or less. The line automatically drops lower-priority fields and shortens its
bars for medium and narrow terminals; it never intentionally wraps.

On a managed Business workspace, the battery is not team-wide usage. It uses
the effective primary rate-limit window returned for the currently authenticated
workspace user/seat. Workspace spend controls are surfaced separately as a
critical warning. The account streak likewise comes from the signed-in account,
not an aggregate of the team.

## Why a separate binary?

A binary is the compiled, runnable Codex program—the native file your Mac
executes after the Rust source code is built. The custom bars and live metrics
must run inside Codex's terminal renderer, so this project compiles a modified
copy of Codex and launches it as `codex-hud`. The HUD itself is small; release
archives are large because they contain the complete Codex executable plus its
code-mode host, ripgrep, zsh, and runtime resources.

Stock Codex supports an ordered list of built-in footer fields, but it cannot
render custom literals, multi-color bars, responsive composite fields, process
runtime, account streak, or compaction count. This repository therefore builds
a private canonical Codex package and exposes it as `codex-hud`.

The package still uses the same `~/.codex` authentication, config, policies,
skills, plugins, and session data as official Codex. The tradeoffs are:

- HUD releases must be rebuilt when the pinned Codex release changes.
- The binary is not the official OpenAI-distributed artifact, so managed-device
  allowlists may require administrator approval.
- Release archives are intentionally not Apple-signed or notarized, so macOS or
  managed-device policy may warn about or block them.

The patch and exact upstream commit are checked into this repo, so the delta is
reviewable. No transcript, rollout, or prompt parsing is used.

## Build

Requirements: macOS, Git, Python 3.10+, Rust as required by upstream Codex, and
network access for pinned build dependencies.

The first optimized build compiles the full canonical Codex package and can
take substantial time and temporary disk space. Release users should generally
prefer the target-specific archives published on GitHub Releases.

```bash
./scripts/build.sh
```

The build script:

1. checks out the exact commit in [`upstream.lock`](upstream.lock);
2. verifies and applies [`patches/0001-codex-mini-hud.patch`](patches/0001-codex-mini-hud.patch);
3. invokes Codex's official canonical package builder; and
4. writes a target-specific archive and SHA-256 checksum under `dist/`.

The canonical package includes `codex`, `codex-code-mode-host`, ripgrep, its
manifest, and upstream runtime resources. This is important: copying only the
`codex` executable would break package detection and code-mode host discovery.

## Install

Install a locally built package directory:

```bash
./install.sh --package-dir /path/to/canonical/package
```

Or install a release archive with its adjacent `.sha256` file:

```bash
./install.sh --archive dist/codex-mini-hud-1.1.0-codex-0.146.0-aarch64-apple-darwin.tar.gz
```

The default locations are:

```text
~/.local/share/codex-mini-hud/current
~/.local/bin/codex-hud
~/.local/state/codex-mini-hud/activity
```

Add `~/.local/bin` to `PATH`, then start:

```bash
codex-hud
```

Inspect the official and patched versions and their paths:

```bash
./scripts/doctor.sh
codex-hud --hud-doctor
```

The installer validates checksums and canonical package contents, refuses
symlinks and foreign launchers, takes an install lock, smoke-tests the staged
binary, and atomically switches the `current` package. It never overwrites
`codex`.

Uninstall only the patched command and its active release:

```bash
./uninstall.sh
```

### Advanced fallback: stock Codex footer preset

The earlier `--native` preset configures only Codex's built-in footer fields.
It does not provide custom bars, runtime, streak, or compaction metrics. Use it
only when a managed device cannot run the separate patched binary:

```bash
./install.sh --native
./uninstall.sh --native
```

## Troubleshooting

### macOS asks for “Codex MCP Credentials” in Keychain

`codex-hud` is a separately built executable that uses the same MCP OAuth
tokens as official Codex. macOS can therefore ask for permission when it first
accesses the `Codex MCP Credentials` Keychain item. Confirm the launcher and
package with `codex-hud --hud-doctor` before approving.

Choose **Allow** for a cautious first run; **Always Allow** trusts the current
HUD build for future access. Denying the request does not affect the HUD itself
or your official Codex command, but authenticated MCP services may need to
reauthenticate. Enter your Mac password only in the macOS system dialog—never
in Codex, a terminal prompt, or a chat.

## Development and verification

```bash
./test.sh
./test-package.sh
```

The Bash suites use isolated temporary homes. Rust tests live with the patch and
cover context and quota thresholds, diff counting, responsive fitting, duration,
and compact formatting.

For a clean upstream checkout:

```bash
git apply --check patches/0001-codex-mini-hud.patch
git apply patches/0001-codex-mini-hud.patch
cd codex-rs
just test -p codex-tui
```

## Metric caveats

- Added/removed values are cumulative turn-level edit churn, matching the most
  useful interpretation of Claude's session counter. Editing the same line in
  multiple turns can count it more than once. Historical churn is unavailable
  when resuming an older thread because Codex does not persist an exposed
  session-total field.
- Runtime is CLI process time, not the age of a resumed thread.
- The primary allowance window is server-defined; managed accounts should not
  assume it is always literally five hours.
- Account streak is nullable or unavailable for API-key-only providers. The
  launcher maintains a local day streak as a fallback.
- Each upgrade removes previously installed, HUD-owned package releases after
  the new package and launcher pass validation. This prevents full Codex
  packages from accumulating on disk.

## Compatibility and support

- macOS only: Apple Silicon (`arm64`) and Intel (`x86_64`).
- The current patch targets exactly Codex 0.146.0 at the commit recorded in
  [`upstream.lock`](upstream.lock).
- Account-only fields can be absent with API-key authentication or when the
  service does not return the corresponding account data.
- Managed-device policy may block unofficial executables.
- Reproduce Codex problems with the official `codex` command before reporting
  them upstream. OpenAI Support does not support this patched distribution.

See [`docs/FEASIBILITY.md`](docs/FEASIBILITY.md) for architecture details and
the comparison with other Codex HUD projects.

## License

The project-owned launcher, installer, tests, and documentation are MIT
licensed; see [`LICENSE`](LICENSE). The patched OpenAI Codex program remains
under Apache 2.0 and its upstream component licenses. See
[`LICENSES/Apache-2.0.txt`](LICENSES/Apache-2.0.txt), [`NOTICE`](NOTICE), and
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
