# Client static-context candidate evidence

The [versioned inventory](conformance/client-v0.9.0.json) names all 145 normative
requirements from OpenFeature v0.9.0 at immutable specification commit
`d5b0a734d8cb9b42bf89be2a97c627f58208e811`. The 4.3.1 language rationale has [maintainer acceptance](https://github.com/open-feature/dart-sdk/issues/117#issuecomment-5819052385).
The other 144 mappings, applicability rationales and SHOULD interpretations remain
**pending maintainer review**. Selected
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

## Disposition and review status

Counts from `client-v0.9.0.json` (also emitted by the executable reporter):

| Disposition | Count | IDs when not test evidence |
| --- | --- | --- |
| evidence | 125 | Mapped runtime tests; semantic review pending |
| not_applicable | 14 | See inventory for conditional dynamic-context exclusions |
| rationale | 2 | 1.4.12, 4.3.1; only 4.3.1 accepted |
| api_shape | 1 | 3.3.2.1 |
| gap | 3 | 2.5.2 (SHOULD), 2.5.3 (SHOULD), 2.8.1 (MUST); provider-owned |

No SDK-owned explicit gaps remain after the accepted 4.3.1 language rationale.
This does not establish semantic completeness of the pending mappings.

## Explicit outstanding evidence and decisions

| Requirement | Remaining work |
| --- | --- |
| 2.5.2, 2.5.3 (SHOULD) | Obtain canonical provider receipts for shared contract v2 C12/C11. These call the provider directly; SDK cleanup is insufficient. |
| 2.8.1 (MUST) | Obtain v2 C13 receipts for controlled provider transitions. Review spontaneous transport transitions with additional provider-owned evidence. |
| 4.3.1 | Accepted Dart language rationale: keep optional no-op `HookAdapter` stages unchanged. No reflection or new beta declaration flag is introduced. |

Other entries retain proposed mappings rather than a semantic-completeness
claim. Ten added tests cover detailed result fields, all statuses, context value
kinds, hook data/hints, metadata immutability, after/error/finally cleanup,
shutdown/reset, isolated API state and captured print output on provider errors.
The reconciliation test also asserts
RECONCILING handler status while the operation is pending.

## Provider, consumer and release boundaries

The [shared contract process](client-provider-validation.md) records canonical
IntelliToggle v2 C01-C13 receipts on VM and Chrome at provider
`1d8949bb0e565aea81eaad88b363d9ef1a268824` against SDK/harness
`21539eb46b932c234c8daa3d4d080c3e5d703514`. The controlled HTTP fixture is not
live-service or native-platform acceptance. Datadog is participating, but its
canonical repository and reviewed v2 receipt remain required. Maintainers must
accept both independent provider results.

The published SDK client remains `0.0.1-beta.1`, which requires Dart `^3.12.2`.
Development supports `^3.10.0`; the 3.10 CI cells exercise unreleased code.
The proposed next release is **SDK `0.0.1-beta.2`**, following the
[beta release checklist](client-beta2-release-checklist.md). It must be reviewed,
promoted and published before providers can use that version. The separately
published **IntelliToggle** client `0.0.1-beta.2` is an older provider release;
it is not the proposed SDK beta. Experimental isolation and tracking remain
experimental.

Use the same [platform acceptance matrix](client-platform-acceptance.md) for
#166 and #167. Builds and runtime results are distinct. Exact package/framework
versions, resolved dependencies, tested commits and raw logs are required.
Both SDK archives, tooling, reviewed promotion, immutable tag and pub.dev archive
verification remain mandatory. This evidence does not close #167 or #117.
