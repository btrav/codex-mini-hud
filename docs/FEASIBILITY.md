# Codex Mini HUD architecture

Research target: Codex CLI 0.146.0 on macOS, August 2026.

## Capability decision

Codex's supported `tui.status_line` setting accepts only an ordered list of
built-in item identifiers. It does not accept literal text, templates, custom
glyphs, multi-style bars, third-party render callbacks, or process commands.
The native fields also do not expose process runtime, account streak, or
compaction count.

That makes the requested Claude-style instrument strip impossible as a stock
configuration preset. Version 1 uses a small opt-in patch in `codex-tui` and
ships it as a separate canonical package.

| Signal | Direct source in patched Codex |
|---|---|
| Context used | `TokenUsageInfo` and the model's effective context window |
| Primary allowance | authenticated `account/rateLimits/read` snapshot |
| Reset ETA | primary window reset epoch |
| Runtime | launcher process epoch, preserved across thread switches |
| Lines added/removed | live aggregated `TurnDiffUpdated` events |
| Streak | `account/usage/read.summary.currentStreakDays`, then local fallback |
| Compactions | canonical v2 `ThreadItem::ContextCompaction` items |
| Model / effort | active `ChatWidget` model and reasoning configuration |
| Fast | active service tier |
| Full access | effective disabled permission profile |
| Credits warning | workspace spend-control/reached state |

The patch does not parse rollout JSONL, transcripts, prompts, responses, or tool
output. Numeric HUD state comes from the same live data already held by the TUI.

## Distribution boundary

The repository stores:

- an exact upstream tag and commit in `upstream.lock`;
- one ordered patch under `patches/`;
- deterministic build orchestration around the upstream package builder;
- a private `codex-hud` launcher and transactional installer.

The installed package keeps the upstream canonical layout, including
`bin/codex`, `bin/codex-code-mode-host`, `codex-path/rg`, the package manifest,
and runtime resources. The launcher enables the HUD with environment variables
and otherwise delegates arguments unchanged.

The official Codex executable is never shadowed or replaced. This is an
intentional difference from projects that put a patched `codex` shim first in
`PATH`.

## Managed Business accounts

The primary battery is the effective bucket returned for the authenticated
user/seat. It is not a team-wide counter. Its window length is server-defined,
so the UI does not label it “5h.” Workspace credits and spend controls are
separate and appear only as a critical condition.

`currentStreakDays` is likewise the signed-in account's activity value. It may
be unavailable for API-key-only providers or some account states. The launcher
keeps a minimal local calendar-day streak so the field remains useful offline.

## Comparison with other HUD projects

| Project | Surface | Data strategy | Main tradeoff |
|---|---|---|---|
| [Jiawang1209/codex-hud](https://github.com/Jiawang1209/codex-hud) | Patched footer, watch mode, or tmux | Node tool reads config/session metadata; installer can put a patched `codex` shim first | Broad cross-platform feature set, but more runtime dependencies and local session parsing |
| [WinningBean/codex-vitals](https://github.com/WinningBean/codex-vitals) | Separate Go panel/tmux footer | Reads Codex rollout and git state | Small standalone binary, but not integrated into the stock one-line footer |
| [ir272/codex-hud](https://github.com/ir272/codex-hud) | Native status-line preset | Built-in Codex fields | Lowest maintenance; cannot produce the requested custom bars and metrics |
| [steipete/CodexBar](https://github.com/steipete/CodexBar) | macOS menu bar | Provider/account usage integrations | Mature quota monitoring outside the terminal footer |
| [neochoon/agenthud](https://github.com/neochoon/agenthud) | Multi-session TUI dashboard | Observes agent sessions | Best for parallel oversight, not a compact in-session footer |

Codex Mini HUD's niche is deliberately narrower: one macOS-first line, direct
in-process state, no transcript parsing, no daemon or tmux pane, and an official
`codex` command that remains untouched.

## Known limitation

Codex exposes the latest aggregated diff for a turn, not a persisted historical
session-total metric. The HUD therefore reports cumulative edit churn observed
by the current CLI process. It includes the active turn, but a resumed older
thread cannot reconstruct earlier line churn exactly. The value is not the same
as net working-tree change or committed branch difference.

## Upgrade procedure

For each upstream Codex release:

1. update `upstream.lock`;
2. run `git apply --check` against a clean checkout;
3. resolve only the patch surface that drifted;
4. run formatting, `codex-tui` tests, and package tests;
5. build and verify both macOS architectures; and
6. publish archives with checksums and upstream/HUD version metadata.

Upstream changes can always be bypassed immediately by running official
`codex`.
