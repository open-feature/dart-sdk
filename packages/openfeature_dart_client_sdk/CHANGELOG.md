# Changelog

## [0.0.1](https://github.com/open-feature/dart-sdk/compare/openfeature_dart_client_sdk-v0.0.1-beta.2...openfeature_dart_client_sdk-v0.0.1) (2026-10-05)

First non-beta client release. The package remains pre-1.0; this version does
not establish a 1.0 API compatibility commitment. The three-second deadline
below belongs to the development-only provider contract, not the application
lifecycle timeout.

### 🐛 Bug Fixes

* **client:** preserve initialization event status and queue handler events ([#205](https://github.com/open-feature/dart-sdk/issues/205)) ([a6bdc60](https://github.com/open-feature/dart-sdk/commit/a6bdc60f2332b324bb60f7ff376339557b2184da))
* **client:** require one initialization ready event within a shared 3-second action/event deadline and reject extra terminal events during bounded observation ([#204](https://github.com/open-feature/dart-sdk/issues/204)) ([a6bdc60](https://github.com/open-feature/dart-sdk/commit/a6bdc60f2332b324bb60f7ff376339557b2184da))

## [0.0.1-beta.2](https://github.com/open-feature/dart-sdk/compare/openfeature_dart_client_sdk-v0.0.1-beta.1...openfeature_dart_client_sdk-v0.0.1-beta.2) (2026-09-26)


### 🐛 Bug Fixes

* **client:** promote reconciliation fix and beta release evidence ([#199](https://github.com/open-feature/dart-sdk/issues/199)) ([94345b5](https://github.com/open-feature/dart-sdk/commit/94345b54ce1cf577b5bc068c708cae568f19e25e))

## 0.0.1-beta.1 (2026-08-28)


### ✨ New Features

* **client:** promote static-context SDK beta ([#148](https://github.com/open-feature/dart-server-sdk/issues/148)) ([1012cfe](https://github.com/open-feature/dart-server-sdk/commit/1012cfee6478bff153f356b87fb55d0e495d64b9))
