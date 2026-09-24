# Shared client provider contract v1 (proposal)

This unpublished development-only package registers the same ten assertions for
each participating provider. It does not add dependencies to either published
SDK. The reference fixture tests the harness itself and **never counts as an
independently maintained provider**. Issue #166 requires two independent provider
receipts and maintainer review before stable promotion under #167.

Implement `ClientProviderFixture` in the provider's canonical repository using
the real provider and its controlled transport/backend. Do not copy the reference
provider into a vendor adapter. Keep HTTP, credentials, token renewal, platform
integration and transport controls in that provider repository.

Add this directory as a path development dependency from an immutable checkout
of `open-feature/dart-sdk`. Override `openfeature_dart_client_sdk` to that same
checkout's `packages/openfeature_dart_client_sdk` directory. The receipt tool
verifies actual package resolution. Then register a provider-owned test:

```dart
import 'package:openfeature_client_provider_contract/client_provider_contract.dart';
import 'support/my_provider_fixture.dart';

void main() => runClientProviderContract(
  providerName: 'My provider',
  createFixture: MyProviderFixture.new,
);
```

Run from the SDK checkout, substituting real provider paths:

```sh
python3 tool/client_provider_evidence.py \
  --classification external \
  --canonical-repository https://example.org/owner/provider \
  --provider-repo /path/to/provider \
  --working-directory /path/to/provider/package \
  --test-target test/shared_contract_test.dart \
  --platform vm \
  --output build/provider-evidence/vm
```

Repeat with `--platform chrome` for actual browser execution. A JavaScript build
alone does not count as browser execution, and Chrome is not native mobile.
Both test JSON and dependency resolution are archived with provider, SDK and
contract checkout commits/trees, dirty status, Dart version and all scenario
outcomes. Run one provider per receipt. Missing/skipped/failed scenarios fail
the receipt command; they are not optional passes.

| Scenario | Shared assertion | Provider-owned control |
| --- | --- | --- |
| C01 | Ready status is visible inside ready handlers | Initialization completion |
| C02 | Synchronous typed values/details, missing defaults, type mismatch | Five typed fixture flags |
| C03 | Failed initialization exposes error ordering and safe defaults | Transport failure |
| C04 | Refresh updates an existing client and emits configuration change | Backend flag update and refresh |
| C05 | Refresh failure is observable and can recover | Fail then restore transport |
| C06 | Identity change/sign-out retires prior private flags | Subject-specific snapshots; null means signed out |
| C07 | Rapid context requests end at the latest identity | Hold/release a reconciliation response |
| C08 | Pending old refresh cannot overwrite final new-identity state | Hold refresh while requesting a new identity |
| C09 | Replaced provider work cannot overwrite replacement flags | Delayed refresh and provider replacement |
| C10 | Shutdown clears state and ignores old work | Delayed refresh and cleanup counter |

The controls must capture a response at request time, not look up the newest
subject after release. Release must be idempotent. `close()` must release any
remaining gates and close test transports. The harness allows providers to
report refresh/sign-out errors via events and/or failed futures. It does not
require anonymous evaluation support, but sign-out cannot expose old private
flags. C08 accepts serialized or concurrent provider transports; provider-owned
tests must additionally show how truly out-of-order responses are quarantined
when that transport allows them.

## Evidence beyond these ten tests

Provider maintainers must attach their own results for token expiration/renewal,
token acquisition failure, HTTP failure/timeout/offline recovery, request
cancellation, cache persistence across identities, and any platform-specific
initialization/resume behavior. Do not put secrets into receipts or examples.
Record whether the backend was a controlled test transport or a real service;
passing the former does not establish production connectivity.

Receipts deliberately keep `independent_provider_gate_satisfied: false`.
Maintainers must verify canonical provenance, independent ownership, SDK pin,
transport tests and the declared platform matrix before accepting two providers.
Two runs/platforms or two provider classes from one maintained implementation do
not meet the two-provider gate. Datadog participation remains unconfirmed.

The v1 tests supplement existing SDK lifecycle/race tests; they do not replace
the full requirement-indexed static-context review. The experimental API import
is used only to isolate the API owned by each test.
