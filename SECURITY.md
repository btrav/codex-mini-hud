# Security policy

## Supported versions

Security fixes are provided for the latest Codex Mini HUD release. Each HUD
release supports only the exact upstream Codex commit recorded in its
`upstream.lock`.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting feature for this
repository. Do not open a public issue for vulnerabilities involving command
execution, installer path handling or deletion, release integrity, credentials,
authentication data, or signing material.

Include the HUD version, upstream Codex version, macOS version and architecture,
reproduction steps, impact, and any suggested mitigation. You should receive an
initial acknowledgement within seven days. Public disclosure should wait until
a fix or coordinated mitigation is available.

## Scope

Codex Mini HUD modifies the Codex CLI and uses the same local Codex
authentication and configuration. Reports that reproduce only in the official
Codex distribution should be submitted through OpenAI's security process.
