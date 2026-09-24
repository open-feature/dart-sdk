import '../feature_provider.dart';
import 'provider_adapter.dart';

/// Identity-based ownership, including adapters exposed by existing clients.
abstract final class ProviderOwnership {
  static final _owners = Expando<Object>('OpenFeature provider owner');

  static Provider definition(Provider provider) =>
      provider is ResolverProviderAdapter ? provider.delegate : provider;

  static void claim(Provider provider, Object owner) {
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

  static void release(Provider provider, Object owner) {
    final definition = ProviderOwnership.definition(provider);
    if (identical(_owners[definition], owner)) _owners[definition] = null;
  }
}
