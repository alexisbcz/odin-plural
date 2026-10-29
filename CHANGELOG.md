# Changelog

This file records all notable changes to this project.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-10-29

### Added

- `Category` and `Category_Set` for the six CLDR plural categories.
- `cardinal` and `ordinal` for `int`, `f64`, string and `Operands` arguments, with CLDR 49 rules for 77 locales and 4 legacy codes.
- `operands` and `Operands`, which compute the CLDR operands `n i v w f t e` and keep visible trailing zeros of string input, with `Parse_Error` for malformed numbers.
- `categories`, `ordinal_categories` and `integer_categories` to list the categories a locale uses.
- `i18n_pluralizer` and `i18n_slot`, which plug the rules into `core:text/i18n` catalogs.
- `match_locale` and `supported_locales`, with fallback from `pt_BR` and `pt-BR` to `pt`, then to the CLDR root rules.
- `tools/gen_rules.py`, which writes the rule tables and the CLDR sample tests from `plurals.xml` and `ordinals.xml`.

[Unreleased]: https://github.com/alexisbcz/odin-plural/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/alexisbcz/odin-plural/releases/tag/v0.1.0
