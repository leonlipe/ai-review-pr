# Review standards for <repo name>

These rules are read by the pr-review skill during reviews only.
They override the generic standards when they conflict.

## Architecture
- <e.g. No direct DB access outside `repositories/`.>
- <e.g. Business logic lives in `services/`, not controllers.>

## Conventions
- <e.g. Public functions need doc comments.>
- <e.g. Feature flags required for user-facing changes.>

## Upstream / fork notes
- <e.g. Upstream requires signed-off commits (DCO).>
- <e.g. Don't flag files under `vendor/`; synced from upstream.>

## Commands
- Tests: <e.g. npm test>
- Lint: <e.g. npm run lint>
