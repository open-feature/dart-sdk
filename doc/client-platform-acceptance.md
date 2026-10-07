# Client platform acceptance for #166 and #167

Brian confirmed this target list on October 7 in #167; it is not a support certification.
Final exact-version runtime evidence remains required. A build alone does not satisfy runtime
acceptance; do not infer native results from a VM, widget test or Chrome run.

| Target | Required execution | Current evidence boundary |
| --- | --- | --- |
| Dart VM, 3.10.0 and stable | Core suite and canonical provider contract; record exact stable version | SDK CI has both lanes. IntelliToggle v2 receipts use Dart 3.13.4, SDK `21539eb`; published SDK 0.0.1 and IntelliToggle provider 0.0.1-beta.4 both allow Dart 3.10; final-pair contract v3 receipt is pending |
| Chrome, Dart 3.10.0 and stable | Core suite and canonical provider contract in real browser | SDK CI has both lanes; IntelliToggle v2 receipts use Dart 3.13.4. Record browser version in final consumer receipt |
| Flutter web release, Chrome | Build release bundle, serve it, execute consumer assertions in browser | Final exact-version release runtime receipt pending |
| Android emulator, API 36.1, x86_64 | Launch Flutter consumer and execute runtime assertions | Pending; local installed emulator image is an available target, not evidence of a run |
| iOS simulator 26.2, iPhone 16e, Xcode 26.2 | Launch Flutter consumer and execute runtime assertions | Pending on macOS; simulator target is listed in the [runner image inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md) |
| macOS 26 desktop | Launch Flutter desktop consumer and execute runtime assertions | Pending |
| Ubuntu 24.04 Linux desktop | Launch Flutter desktop consumer under a display and execute runtime assertions | Pending |
| Windows 11 desktop (or maintainer-accepted hosted Windows Server 2025) | Launch Flutter desktop consumer and execute runtime assertions | Pending |

For each Flutter row record `flutter --version --machine`, bundled Dart version,
OS/build, device/runtime identifier, exact resolved SDK/provider versions or
immutable commits, dependency lockfile, source dirty status and raw execution
logs. Flutter's bundled Dart is independent of the standalone 3.10/stable lanes.
Record build and runtime outcomes separately, including failures and skipped
cells. Use the same consumer assertions for typed evaluation, context changes,
ready/error events and shutdown; controlled transport does not certify a live
provider backend. Provider-owned spontaneous transport transitions need their
own evidence in addition to the shared v2 contract.

The [canonical provider receipts](client-provider-validation.md) and these
platform receipts are separate gates. Final release acceptance must use the
reviewed SDK candidate; earlier receipts remain useful historical evidence.

## October 7 accepted scope and current package pair

Brian confirmed the matrix and accepted hosted Windows Server 2025 when a
Windows 11 machine is unavailable. macOS 26 hosted runners can cover iOS and
macOS; Ubuntu 24.04 needs a virtual display. Runner availability is not execution.
Final consumers use client SDK 0.0.1 and IntelliToggle client provider
0.0.1-beta.4. Existing SDK core runs and provider support-window consumers are
reusable, but do not replace canonical v3 receipts or Flutter runtime cells.
Decision: https://github.com/open-feature/dart-sdk/issues/167#issuecomment-6040698351
