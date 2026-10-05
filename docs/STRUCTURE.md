# Source structure and build

The maintainable source is split by responsibility under `src/`. The
repository-root `VGUIFontChanger.ps1` is generated and is the only file required
at runtime. Source order is explicit in the `$sourceFiles` list in `Build.ps1`;
directory or file-name sorting is not used because PowerShell types, functions
and the final entry point have ordering requirements.

- `src/bootstrap` and `src/EntryPoint.ps1` must remain first and last in the
  source order.
- `src/cli` and `src/gui` contain the two user interfaces.
- `src/games`, `src/vpk`, `src/keyvalues`, `src/fonts` and `src/schemes` contain
  domain logic.
- `src/build`, `src/cache`, `src/settings` and `src/worker` contain application
  services.
- `src/tests` contains the self-tests bundled into the release script.

~~~powershell
.\Build.ps1
.\Build.ps1 -Check -Test
~~~

`Build.ps1` writes the local/release script as UTF-8 with BOM, so Windows
PowerShell 5.1 reads Korean correctly. Use
`-Encoding Utf8NoBom -OutputPath <path>` when producing a copy served to
`irm ... | iex`. The generated `VGUIFontChanger.ps1` is not committed; CI
builds it from `src/` and runs the integrated self-tests in Windows
PowerShell 5.1 and PowerShell 7.
