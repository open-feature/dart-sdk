# Changelog

## [0.0.25](https://github.com/open-feature/dart-sdk/compare/v0.0.24...v0.0.25) (2026-09-17)


### 🧹 Chore

* promote context snapshots and repository rename to main ([#174](https://github.com/open-feature/dart-sdk/issues/174)) ([1270e2e](https://github.com/open-feature/dart-sdk/commit/1270e2e6af2b0d4be24858756c07a7aadf90e80f))

## [0.0.24](https://github.com/open-feature/dart-server-sdk/compare/v0.0.23...v0.0.24) (2026-08-28)

This release repackages the server SDK under
`packages/openfeature_dart_server_sdk`. The Dart package name, pub.dev
dependency, public API, and `package:` imports are unchanged.

### Repository layout migration

* Move the published server package from the repository root to
  `packages/openfeature_dart_server_sdk`
  ([#151](https://github.com/open-feature/dart-server-sdk/pull/151)).
* Git dependencies must now set
  `path: packages/openfeature_dart_server_sdk`; pub.dev consumers require no
  dependency or import changes.

## [0.0.23](https://github.com/open-feature/dart-server-sdk/compare/v0.0.22...v0.0.23) (2026-08-14)

This release contains the first lifecycle and evaluation-safety work toward
OpenFeature v0.9.0. It does not claim complete v0.9 conformance; remaining
requirements are tracked in
[#121](https://github.com/open-feature/dart-server-sdk/issues/121).

### Notable compatibility changes

- Raise the minimum supported Dart SDK from 3.11.4 to 3.12.2
  ([#123](https://github.com/open-feature/dart-server-sdk/pull/123)).
- Make `OpenFeatureAPI.resetInstance()` asynchronous so callers can await
  provider and controller teardown before creating a replacement API instance
  ([#138](https://github.com/open-feature/dart-server-sdk/pull/138)).
- Make `FlagEvaluationDetails.flagMetadata` non-nullable and immutable. Missing
  metadata now defaults to an empty map, and mutation attempts throw
  `UnsupportedError`
  ([#126](https://github.com/open-feature/dart-server-sdk/pull/126),
  [#132](https://github.com/open-feature/dart-server-sdk/pull/132)).

### Features

- Add provider-owned lifecycle events and per-instance lifecycle coordination,
  including dynamic client rebinding, domain-scoped providers, final-binding
  shutdown, and explicit wait-for-readiness APIs
  ([#124](https://github.com/open-feature/dart-server-sdk/pull/124)).

### Bug fixes

- Contain provider, hook, and context-resolution failures while preserving
  targeting keys and caller defaults
  ([#126](https://github.com/open-feature/dart-server-sdk/pull/126)).
- Preserve the latest concurrent provider and domain binding request, serialize
  rebinding with provider shutdown, and prevent late initialization from
  restoring stale bindings
  ([#132](https://github.com/open-feature/dart-server-sdk/pull/132),
  [#133](https://github.com/open-feature/dart-server-sdk/pull/133),
  [#134](https://github.com/open-feature/dart-server-sdk/pull/134),
  [#138](https://github.com/open-feature/dart-server-sdk/pull/138)).

### Documentation

- Add the server v0.9 conformance matrix and provider-lifecycle compatibility
  contract
  ([#122](https://github.com/open-feature/dart-server-sdk/pull/122)).
- Add the proposed pure-Dart client SDK architecture and conformance matrix;
  the client SDK is not implemented or published in this release
  ([#118](https://github.com/open-feature/dart-server-sdk/pull/118),
  [#136](https://github.com/open-feature/dart-server-sdk/pull/136)).
- Clarify the public README's asynchronous lifecycle examples and client SDK
  proposal status
  ([#143](https://github.com/open-feature/dart-server-sdk/pull/143),
  [#144](https://github.com/open-feature/dart-server-sdk/pull/144)).

### CI and release maintenance

- Publish each version once and harden release, validation, coverage, branch,
  formatting, and minimum-dependency workflows
  ([#119](https://github.com/open-feature/dart-server-sdk/pull/119),
  [#125](https://github.com/open-feature/dart-server-sdk/pull/125),
  [#127](https://github.com/open-feature/dart-server-sdk/pull/127),
  [#128](https://github.com/open-feature/dart-server-sdk/pull/128),
  [#130](https://github.com/open-feature/dart-server-sdk/pull/130)).
- Use the conventional `doc/` package layout and add DCO remediation support
  for shared-branch squash commits
  ([#129](https://github.com/open-feature/dart-server-sdk/pull/129),
  [#135](https://github.com/open-feature/dart-server-sdk/pull/135)).

## [0.0.22](https://github.com/open-feature/dart-server-sdk/compare/v0.0.21...v0.0.22) (2026-05-12)


### 🐛 Bug Fixes

* run parent pipeline without pull_request_target ([#115](https://github.com/open-feature/dart-server-sdk/issues/115)) ([1c5d5ad](https://github.com/open-feature/dart-server-sdk/commit/1c5d5ad57346ccbbd85e1e94bcc612c2fc2636a2))

## [0.0.21](https://github.com/open-feature/dart-server-sdk/compare/v0.0.20...v0.0.21) (2026-04-22)


### 🐛 Bug Fixes

* remove duplicate release badge ([#113](https://github.com/open-feature/dart-server-sdk/issues/113)) ([86eea16](https://github.com/open-feature/dart-server-sdk/commit/86eea166b859a68cfc4c9d519c2df8b88367ffb2))

## [0.0.20](https://github.com/open-feature/dart-server-sdk/compare/v0.0.19...v0.0.20) (2026-04-21)


### 🧹 Chore

* development to main ([#110](https://github.com/open-feature/dart-server-sdk/issues/110)) ([5463261](https://github.com/open-feature/dart-server-sdk/commit/5463261b4c82458b65e1b0e7f618f4602f4ff4b7))

## [0.0.19](https://github.com/open-feature/dart-server-sdk/compare/v0.0.18...v0.0.19) (2026-04-20)


### 🧹 Chore

* align main with development ([#107](https://github.com/open-feature/dart-server-sdk/issues/107)) ([1abd3df](https://github.com/open-feature/dart-server-sdk/commit/1abd3df560f86d8f622a985a3f11a765beeb2cd6))

## [0.0.18](https://github.com/open-feature/dart-server-sdk/compare/v0.0.17...v0.0.18) (2026-04-15)


### 🧹 Chore

* Development to Main ([#96](https://github.com/open-feature/dart-server-sdk/issues/96)) ([34f8c49](https://github.com/open-feature/dart-server-sdk/commit/34f8c49ee0f399cf345e21e2e1c94ab779bf94fc))

## [0.0.17](https://github.com/open-feature/dart-server-sdk/compare/v0.0.16...v0.0.17) (2026-03-12)


### 🧹 Chore

* development to main ([#91](https://github.com/open-feature/dart-server-sdk/issues/91)) ([4bcf320](https://github.com/open-feature/dart-server-sdk/commit/4bcf3200ddf7562aad8bf73f4cfdaf2b27e32b4c))

## [0.0.16](https://github.com/open-feature/dart-server-sdk/compare/v0.0.15...v0.0.16) (2026-01-08)


### 🧹 Chore

* Development to Main ([#88](https://github.com/open-feature/dart-server-sdk/issues/88)) ([13eba3a](https://github.com/open-feature/dart-server-sdk/commit/13eba3a9a62a5967082e043d8914a0e6352d5166))

## [0.0.15](https://github.com/open-feature/dart-server-sdk/compare/v0.0.14...v0.0.15) (2025-12-26)


### ✨ New Features

* A new feature ([#86](https://github.com/open-feature/dart-server-sdk/issues/86)) ([edc52e7](https://github.com/open-feature/dart-server-sdk/commit/edc52e7eb497b4634f32da8e39ccfef061144c1c))

## [0.0.14](https://github.com/open-feature/dart-server-sdk/compare/v0.0.13...v0.0.14) (2025-12-25)


### ✨ New Features

* A new feature ([#83](https://github.com/open-feature/dart-server-sdk/issues/83)) ([dc73440](https://github.com/open-feature/dart-server-sdk/commit/dc73440bc6dc0f852b798f9387b678df7e76de20))


### 🧹 Chore

* update copyright to OpenFeature Maintainers ([#80](https://github.com/open-feature/dart-server-sdk/issues/80)) ([5d2dc98](https://github.com/open-feature/dart-server-sdk/commit/5d2dc988b61db1cd61f232b9091a7f01a17aaff0))

## [0.0.13](https://github.com/open-feature/dart-server-sdk/compare/v0.0.12...v0.0.13) (2025-10-01)


### 🧹 Chore

* development to main ([#77](https://github.com/open-feature/dart-server-sdk/issues/77)) ([ab1b015](https://github.com/open-feature/dart-server-sdk/commit/ab1b015e206d4c505074df3282a8c17ec972afd3))

## [0.0.12](https://github.com/open-feature/dart-server-sdk/compare/v0.0.11...v0.0.12) (2025-08-30)


### 📚 Documentation

* update install version and links ([#68](https://github.com/open-feature/dart-server-sdk/issues/68)) ([3f1f302](https://github.com/open-feature/dart-server-sdk/commit/3f1f30263a8ec89d14eb744bfcb192e36d15fc8e))

## [0.0.11](https://github.com/open-feature/dart-server-sdk/compare/v0.0.10...v0.0.11) (2025-08-28)


### 🧹 Chore

* Development to Main ([#69](https://github.com/open-feature/dart-server-sdk/issues/69)) ([d21c553](https://github.com/open-feature/dart-server-sdk/commit/d21c5539334681c2c96e354e088b8434c91e7d34))

## [0.0.10](https://github.com/open-feature/dart-server-sdk/compare/v0.0.9...v0.0.10) (2025-06-16)


### 🧹 Chore

* development to main ([#62](https://github.com/open-feature/dart-server-sdk/issues/62)) ([5d0cb78](https://github.com/open-feature/dart-server-sdk/commit/5d0cb788b3e9ed35df9a5cdcbcf9c8689a772c93))

## [0.0.9](https://github.com/open-feature/dart-server-sdk/compare/v0.0.8...v0.0.9) (2025-04-08)


### 🧹 Chore

* merge Development main ([#56](https://github.com/open-feature/dart-server-sdk/issues/56)) ([8c2c222](https://github.com/open-feature/dart-server-sdk/commit/8c2c22247e6347903c529783cd0477739fff1ecb))

## [0.0.8](https://github.com/open-feature/dart-server-sdk/compare/v0.0.7...v0.0.8) (2025-04-01)



### 🧹 Chore

* merge development to main ([#52](https://github.com/open-feature/dart-server-sdk/issues/52)) ([6b945f3](https://github.com/open-feature/dart-server-sdk/commit/6b945f3877e26714760f1cb7347b48e4aa8ab338))
* workflow cleanup ([#48](https://github.com/open-feature/dart-server-sdk/issues/48)) ([d81281b](https://github.com/open-feature/dart-server-sdk/commit/d81281bd43ffc3b903517e97d4308eebef1c43c8))

## [0.0.7](https://github.com/open-feature/dart-server-sdk/compare/v0.0.6...v0.0.7) (2025-03-17)


### 🧹 Chore

* update dartsdk minimum to latest version 3.7.2 ([#44](https://github.com/open-feature/dart-server-sdk/issues/44)) ([9729726](https://github.com/open-feature/dart-server-sdk/commit/9729726080e49ad86656c22778c723c724c08a96))

## [0.0.6](https://github.com/open-feature/dart-server-sdk/compare/v0.0.5...v0.0.6) (2025-03-14)


### 🧹 Chore

* move publishing step to a separate workflow ([#41](https://github.com/open-feature/dart-server-sdk/issues/41)) ([9606219](https://github.com/open-feature/dart-server-sdk/commit/96062192c23094a75cb027c384366cde7af03395))

## [0.0.5](https://github.com/open-feature/dart-server-sdk/compare/v0.0.4...v0.0.5) (2025-03-14)


### 🧹 Chore

* update the dart publishing logic ([c66b9b7](https://github.com/open-feature/dart-server-sdk/commit/c66b9b735940a2ccc3d1ada0391f8f266a3812c0))

## [0.0.4](https://github.com/open-feature/dart-server-sdk/compare/v0.0.3...v0.0.4) (2025-03-14)


### ✨ New Features

* release v.0.0.1-pre+1 ([#25](https://github.com/open-feature/dart-server-sdk/issues/25)) ([83b6438](https://github.com/open-feature/dart-server-sdk/commit/83b643864d7d6e100cfc337e2abf05eadd8f241e))


### 🧹 Chore

* add .release-please-manifest.json ([32afd53](https://github.com/open-feature/dart-server-sdk/commit/32afd5308fa5db55d7d86324c3bc1a8ebccbf96c))
* add license file ([88d6f2b](https://github.com/open-feature/dart-server-sdk/commit/88d6f2b94d57130b36a1ed164cadfef86bc6526e))
* add readme to release please ([e8c96e5](https://github.com/open-feature/dart-server-sdk/commit/e8c96e5fc5f5c5e417fc057c504cbfdcf53f14ab))
* add release please config ([d811414](https://github.com/open-feature/dart-server-sdk/commit/d8114148693338bc812a1b59ab24b591e99a5b1d))
* experimental readme ([dea052a](https://github.com/open-feature/dart-server-sdk/commit/dea052a3bea9edc0529931ed74510bd993e8a065))
* **main:** release open_feature_dart_server_sdk 0.0.2 ([#31](https://github.com/open-feature/dart-server-sdk/issues/31)) ([00cba1f](https://github.com/open-feature/dart-server-sdk/commit/00cba1f0c698bd167678af4f90b0b44954f83751))
* **main:** release open_feature_dart_server_sdk 0.0.3 ([#35](https://github.com/open-feature/dart-server-sdk/issues/35)) ([cd94eb8](https://github.com/open-feature/dart-server-sdk/commit/cd94eb81c406c19c85e817d0402fdbc7a16d370c))
* move code into the root directory ([#32](https://github.com/open-feature/dart-server-sdk/issues/32)) ([ba2a59e](https://github.com/open-feature/dart-server-sdk/commit/ba2a59e3b8796f5c28ccaa1105b20bb5b5ee0e50))
* remove readme from release please config ([1f41977](https://github.com/open-feature/dart-server-sdk/commit/1f41977b1d36423e0c9330d78f5428c837cf276d))
* switch from dart to simple ([5b00b42](https://github.com/open-feature/dart-server-sdk/commit/5b00b4240d84db1e11e6a469ca554a5185973478))
* update pubdev package name  ([#38](https://github.com/open-feature/dart-server-sdk/issues/38)) ([36d10de](https://github.com/open-feature/dart-server-sdk/commit/36d10de418cdb72ca21e724f7d5da6be47f348ad))
* update pubspec yaml - remove pre version ([#36](https://github.com/open-feature/dart-server-sdk/issues/36)) ([9ce0dd8](https://github.com/open-feature/dart-server-sdk/commit/9ce0dd87ca21c21f544104996d62cf9b8283f8a4))
* update release config name ([805e7b7](https://github.com/open-feature/dart-server-sdk/commit/805e7b784729fd6f92f76fb719685c170102bba4))
* update release please config ([#29](https://github.com/open-feature/dart-server-sdk/issues/29)) ([d850dfd](https://github.com/open-feature/dart-server-sdk/commit/d850dfd3c52ddd5b25ef2337cb1c285c38aa7cb5))
* update release please config ([#33](https://github.com/open-feature/dart-server-sdk/issues/33)) ([392510c](https://github.com/open-feature/dart-server-sdk/commit/392510ce318f7e5615d98c48e0ed6b54778493eb))


### 📚 Documentation

* update readme ([c3092e7](https://github.com/open-feature/dart-server-sdk/commit/c3092e7a119570759c4fa41274b11e4e89abcfc7))
* update version in readme ([c77b74c](https://github.com/open-feature/dart-server-sdk/commit/c77b74c52514315cc37c81c68b01a2c1e2bc0eee))

## [0.0.3](https://github.com/open-feature/dart-server-sdk/compare/open_feature_dart_server_sdk-v0.0.2...open_feature_dart_server_sdk-v0.0.3) (2025-03-14)


### ✨ New Features

* release v.0.0.1-pre+1 ([#25](https://github.com/open-feature/dart-server-sdk/issues/25)) ([83b6438](https://github.com/open-feature/dart-server-sdk/commit/83b643864d7d6e100cfc337e2abf05eadd8f241e))


### 🧹 Chore

* add .release-please-manifest.json ([32afd53](https://github.com/open-feature/dart-server-sdk/commit/32afd5308fa5db55d7d86324c3bc1a8ebccbf96c))
* add readme to release please ([e8c96e5](https://github.com/open-feature/dart-server-sdk/commit/e8c96e5fc5f5c5e417fc057c504cbfdcf53f14ab))
* add release please config ([d811414](https://github.com/open-feature/dart-server-sdk/commit/d8114148693338bc812a1b59ab24b591e99a5b1d))
* experimental readme ([dea052a](https://github.com/open-feature/dart-server-sdk/commit/dea052a3bea9edc0529931ed74510bd993e8a065))
* **main:** release open_feature_dart_server_sdk 0.0.2 ([#31](https://github.com/open-feature/dart-server-sdk/issues/31)) ([00cba1f](https://github.com/open-feature/dart-server-sdk/commit/00cba1f0c698bd167678af4f90b0b44954f83751))
* move code into the root directory ([#32](https://github.com/open-feature/dart-server-sdk/issues/32)) ([ba2a59e](https://github.com/open-feature/dart-server-sdk/commit/ba2a59e3b8796f5c28ccaa1105b20bb5b5ee0e50))
* remove readme from release please config ([1f41977](https://github.com/open-feature/dart-server-sdk/commit/1f41977b1d36423e0c9330d78f5428c837cf276d))
* switch from dart to simple ([5b00b42](https://github.com/open-feature/dart-server-sdk/commit/5b00b4240d84db1e11e6a469ca554a5185973478))
* update pubspec yaml - remove pre version ([#36](https://github.com/open-feature/dart-server-sdk/issues/36)) ([9ce0dd8](https://github.com/open-feature/dart-server-sdk/commit/9ce0dd87ca21c21f544104996d62cf9b8283f8a4))
* update release config name ([805e7b7](https://github.com/open-feature/dart-server-sdk/commit/805e7b784729fd6f92f76fb719685c170102bba4))
* update release please config ([#29](https://github.com/open-feature/dart-server-sdk/issues/29)) ([d850dfd](https://github.com/open-feature/dart-server-sdk/commit/d850dfd3c52ddd5b25ef2337cb1c285c38aa7cb5))
* update release please config ([#33](https://github.com/open-feature/dart-server-sdk/issues/33)) ([392510c](https://github.com/open-feature/dart-server-sdk/commit/392510ce318f7e5615d98c48e0ed6b54778493eb))


### 📚 Documentation

* update readme ([c3092e7](https://github.com/open-feature/dart-server-sdk/commit/c3092e7a119570759c4fa41274b11e4e89abcfc7))
* update version in readme ([c77b74c](https://github.com/open-feature/dart-server-sdk/commit/c77b74c52514315cc37c81c68b01a2c1e2bc0eee))

## [0.0.2](https://github.com/open-feature/dart-server-sdk/compare/open_feature_dart_server_sdk-v0.0.1...open_feature_dart_server_sdk-v0.0.2) (2025-03-14)


### ✨ New Features

* release v.0.0.1-pre+1 ([#25](https://github.com/open-feature/dart-server-sdk/issues/25)) ([83b6438](https://github.com/open-feature/dart-server-sdk/commit/83b643864d7d6e100cfc337e2abf05eadd8f241e))
