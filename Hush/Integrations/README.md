# Integrations

Place external SDK adapters in this folder.

## Suggested layout

- `OpenAI/` for live provider adapters
- `AppleIntelligence/` for on-device model routing
- `Storage/` for persistence providers
- `Telemetry/` for analytics and logging sinks

Keep each integration behind protocols in `HUSH/Core` so features stay testable and independent.
