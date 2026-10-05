# Dart Client SDK Releases

The Dart client SDK is independently versioned from the server SDK. Client
changes use the `openfeature_dart_client_sdk-v<version>` tag format and must not
require a server package release. Release Please opens separate component pull
requests so maintainers can merge the client release without publishing the
server package. Both SDKs live under `packages/`, so Release Please can scope
each proposal to the package directory that owns the change.

## First non-beta milestone

The intended releases are server `0.1.0` and client `0.0.1`. They remain
independent pre-1.0 packages; a non-beta suffix is not a 1.0 API compatibility
commitment. The current published baselines are server `0.0.27` and client
`0.0.1-beta.2`; this preparation does not publish either milestone.

The client configuration disables prerelease generation while retaining the
suffix-safe `simple` strategy, component-prefixed tag, version file and generic
pubspec/README updates. Temporary per-package `release-as` values make the two
milestones explicit even when the promotion is squash-merged. Release Please
opens separate draft component PRs; these are not publication approvals.

Before either component release:

1. Integrate the reviewed development candidate, including PR204 and PR205,
   with fresh exact-head CI. Preserve the newest main release metadata.
2. Obtain applicable maintainer semantic/migration and provider/platform
   acceptance. Client gates in issues117/166/167 and server conformance decisions
   in issues121/165 remain separate from passing builds and version changes.
3. Review the generated component PR's exact target and changelog. Remove ONLY
   that component's temporary `release-as` override in the same release PR.
   Repository tests reject the override once the manifest records its milestone.
   Retain the other component's pending target until its own review is complete.
4. Validate the staged package/dry-run, documented minimum/current Dart and
   Flutter/platform scope, exact hosted provider/consumer versions, migration
   and support documentation. Record remaining dispositions honestly.
5. Finalize current README/status/version instructions with the release, retaining
   historical beta changelogs and accurate conformance scope. Make the reviewed
   component PR ready only when its required acceptance is satisfied.
6. After normal merge, verify the distinct tag, publish workflow, pub.dev archive
   and consumer receipt. Server tag is `v0.1.0`; client tag is
   `openfeature_dart_client_sdk-v0.0.1`. Publication is not established by a push
   or README edit alone.

IntelliToggle's current server provider dependency `^0.0.26` excludes SDK
`0.1.0`; its owner must release reviewed compatible constraints. The intended
client provider, demo and downloads must also use verified non-beta runtime
packages before the public non-beta announcement. Do not use overrides to hide
an incompatible dependency or replace missing runtime acceptance.

The sections below preserve the historical bootstrap and prerelease process.
They do not instruct the next non-beta release to reuse the beta override.

## Historical bootstrap release set

The repository-layout migration after server `v0.0.23` deliberately requires
one server repackaging release, `0.0.24`, alongside the first client beta release
proposal. This is a one-time migration decision rather than a coupling between
the two package versions. Release Please must still open separate server and
client release pull requests, and maintainers may review and merge them
independently.

Before merging the generated server `0.0.24` release pull request, curate its
changelog to describe the server package move and the required Git dependency
`path: packages/openfeature_dart_server_sdk`. Remove client-scoped changes and
repository-only DCO or branch-sync entries from the server changelog. The full
migration instructions remain in `doc/repository-layout-migration.md`.

Release Please owns both package changelogs. Before the first client release,
the client changelog contains only a non-rendered bootstrap marker mentioning
`0.0.1-beta.1`, which keeps the package dry-run warning-free while allowing the
generated entry to be the first visible heading. Do not prewrite that version
heading. The server changelog must not carry an `Unreleased` block above its
generated version entries.

## Historical first pub.dev publication

Automated pub.dev publishing can be configured only after a package exists.
For `0.0.1-beta.1`, an authorized OpenFeature publisher must:

1. Merge the reviewed client beta promotion to `main`.
2. In the generated client release PR, remove the one-time `release-as` setting
   from `release-please-config.json`. The repository test suite deliberately
   rejects a non-bootstrap manifest that retains this override. Verify that the
   PR still proposes `0.0.1-beta.1`, then merge it. Release Please updates the
   manifest from `0.0.0` and creates the
   `openfeature_dart_client_sdk-v0.0.1-beta.1` tag.
3. Check out that exact tag and run:

   ```text
   dart tool/stage_client_package.dart --dry-run
   dart tool/stage_client_package.dart --publish
   ```

4. Transfer the package to the verified `openfeature.dev` publisher on pub.dev.
5. Configure pub.dev automated publishing for this GitHub repository and the
   `openfeature_dart_client_sdk-v{{version}}` tag pattern.
6. Set the GitHub repository variable `CLIENT_PUBDEV_BOOTSTRAPPED` to `true`.

Until the repository variable is enabled, client release tags deliberately
print bootstrap instructions instead of silently attempting publication.

## Historical prerelease process

Release Please tracks the client from `packages/openfeature_dart_client_sdk`
and creates component-prefixed beta tags. The tag-triggered publish workflow
stages the package before publishing so the validated archive is identical to
the archive used for the manual first-publication bootstrap.

The package-local `.release-please-version` file and the generic marker on the
pubspec version keep prerelease suffixes intact; Release Please's Dart updater
treats a hyphenated prerelease suffix as Dart build metadata.

Before every client release, verify formatting, analysis, tests, Dart web
compilation, the staged pub.dev dry-run, and at least one external provider
against the exact release commit.
