# Server v0.9 candidate evidence and release review

This report is evidence for #165, not a conformance declaration. The normative
inventory is pinned to OpenFeature specification v0.9.0 commit
`d5b0a734d8cb9b42bf89be2a97c627f58208e811`. It includes 145 entries across six
sections, including the normative MAY headed `Condition 2.7.1` upstream.

From the repository root, with Dart and Python 3 installed:

```sh
cd packages/openfeature_dart_server_sdk
dart pub get
cd ../..
python3 -m unittest discover -s tool -p test_server_conformance.py
python3 tool/server_conformance.py
python3 tool/server_compatibility.py
```

`build/server-conformance/report.json` records the actual checkout commit/tree,
Dart version, dirty state, specification commit/checksums, every mapped test name
and result, proposed exceptions, and release gates. The Markdown companion is a
compact review index. CI uploads both reports, the raw Dart JSON test stream and
legacy consumer logs. In PR workflows the tested checkout may be GitHub's merge
commit; the source PR head is recorded separately. Never substitute the PR head
for the tested commit when citing evidence.

The reporter downloads the six files by immutable commit, verifies their SHA256
checksums and checks the inventory for missing/extra identifiers. For offline
reproduction, `--spec-dir PATH` accepts previously downloaded files only if all
checksums match. It then runs the server tests freshly. Skipped, unfinished,
failed or unmatched tests cannot become passing evidence. A report with broken
test evidence fails CI. Review and provider gates remain visible when CI passes;
`--require-release-ready` also fails while any release gate remains unresolved.

## What must still be reviewed

Counts from `conformance/server-v0.9.0.json` (also emitted by the reporter):

| Disposition | Count | IDs when not test evidence |
| --- | --- | --- |
| evidence | 127 | Mapped tests; semantic review pending |
| not_applicable | 16 | 1.3.2.1, 1.4.2.1, 1.7.2.1, 2.8.4, 3.2.2.1–3.2.2.4, 3.2.4.1–3.2.4.2, 3.3.2.1, 4.3.3.1, 5.3.4.1–5.3.4.3, 6.1.2.1 |
| rationale | 1 | 2.6.1: optional MAY capability omitted because context is passed on every evaluation |
| deviation | 1 | 1.4.11: default evaluation-error logging, pending acceptance |

All 145 semantic mappings remain pending review. Requirement 2.8.4 is conditional
on the optional callback in 2.6.1; that callback is neither implemented nor
called by this dynamic-context SDK. It is not a blanket provider exemption.

The mappings in `conformance/server-v0.9.0.json` are proposals. A passing selected
test establishes that behavior in that fixture; it does not prove semantic
completeness for every requirement. Maintainers must inspect each mapping,
including the proposed static-context exceptions and the legacy client-logging
SHOULD deviation. Any unmet applicable MUST blocks the release.

Provider-specific requirements need evidence from the provider implementation.
Core fixtures establish SDK dispatch/lifecycle behavior; they do not certify
every vendor provider. Validate an external provider in its canonical repository
against the exact candidate, including lifecycle, event/hook and tracking
integration. Local dependency overrides or a passing consumer build alone do
not establish deployed or live service acceptance.

IntelliToggle is the named external server-provider candidate in its
[canonical repository](https://gitlab.com/dartapps/apps/intellitoggle/openfeature-provider-intellitoggle).
Existing green provider CI is not yet the requirement-level receipt: identify
the exact server job, resolved SDK version/commit and lifecycle, events, hooks
and tracking coverage before accepting this gate. The client v2 receipts do not
substitute for server integration coverage.

Context scope (#159), shutdown ownership/deadline documentation (#163) and the
shipped `0.0.26` numeric widening/migration notes (#164) have been accepted and
closed. The latest merged documentation baseline is `4fd0ecf9d6cdf29e330a344b1cd1aea48bc35bf3`;
its server evidence run contains 407 passing tests. These implementation slices
do not resolve the remaining semantic, provider or future conformance-release
gates. The reporter records the exact candidate under review.

### Default logging and opt-out (1.4.11)

Evaluation errors log `WARNING` through `Logger('FeatureClient')` by default.
Singleton API construction sets `Logger.root.level = Level.ALL` and subscribes a printer
to root records. Isolated API construction does not install that printer, but
clients still emit logger records. Applications can use the existing `package:logging` API:

```dart
import 'package:logging/logging.dart';
import 'package:openfeature_dart_server_sdk/open_feature_api.dart';

final api = OpenFeatureAPI();
hierarchicalLoggingEnabled = true;
Logger('FeatureClient').level = Level.OFF;
```

Declare `logging` as a direct application dependency when importing it.
This process-wide configuration silences that named logger, including its
tracking warnings, and preserves other loggers. It is not an SDK-wide opt-out.
`logging_opt_out_test.dart` checks both default evaluation-error output and the
named logger's suppression while an unrelated warning still prints. Keeping
default logging is a **SHOULD NOT deviation awaiting maintainer acceptance**.

### Legacy API decisions proposed for review

| Legacy surface | Proposed 0.0.x decision | Later change gate |
| --- | --- | --- |
| Positional context constructors and legacy reserved-key behavior | Keep; canonical named form remains additive | #195: review warnings/migration before a breaking removal; no removal version chosen |
| `Hook` / `BaseHook` mutability and stages | Keep; use opt-in `EvaluationHook` for the new contract | Review migration and a breaking version before removal |
| Legacy provider event streams and grace behavior | Keep alongside typed events | Review event migration before any breaking removal |
| Legacy provider members | Keep; optional capability interfaces remain additive | Review migration before any breaking removal |

These are proposals for maintainers to mark, not independent approvals. The
supported public timeout configuration request remains a separate #196 follow-up.

## Migration and consumer evidence

The identical legacy consumer fixture runs against published server `0.0.25`,
published `0.0.26` (the latest release baseline), and the candidate. Retaining
`0.0.25` also checks the pre-numeric-widening API. It analyzes and executes old package imports, provider setup,
positional contexts, asynchronous evaluation/details, legacy transactions and
tracking, and checks the resolved dependency graph for Flutter dependencies.
This is a scoped compatibility fixture, not proof that every old program builds.
In particular, direct assignment of tracking `value` to `double?` requires the
documented conversion after the property becomes `num?`.

The package retains its name and import identity. Migration guides:

- [Required defaults](../packages/openfeature_dart_server_sdk/doc/evaluation-defaults-migration.md)
- [Canonical context and legacy values](../packages/openfeature_dart_server_sdk/doc/evaluation-context-migration.md)
- [Optional provider capabilities](../packages/openfeature_dart_server_sdk/doc/provider-capabilities-migration.md)
- [Hook stages/options and compatibility](../packages/openfeature_dart_server_sdk/doc/hooks-migration.md)
- [Typed events and legacy streams](../packages/openfeature_dart_server_sdk/doc/events-migration.md)
- [Shutdown and isolated APIs](../packages/openfeature_dart_server_sdk/doc/shutdown-and-isolation.md)
- [Tracking numeric migration and transaction carriers](../packages/openfeature_dart_server_sdk/doc/tracking-and-transactions.md)

`createClient({String? domain})` adds optional-domain creation while preserving
the legacy `getClient(name, domain: ...)`. Creation remains safe after permanent
disposal; such clients return application defaults. Evaluation details report
the requested flag key even if the provider uses an internal alias. Those gaps
are covered by `conformance_completion_test.dart`.
