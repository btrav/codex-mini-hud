# Contributing

Thanks for helping improve Codex Mini HUD. This is an unofficial project and
changes should remain small, reviewable, and tied to the exact Codex revision in
`upstream.lock`.

## Before opening a pull request

1. Do not include credentials, Codex authentication/session data, build output,
   Apple signing material, or files from `dist/`.
2. Run the Bash suites:

   ```bash
   ./test.sh
   ./test-package.sh
   ```

3. Apply the patch to a clean checkout of the pinned upstream commit and run:

   ```bash
   cd codex-rs
   cargo fmt --all -- --check
   RUST_MIN_STACK=16777216 cargo test -p codex-tui --lib
   ```

4. Explain any user-visible HUD or installer change and update the README when
   behavior, compatibility, or release contents change.

## Updating upstream Codex

Update the tag and commit together, confirm that the tag resolves to that exact
commit, regenerate the patch, review every changed upstream surface, run the
full test matrix, then build and inspect both macOS architectures.

## Security reports

Do not report sensitive vulnerabilities in a public issue. Follow
[`SECURITY.md`](SECURITY.md).
