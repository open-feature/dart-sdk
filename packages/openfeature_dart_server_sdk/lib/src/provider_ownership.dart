import 'dart:async';

import '../feature_provider.dart';
import 'provider_adapter.dart';

/// Identity-based ownership, including adapters exposed by existing clients.
abstract final class ProviderOwnership {
  static final _owners = Expando<Object>('OpenFeature provider owner');
  static final _pendingCleanup = Expando<Future<void>>(
    'OpenFeature timed-out provider cleanup',
  );

  static Provider definition(Provider provider) =>
      provider is ResolverProviderAdapter ? provider.delegate : provider;

  static void claim(Provider provider, Object owner) {
    ensureAvailable(provider);
    final definition = ProviderOwnership.definition(provider);
    final previous = _owners[definition];
    if (previous != null && !identical(previous, owner)) {
      throw StateError(
        'A provider instance cannot belong to multiple active '
        'APIs. Create a separate provider or await its previous shutdown.',
      );
    }
    _owners[definition] = owner;
  }

  /// A Dart timeout does not cancel provider work. Prevent a new lifecycle from
  /// racing that work, even if its old API has reset and released ownership.
  static void quarantineUntil(Provider provider, Future<void> cleanup) {
    final definition = ProviderOwnership.definition(provider);
    final previous = _pendingCleanup[definition];
    final pending = previous == null
        ? cleanup
        : Future.wait<void>([previous, cleanup]).then<void>((_) {});
    _pendingCleanup[definition] = pending;
    void release() {
      if (identical(_pendingCleanup[definition], pending)) {
        _pendingCleanup[definition] = null;
      }
    }

    unawaited(
      pending.then<void>(
        (_) => release(),
        onError: (Object _, StackTrace __) => release(),
      ),
    );
  }

  /// Rejects reuse while timed-out cleanup still owns the provider's resources.
  static void ensureAvailable(Provider provider) {
    if (_pendingCleanup[definition(provider)] != null) {
      throw StateError(
        'Provider cleanup is still pending after a timeout. '
        'Use a new provider instance or wait for cleanup to finish.',
      );
    }
  }

  static void release(Provider provider, Object owner) {
    final definition = ProviderOwnership.definition(provider);
    if (identical(_owners[definition], owner)) _owners[definition] = null;
  }
}
