# Proposed client SDK 0.0.1-beta.2

The next proposed client release is `openfeature_dart_client_sdk` **0.0.1-beta.2**.
It would publish the Dart 3.10 floor and merged client corrections so providers
can validate an immutable pub.dev package. This proposal is not publication or
stable-conformance approval. Published beta.1 still requires Dart `^3.12.2`.

## Release review

- [ ] Review the complete client diff from
  `openfeature_dart_client_sdk-v0.0.1-beta.1` to the proposed promotion commit,
  including #168, #187 and #189; review migration/provider compatibility notes.
- [ ] Validate both SDK packages, repository tooling, package staging and dry-run
  archives at that exact commit; record analyzer/test results and resolved Dart
  versions. Client 3.10 CI is source validation until this package is published.
- [ ] Verify the client pub.dev **admin page** uses repository
  `open-feature/dart-sdk` and tag pattern
  `openfeature_dart_client_sdk-v{{version}}`. Existing pre-rename configuration
  receipts and the GitHub workflow alone do not establish this setting.
- [ ] Obtain normal maintainer review and approval for development-to-main
  promotion and the beta release. Server release identity stays independent.
- [ ] Let the existing component release-please flow generate the client release
  PR after promotion. Inspect that it selects **0.0.1-beta.2**, updates client
  `.release-please-version`, pubspec, changelog and manifest consistently, and
  does not trigger an unintended server release. Correct and review the release
  PR before merging if necessary; do not pre-advance the manifest as if published.
- [ ] Review and merge that release PR, then verify the immutable component tag,
  successful publish workflow, pub.dev archive/version/Dart constraint and
  archive contents. A green dry run is not a published package.
- [ ] Rerun each canonical provider receipt and the agreed consumer matrix
  against the published SDK beta.2. IntelliToggle provider beta.2 is a different,
  older package version and must not be confused with this SDK release.

Proposed release-note topics: Dart `^3.10.0` support; provider reconciliation and
event ordering fixes; lifecycle/static-context behavior since beta.1; experimental
API boundaries. Generate the actual changelog from reviewed commits and verify
each entry. Contract v2 and evidence tooling are repository validation assets;
do not describe them as new runtime provider support or stable certification.

The unresolved semantic review, second canonical provider and native consumer
evidence remain stable-release gates even if this beta is approved.
