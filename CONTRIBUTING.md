# Contributing to Wendelin

Thanks for your interest! Bug reports, translations, documentation fixes and code are all welcome.

- **Found a bug?** Open a [bug report](https://github.com/brokoskokoli/wendelin/issues/new?template=bug_report.yml).
- **Have an idea?** Start a [feature request](https://github.com/brokoskokoli/wendelin/issues/new?template=feature_request.yml)
  or a thread in [Discussions](https://github.com/brokoskokoli/wendelin/discussions).
- **Security issue?** Please don't open a public issue – see [SECURITY.md](SECURITY.md).

## Development setup

Wendelin is a Flutter app (Android first) in a Pub workspace, with a small Rust module in
`native/attest`. The details (toolchain, layout, dependency rules, tests, git workflow) are in
[docs/ENGINEERING.md](docs/ENGINEERING.md); most project documentation is in German.

```sh
flutter pub get                         # in the repository root
dart run tool/gate.dart --changed       # checks for the packages you changed
tool/t.sh <test files>                  # run single tests
```

The full gate runs in CI before anything is merged.

## Project layout

| Path | Contents |
|---|---|
| `app/` | The Flutter app (UI, platform glue) |
| `packages/` | Pure Dart packages (no Flutter import); device access only through ports |
| `native/attest/` | Rust module for attestation checks |
| `tool/` | Gate, test and release scripts |
| `docs/` | Architecture, engineering rules, work packages, decisions |

## Coding conventions

- Formatting and analysis are checked by the gate and in CI; run it before committing.
- Keep pull requests focused: one logical change per PR, with tests for new behaviour.
- Never commit secrets, personal data or absolute local paths.

## Commit messages

- One logical change per commit. Summary line ≤ 72 characters, no trailing period.
- In the body, explain *why*, and reference issues (`#123`).
- Use your GitHub `noreply` address as the author e-mail; don't add other people's addresses.

## Licensing of contributions

Wendelin is licensed under **GPL-3.0-or-later** (see [LICENSE](LICENSE)). By opening a pull
request you agree that your contribution is licensed under GPL-3.0-or-later. In addition, you
agree that the maintainer may also use and distribute your contribution under other licenses
(for example in a dual-licensed or commercial edition of Wendelin). There is no separate CLA to
sign. A `Signed-off-by` line ([Developer Certificate of Origin](https://developercertificate.org))
is welcome but not required.

Only contribute code you wrote yourself or that is under a compatible license. Say so in the PR
when you include third-party code, and add its license to `LICENSES/` and `REUSE.toml`.

## Pull request checklist

- [ ] The change is described in an issue (for features: discussed first)
- [ ] The gate passes locally (`dart run tool/gate.dart --changed`)
- [ ] New behaviour has tests
- [ ] User-visible changes are noted in [CHANGELOG.md](CHANGELOG.md) under *Unreleased*
- [ ] Docs updated where needed

The [pull request template](.github/PULL_REQUEST_TEMPLATE.md) contains the same list.
