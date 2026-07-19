# Nexora Coding Rules

## Clean Architecture

- Keep dependencies pointing inward.
- Separate API, service, platform, storage, and UI concerns.
- Put platform-specific logic behind adapters.
- Keep business logic out of route handlers and widgets.

## Readability

- Prefer simple control flow over clever code.
- Keep functions small and single-purpose.
- Use explicit names for files, classes, and variables.
- Optimize for quick understanding by humans and AI tools.

## Naming Conventions

- Python: `snake_case` for modules, functions, and variables; `PascalCase` for classes.
- Flutter/Dart: `PascalCase` for types and widgets; `camelCase` for members and variables.
- Use clear feature names instead of generic names like `manager` or `helper`.
- Keep backend route versions explicit, such as `v1`.

## Error Handling

- Validate inputs early.
- Fail with clear, actionable messages.
- Separate validation, extraction, download, conversion, and storage errors.
- Remove partial files on failure.
- Never expose internal stack traces to the mobile app.

## Logging

- Log enough detail to debug failures.
- Keep user-facing errors separate from internal logs.
- Log job IDs, platform, and failure stage when available.
- Avoid noisy logs for normal control flow.

## Configuration

- Read environment-specific values from configuration, not hardcoded literals.
- Keep defaults small and obvious.
- Group configuration by purpose.
- Do not mix config loading with business logic.

## File Organization

- Keep one responsibility per folder.
- Group code by feature or layer, not by convenience.
- Keep generated or temporary files out of source folders.
- Put tests next to the responsibility they verify.

## Comments

- Prefer self-explanatory code over comments.
- Add comments only for non-obvious decisions, constraints, or workarounds.
- Do not comment on what the code already makes clear.

## Documentation

- Keep docs short, current, and implementation-focused.
- Update project docs when architecture or workflow changes.
- Document only what helps future implementation.

## Git Commits

- Keep commits small and focused.
- Use clear imperative commit messages.
- Do not mix unrelated changes in one commit.
- Prefer one logical change per commit.

## Rule Priority

- Follow these rules by default unless a later project decision overrides them.
- Favor simplicity when two options are otherwise equal.
