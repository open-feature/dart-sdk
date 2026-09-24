# Client provider validation and stable-release evidence

Issue #166 now has a [versioned shared harness](../conformance/client_provider_contract/README.md)
with ten scenarios and a reproducible receipt command. Its SDK reference passes
on Dart VM and Chrome, which validates the harness. No second independent
provider commitment or external contract pass is asserted.

The existing SDK suites remain required: `client_sdk_test.dart` covers typed
resolution/static context; `event_handlers_test.dart` covers routing/state
ordering; `race_safety_test.dart` covers serialized replacement/reconciliation;
`promotion_readiness_test.dart` covers lifecycle timeouts, quarantine, ownership
and rollback. The shared contract makes provider results comparable without
moving vendor transport into core.

| Release input | Required evidence | Current decision |
| --- | --- | --- |
| SDK reference | All ten cases on VM and real Chrome | Harness validation only |
| IntelliToggle | Canonical provider adapter, exact SDK/provider receipts, transport scenarios | [Canonical MR62](https://gitlab.com/dartapps/apps/intellitoggle/openfeature-provider-intellitoggle/-/merge_requests/62) provides the first candidate; native review and hosted CI remain required |
| Second independent provider | Same contract and independently maintained canonical implementation | Participation and receipt pending; Datadog is not confirmed |
| Dart/Flutter/platform consumers | Exact SDK/provider/framework versions, resolved dependencies, web build/runtime and native device records | Distinguish each platform; no native mobile claim from Chrome |
| Static-context requirements | Each applicable v0.9 MUST mapped and reviewed; SHOULD deviations explained | [Executable inventory](client-conformance-evidence.md) exposes proposed mappings and explicit gaps; semantic review remains required |
| Package/release safety | Both SDKs/tooling pass; archive, immutable tag and pub.dev identity verified | Independent routing retained; no stable publication authorized by a reference pass |

For #167, maintainers must review the shared receipts and complete the
[client conformance matrix](client-sdk-conformance-matrix.md) before approving
stable promotion. Preserve the beta migration history, name the supported
provider versions, reconcile unpublished client changes since `0.0.1-beta.1`,
and promote through development to main using the normal review/check gates.
The server's release identity remains independent.

No checkbox for two providers or stable readiness should be completed from
this harness PR alone. Run the adapter in each canonical provider repository,
retain raw JSON/logs, and link provider-specific failures to focused issues.
