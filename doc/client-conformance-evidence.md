# Client static-context candidate evidence

The [versioned inventory](conformance/client-v0.9.0.json) names all 145 normative
requirements from OpenFeature v0.9.0 at immutable specification commit
`d5b0a734d8cb9b42bf89be2a97c627f58208e811`. Every mapping, proposed dynamic-context
exclusion and SHOULD interpretation is **pending maintainer review**. Selected
passing tests are relevant evidence, not proof that every clause is covered.

From the repository root, after installing client package dependencies:

```sh
python3 -m unittest discover -s tool -p test_client_conformance.py
python3 tool/client_conformance.py --platform vm --output build/client-vm
python3 tool/client_conformance.py --platform chrome --output build/client-chrome
```

The reporter verifies six specification checksums and the complete requirement
inventory, executes the actual client tests, and records the tested SDK commit,
tree, dirty status, Dart version, platform, exact test names and results. CI runs
VM and Chrome on Dart 3.10.0 and stable. GitHub's tested merge commit is recorded
separately from the PR source head. Missing, skipped, unfinished or failed mapped
tests cannot become passing evidence. Raw test JSON remains in each artifact.
Four host-Dart analyzer fixtures also check a valid consumer and reject
transaction propagation, client context and invocation context with the expected
diagnostics. These compile checks are recorded separately from browser runtime.

`--spec-dir` permits an offline copy of the same six checksum-verified files.
`--require-release-ready` rejects unresolved mappings, explicit gaps, dirty
source and remaining release gates. Normal candidate CI succeeds when its
declared tests and inventory are valid while reporting `release_ready: false`.
It does not waive stable-promotion gates.

## Explicit outstanding evidence and decisions

| Requirement | Remaining work |
| --- | --- |
| 2.5.2, 2.5.3 | Obtain canonical provider post-shutdown/idempotency evidence; SDK cleanup is not proof of each provider's behavior. |
| 2.8.1 | Review every provider-owned status transition, including spontaneous transport events, against canonical provider receipts. |
| 4.3.1 | Resolve the at-least-one-stage contract: `HookAdapter` currently permits an entirely empty hook. Existing no-op-stage tests do not establish this MUST. Any change needs beta migration review. |

Other entries retain proposed mappings rather than a semantic-completeness
claim. Ten added tests cover detailed result fields, all statuses, context value
kinds, hook data/hints, metadata immutability, after/error/finally cleanup,
shutdown/reset, isolated API state and captured print output on provider errors.
The reconciliation test also asserts
RECONCILING handler status while the operation is pending.

## Provider, consumer and release boundaries

The [shared contract process](client-provider-validation.md) remains a separate
gate. The first canonical IntelliToggle candidate is [provider MR62](https://gitlab.com/dartapps/apps/intellitoggle/openfeature-provider-intellitoggle/-/merge_requests/62),
with controlled HTTP VM/Chrome results against SDK contract commit
`c1dccdd0560526ce25c3a93b398c5e7af2528541`. Its runtime provider fix and adapter
require their own native review and complete hosted CI. These receipts do not
test this later client test-only branch. A second independent implementation is
still required; Datadog participation is unconfirmed.

The published client remains `0.0.1-beta.1`; published IntelliToggle client
`0.0.1-beta.2` is prior compatibility input, not a claim that its release includes
MR62. No runtime API, dependency constraint, version, tag or release routing is
changed here. Previously merged client changes include the Dart 3.10 minimum;
maintainers must reconcile the final development-to-main diff and migration
notes before choosing a stable version. Experimental isolation and tracking
remain experimental.

Flutter builds, Flutter web runtime and actual Android/iOS/desktop runtime
results must name resolved SDK/provider/framework versions individually. VM or
Chrome core tests do not establish those consumer gates. Both SDK archives,
tooling, reviewed promotion, immutable tag and pub.dev archive verification
remain mandatory. This evidence does not close #167 or #117.
