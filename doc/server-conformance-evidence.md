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

Compatibility decisions requiring release review include legacy provider event
grace, legacy hook mutability/stage behavior, provider cleanup failures now
reported by dispose/resetInstance, and the tracking numeric-property widening.
The report deliberately keeps these gates unresolved. After that review, use
the normal development-to-main and immutable package publication process.

## Migration and consumer evidence

The identical legacy consumer fixture runs against published server `0.0.25` and
the candidate. It analyzes and executes old package imports, provider setup,
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
