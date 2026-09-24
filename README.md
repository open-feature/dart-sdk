<!-- markdownlint-disable MD033 -->
<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/open-feature/community/0e23508c163a6a1ac8c0ced3e4bd78faafe627c7/assets/logo/horizontal/white/openfeature-horizontal-white.svg" />
    <img align="center" alt="OpenFeature Logo" src="https://raw.githubusercontent.com/open-feature/community/0e23508c163a6a1ac8c0ced3e4bd78faafe627c7/assets/logo/horizontal/black/openfeature-horizontal-black.svg" />
  </picture>
</p>

<h2 align="center">OpenFeature Dart SDKs</h2>

<p align="center">
  <a href="https://dart.dev/">
    <img alt="Built with Dart" src="https://img.shields.io/badge/Built%20with-Dart-blue.svg?style=for-the-badge" />
  </a>
  <a href="https://codecov.io/gh/open-feature/dart-sdk">
    <img alt="Code Coverage" src="https://codecov.io/gh/open-feature/dart-sdk/branch/main/graph/badge.svg?token=FZ17BHNSU5" />
  </a>
  <a href="https://github.com/open-feature/dart-sdk/actions/workflows/validation-workflow.yml">
    <img alt="GitHub CI Status" src="https://github.com/open-feature/dart-sdk/actions/workflows/validation-workflow.yml/badge.svg?style=for-the-badge" />
  </a>
</p>

This repository contains the independently versioned OpenFeature SDK packages
for Dart server and client applications.

## Packages

| Package | Source | Status |
| --- | --- | --- |
| [`openfeature_dart_server_sdk`](https://pub.dev/packages/openfeature_dart_server_sdk) | [`packages/openfeature_dart_server_sdk`](packages/openfeature_dart_server_sdk) | Existing pre-1.0 dynamic-context server SDK |
| `openfeature_dart_client_sdk` | [`packages/openfeature_dart_client_sdk`](packages/openfeature_dart_client_sdk) | Static-context beta for Dart VM, Dart web, and Flutter consumers |

Each package owns its pubspec, changelog, documentation, source, tests, release
history, and publication path. Server releases retain the `v0.0.x` tag format.
Client releases use `openfeature_dart_client_sdk-v<version>`.

## Repository layout migration

The server SDK moved from the repository root to
`packages/openfeature_dart_server_sdk`. Package names, pub.dev dependencies,
and `package:` imports are unchanged.

Git dependencies that previously resolved the server package from the
repository root must set the package path:

```yaml
dependencies:
  openfeature_dart_server_sdk:
    git:
      url: https://github.com/open-feature/dart-sdk.git
      path: packages/openfeature_dart_server_sdk
```

Repository-relative scripts and local path dependencies must make the same
adjustment. See the
[repository layout migration guide](doc/repository-layout-migration.md) for
compatibility details.

## Client SDK beta

The framework-neutral client SDK has no Flutter dependency, but Flutter
applications can consume it as a normal Dart package. The beta is intended for
provider integration and real-world feedback before the first stable client
release.

- Read the [client package guide](packages/openfeature_dart_client_sdk/README.md).
- Review the [client SDK architecture](doc/client-sdk-architecture.md).
- Review the [client SDK conformance matrix](doc/client-sdk-conformance-matrix.md).
- Follow the [client beta release procedure](doc/client-sdk-release.md).

## Development

Install and validate repository tooling from the repository root:

```text
dart pub get
dart analyze
dart test
```

Run SDK commands from the package being changed:

```text
cd packages/openfeature_dart_server_sdk
dart pub get
dart analyze
dart test
dart pub publish --dry-run
```

Use `packages/openfeature_dart_client_sdk` for the equivalent client commands.
The client publication archive is validated from the repository root with:

```text
dart tool/stage_client_package.dart --dry-run
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for branch, commit, testing, and DCO
requirements.

## Community

- [OpenFeature documentation](https://openfeature.dev/docs/reference/intro)
- [OpenFeature community](https://github.com/open-feature/community)
- [CNCF Slack](https://slack.cncf.io/)
