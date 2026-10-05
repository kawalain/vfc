# Repository Guidelines

## Project Structure & Module Organization

Maintainable PowerShell sources live under `src/`, grouped by responsibility: `gui/`, `cli/`, `fonts/`, `games/`, `vpk/`, `keyvalues/`, `schemes/`, and supporting service directories. `src/bootstrap/Parameters.ps1` must load first, while `src/EntryPoint.ps1` must load last. The authoritative order is the `$sourceFiles` list in `Build.ps1`.

Self-tests are stored in `src/tests/` and bundled into the release. Documentation belongs in `README.md` and `docs/`. The repository-root `VGUIFontChanger.ps1` is generated distribution output; do not edit it directly, and never commit it; CI builds it from `src/`.

## Build, Test, and Development Commands

Run commands from the repository root. Compatibility tests require both Windows PowerShell 5.1 and PowerShell 7:

```powershell
.\Build.ps1
.\Build.ps1 -Check -Test
.\VGUIFontChanger.ps1 -SelfTest
.\VGUIFontChanger.ps1 -Cli -ListFonts
```

`Build.ps1` combines the ordered sources into the single-file release. `-Check -Test` verifies that the generated file is current and runs all self-tests in both supported runtimes. Use `-Encoding Utf8NoBom -OutputPath <path>` only for web-served `irm | iex` artifacts.

## Coding Style & Naming Conventions

Target Windows PowerShell 5.1 and PowerShell 7 on Windows using built-in .NET APIs. Avoid dependencies that users must install. Use four-space indentation for new code, `PascalCase` for types, and approved PowerShell `Verb-Noun` names for functions. Keep `$script:` state explicit and limited. Add new source files to the ordered list in `Build.ps1`. Preserve CRLF endings for `.ps1` files.

Write documentation and code comments in English. Keep punctuation plain ASCII:
no em or en dashes, middle dots, ellipses or other decorative Unicode characters.
Korean text is reserved for localized UI resources, font-family fixtures, and
localization tests.

## Testing Guidelines

Tests use the project's built-in assertion-style self-test functions rather than an external framework. Name test files `*.Tests.ps1` and place them in `src/tests/`. Add regression coverage for parsing, VPK access, font resolution, generated output, or GUI behavior when changing those areas. Run `Build.ps1 -Check -Test` before every commit.

## Commit & Pull Request Guidelines

Write every commit message in English and follow Conventional Commits 1.0.0: `<type>[optional scope][!]: <description>`. Use lowercase types such as `feat`, `fix`, `docs`, `test`, `refactor`, `build`, `ci`, and `chore`, with a concise imperative description. Examples include `feat(gui): add font search` and `fix(cache): preserve dependency fingerprints`. Mark breaking changes with `!` or a `BREAKING CHANGE:` footer. Never commit the generated `VGUIFontChanger.ps1`; it is git-ignored and built by CI from the source changes. Bump `$script:VfcVersion` in `src/bootstrap/Parameters.ps1` in the same commit: `fix` bumps the patch, `feat` bumps the minor; the major stays `0`. Pull requests should explain user-visible behavior, list validation performed, link relevant issues, and include screenshots for visible GUI changes.

## Security & Configuration

Never commit AppData profiles, logs, caches, local paths, `.env` files, credentials, or signing keys. Review staged changes for personal information before publishing. Configure Git with a GitHub `noreply` email before creating public commits.
