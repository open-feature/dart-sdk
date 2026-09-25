# Opt-in evaluation context snapshots

This is an additive step toward [#159](https://github.com/open-feature/dart-sdk/issues/159),
based on [OpenFeature v0.9.0 section 3](https://github.com/open-feature/spec/blob/v0.9.0/specification/sections/03-evaluation-context.md).
It is not a full SDK conformance claim or an automatic migration of legacy data.

## Existing applications

The existing `const EvaluationContext(attributes: ...)` constructor and
`OpenFeatureEvaluationContext(map, targetingKey: ...)` adapter retain their
legacy value semantics. Evaluation, tracking, client creation, global context
through `setGlobalContext`, transaction contexts, and hook contributions do not
implicitly validate or deeply freeze those values. Null, provider-specific
objects, Duration, Uri, enums, BigInt, lazy Iterables, and typed collections
continue to reach the provider unchanged. The SDK does not serialize these
values or claim every provider supports them.

The positional-map adapter still makes its outer attributes map read-only.
Nested legacy values remain caller-owned and can change after registration or
while an asynchronous hook is suspended. Providers receive a fresh mutable
outer effective map; writing a provider-local field does not mutate the
caller's outer attributes. Nested legacy objects retain their existing aliasing.
Hooks receive a read-only outer view and return contributions as before.

## Opt into a snapshot

Use `EvaluationContext.immutable`, `.snapshot()` or the new canonical
`setEvaluationContext` setter to explicitly capture data. All three use the
same snapshot contract. Snapshot before passing data to legacy APIs when
isolation is required:

```dart
import 'package:openfeature_dart_server_sdk/evaluation_context.dart';
import 'package:openfeature_dart_server_sdk/open_feature_api.dart';
import 'package:openfeature_dart_server_sdk/transaction_context.dart';

final fields = <String, dynamic>{
  'account': {'plan': 'standard'},
  'groups': ['riders'],
  'optional': null,
};
final context = EvaluationContext.immutable(
  targetingKey: 'rider-123', attributes: fields,
);
final api = OpenFeatureAPI();
api.setEvaluationContext(context);
final client = api.getClient('matching');
final enabled = await client.getBooleanFlag(
  'matching-enabled', defaultValue: false, context: context,
);
final request = TransactionContext(
  transactionId: 'request-123', attributes: context.toProviderContext(),
);
```

An immutable context copies nested maps/lists, its full parent chain, and
local targeting rules (values, metadata and subrules). Its `createChild`
method snapshots new child data. Repeated `.snapshot()` and
`toProviderContext()` calls reuse the immutable snapshot. Legacy `createChild`
retains its prior behavior. Merging two immutable contexts produces an immutable
context; a merge involving a legacy context preserves legacy values. Call
`.snapshot()` on that result to opt into validation and isolation.

For attributes and rule metadata, the strict value model accepts null, bool,
String, num, DateTime, string-keyed
maps and lists at every depth. DateTime retains its Dart instant/timezone.
Unsupported objects, functions, sets, lazy Iterables, non-string keys and
cycles throw `ArgumentError` during explicit construction. Errors include the
field path, such as `attributes.account.orders[0].total`, without printing the
field's value. Convert provider-specific data deliberately before opting in.

Rule operands use the targeting evaluator's broader value model. Their nested
maps/lists are copied and frozen, including non-string map keys, and cycles
are rejected. Non-collection operands such as enums, Duration, Uri and custom
objects retain their identity. Custom mutable objects, sets and other Iterables
remain caller-owned and must stay stable for the snapshot's lifetime.

Attribute and metadata snapshots normalize nested collections to `List<Object?>` and
`Map<String, Object?>`; they do not promise the original generic arguments or
concrete collection subclasses. Read a typed list using
`(context.getAttribute('groups') as List).cast<String>()`, or make a mutable
copy with `List<String>.from(...)`. A provider that mutates nested structures
must copy those structures when accepting opt-in immutable input. This
normalization does not run on legacy input.

## Targeting keys and merging

Immutable `attributes` and `getAttribute('targetingKey')` expose the local key,
including an explicit constructor argument. That argument wins over the map
alias at the same level. `toProviderContext()` includes inherited fields and
the effective key. Null custom fields in immutable contexts shadow parent
values. The legacy adapter continues to expose its original attributes.

Legacy constructors allow an attributes entry named `targetingKey` even when
an explicit targeting key is supplied. The original attributes map keeps that
entry; `getAttribute('targetingKey')` and `toProviderContext()` prefer the explicit
key and emit one effective map key. This legacy-only alias distinction is
recorded for the [#165 semantic review](https://github.com/open-feature/dart-sdk/issues/165),
not silently normalized into the immutable API. The regression
`legacy targeting-key collision preserves attributes and resolves explicit key`
in `context_review_regression_test.dart` covers both legacy constructors.

For the helper `merge`, the right explicit targeting key wins, followed by
the left explicit key, then local map aliases (right before left). Inherited
keys are used only if neither context has a local key. Immutable construction
normalizes a local map alias to the canonical targeting-key field. Both complete parent chains contribute other fields. This preserves the
legacy explicit-key precedence without discarding inherited fields.

Both the canonical context and legacy wrapper merge concatenate the local rule
lists (left, then right) and retain the left context's cache duration. Parent
attributes are flattened; parent rule inheritance is not retained by merge.

The SDK's evaluation/tracking context levels have a separate precedence:
API -> transaction -> client -> invocation, with before-hook contributions
applied last for evaluation. Higher levels overwrite lower levels, including
inherited targeting keys within those levels.

## Errors and migration scope

[Requirement 1.4.10](https://github.com/open-feature/spec/blob/v0.9.0/specification/sections/01-flag-evaluation.md#requirement-1410)
requires evaluation failures to return the application default rather than
throw. An invalid explicit snapshot created inside a before hook is reported
as `ERROR` / `INVALID_CONTEXT`, with the path in detailed evaluation errors.
Unrelated provider errors retain their existing classification. Tracking
continues its existing non-throwing contract and logs failures.

There is no analyzer deprecation or removal date in this additive stage.
Brian accepted the additive context scope in
[#159](https://github.com/open-feature/dart-sdk/issues/159#issuecomment-5831385040).
The spec does not require deep immutability or rejection of every unsupported
legacy value. [#195](https://github.com/open-feature/dart-sdk/issues/195) tracks
warnings and migration examples before any separately approved breaking change
to legacy constructors. No deprecation/removal version is selected here.
Hook and isolation implementations are integrated; their review and the broader
semantic conformance gates remain distinct from these opt-in guarantees.

## Verification

`context_review_regression_test.dart` exercises legacy values, typed casts,
provider writes, tracking, key precedence, child/rule snapshots and paths.
`rule_snapshot_merge_regression_test.dart` covers arbitrary rule operands,
nested collection isolation, operand cycles and wrapper merge preservation.
`context_contract_test.dart` checks the strict model, five-level precedence,
explicit isolation across awaited hooks and overlapping transactions, and
late global replacement. Both independently published SDKs contain the same
immutable-value implementation; a repository test detects drift. The client
package also tests cycle rejection, shared acyclic data and error paths.
