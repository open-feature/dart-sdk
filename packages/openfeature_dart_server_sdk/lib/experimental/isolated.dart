/// Experimental isolated API instances (OpenFeature v0.9 section 1.8).
library;

import '../open_feature_api.dart';

/// Creates an API with independent providers, context, hooks and events.
///
/// Prefer [OpenFeatureAPI] for the ordinary singleton. Do not share a provider
/// object across active API instances. Call shutdown or dispose when finished.
OpenFeatureAPI createIsolatedOpenFeatureAPI() => OpenFeatureAPI.isolated();
