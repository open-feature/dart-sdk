# Client platform acceptance for #166 and #167

This is the proposed release acceptance matrix, not a support certification.
Maintainers must approve the target list. A build alone does not satisfy runtime
acceptance; do not infer native results from a VM, widget test or Chrome run.

| Target | Required execution | Current evidence boundary |
| --- | --- | --- |
| Dart VM, 3.10.0 and stable | Core suite and canonical provider contract; record exact stable version | SDK CI has both lanes. IntelliToggle v2 receipts use Dart 3.13.4, SDK `21539eb`; published beta.1 cannot install on 3.10 |
| Chrome, Dart 3.10.0 and stable | Core suite and canonical provider contract in real browser | SDK CI has both lanes; IntelliToggle v2 receipts use Dart 3.13.4. Record browser version in final consumer receipt |
| Flutter web release, Chrome | Build release bundle, serve it, execute consumer assertions in browser | Final exact-version release runtime receipt pending |
| Android emulator, API 36.1, x86_64 | Launch Flutter consumer and execute runtime assertions | Pending; local installed emulator image is an available target, not evidence of a run |
| iOS simulator 26.2, iPhone 16e, Xcode 26.2 | Launch Flutter consumer and execute runtime assertions | Pending on macOS; simulator target is listed in the [runner image inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md) |
| macOS 26 desktop | Launch Flutter desktop consumer and execute runtime assertions | Pending |
| Ubuntu 24.04 Linux desktop | Launch Flutter desktop consumer under a display and execute runtime assertions | Pending |
| Windows 11 desktop | Launch Flutter desktop consumer and execute runtime assertions | Pending |

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
