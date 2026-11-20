# Feature 002: Canonical code-agent command

A team lead needs a single unambiguous command for delegating implementation through the project's OpenCode wrapper. This change adds a public name to the current runtime.

| Requirement | Acceptance |
| --- | --- |
| R1. Use code-agent for new work. Existing code-channel commands remain supported. | Both entry points have equivalent offline plan, argument and exit behavior. |
| R2. Apply the same dispatch policy and accounting to either command. | Guard decisions match for valid and invalid invocations. One helper invocation contributes one count. |
| R3. Keep archive recovery reproducible. | Active instructions identify the old name, preserve the original archive and require migration and verification in the restored working copy. |
| R4. Preserve state and historical evidence. | Both names share the existing implementation, configuration, lock namespace and journal. Existing archive and historical spec files are byte-for-byte unchanged. |
| R5. Deliver an operational command. | Verify the reviewed revision on GitHub and the installed launch path separately with offline checks. |

The implementation plan and test commands are in [the delivery plan](../../docs/plans/2026-11-20-code-agent.md).
