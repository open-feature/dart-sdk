# Repository Layout Migration

The Dart server and client SDKs now use the same package layout:

```text
dart-sdk/
|-- packages/
|   |-- openfeature_dart_server_sdk/
|   `-- openfeature_dart_client_sdk/
|-- doc/
|-- test/       # repository release and staging tests
`-- tool/       # repository release and staging tools
```

## Compatibility

The move does not rename either Dart package and does not change their public
APIs. Pub.dev consumers keep the same dependency and `package:` imports.

Repository-relative consumers must update paths that assumed the server SDK
was at the repository root. This includes Git dependencies, local path
dependencies, scripts, and CI jobs.

Before (historical layout; not a current dependency configuration):

```yaml
dependencies:
  openfeature_dart_server_sdk:
    git:
      url: https://github.com/open-feature/dart-server-sdk.git
```

After:

```yaml
dependencies:
  openfeature_dart_server_sdk:
    git:
      url: https://github.com/open-feature/dart-sdk.git
      path: packages/openfeature_dart_server_sdk
```

Local contributors should run server commands from
`packages/openfeature_dart_server_sdk` and client commands from
`packages/openfeature_dart_client_sdk`. Repository release and staging tests
continue to run from the repository root.

The established server tag format remains `v0.0.x`. Client releases use
`openfeature_dart_client_sdk-v<version>`. Moving the server package does not
reset release history or couple the two packages' versions.
