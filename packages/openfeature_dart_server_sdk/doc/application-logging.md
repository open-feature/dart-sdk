# Application-owned logging

In the next release containing the quiet-logging correction, singleton and
isolated API construction preserve the application root logger configuration.
Evaluation and tracking errors no longer log on every call. Evaluation defaults,
details and error hooks are unchanged; use LoggingHook with an application-owned
logger callback for opt-in evaluation diagnostics. Lifecycle/configuration
records still go to application-installed listeners.
