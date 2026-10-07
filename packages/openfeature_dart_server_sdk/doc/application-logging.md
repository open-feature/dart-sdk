# Application-owned logging

In the next release containing the quiet-logging correction, singleton and
isolated API construction preserve the application root logger configuration.
Evaluation and tracking errors no longer log on every call. Evaluation defaults,
details and error hooks are unchanged; use LoggingHook with an application-owned
logger callback for opt-in evaluation diagnostics. Lifecycle/configuration
records still go to application-installed listeners.

Release note for the maintainer-generated changelog: preserve application logging
configuration and quiet default evaluation/tracking diagnostics. Release Please
owns numeric changelog entries and generates this fix from its conventional
commit; do not add a separate Unreleased block or rewrite published history.
