# plural

[![CI](https://github.com/alexisbcz/odin-plural/actions/workflows/ci.yml/badge.svg)](https://github.com/alexisbcz/odin-plural/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Odin](https://img.shields.io/badge/Odin-dev--2026--09-1e5a99.svg)](https://odin-lang.org)

CLDR plural rules for Odin: pick the right form of "1 file, 2 files" in Russian, Arabic, Polish, Welsh and more than 70 other locales, and plug the rules straight into `core:text/i18n`.

`core:text/i18n` loads gettext and Qt catalogs, but unless you pass a `pluralizer` it uses `n != 1`. That rule gives Russian "5 файла" instead of "5 файлов" and can't express the six forms of Arabic. This package implements the [Unicode CLDR](https://cldr.unicode.org/index/cldr-spec/plural-rules) cardinal and ordinal rules, computed from the CLDR operands, so that "1" and "1.0" can fall into different categories as CLDR requires.

## Install

The repository root is the package, so you can vendor it in two ways.

As a Git submodule inside your project:

```sh
git submodule add https://github.com/alexisbcz/odin-plural libs/plural
```

```odin
import "libs/plural"
```

As a copy in a shared collection that all your projects use:

```sh
git clone https://github.com/alexisbcz/odin-plural ~/odin-shared/plural
odin build . -collection:shared=$HOME/odin-shared
```

```odin
import "shared:plural"
```

## Quick start

```odin
package main

import "core:fmt"
import "shared:plural"

Forms :: [plural.Category]string

main :: proc() {
	files_ru := #partial Forms {
		.One   = "файл",
		.Few   = "файла",
		.Many  = "файлов",
		.Other = "файла",
	}
	for n in ([]int{1, 2, 5, 21}) {
		fmt.println(n, files_ru[plural.cardinal("ru", n)]) // 1 файл, 2 файла, 5 файлов, 21 файл
	}

	suffix_en := #partial Forms {
		.One   = "st",
		.Two   = "nd",
		.Few   = "rd",
		.Other = "th",
	}
	fmt.printf("%d%s\n", 22, suffix_en[plural.ordinal("en", 22)]) // 22nd

	// Pass the digits you display as a string to keep trailing zeros.
	c, err := plural.cardinal("en", "1.0")
	if err == .None {
		fmt.println(c) // Other, as in "1.0 files"
	}
}
```

## Use with core:text/i18n

`i18n_pluralizer` returns a `proc(int) -> int` that you pass to the catalog loader:

```odin
package main

import "core:fmt"
import "core:text/i18n"
import "shared:plural"

CATALOG :: #load("ru.mo")

main :: proc() {
	catalog, err := i18n.parse_mo(CATALOG, pluralizer = plural.i18n_pluralizer("ru_RU.UTF-8"))
	if err != .None {
		fmt.eprintln("cannot load catalog:", err)
		return
	}
	defer i18n.destroy(catalog)

	for n in ([]int{1, 2, 5, 11, 21}) {
		fmt.println(n, i18n.get_n("file", n, catalog))
	}
}
```

The slot number is the position of the category among the categories that whole numbers can select in that locale, in CLDR order: zero, one, two, few, many, other. For Russian that is one = 0, few = 1, many = 2. For Arabic it's zero = 0 through other = 5. This is the plural form order that CLDR-based tools such as Weblate write into `.po` files. `integer_categories(locale)` returns the categories that the slots number.

Qt Linguist catalogs work the same way through `i18n.parse_qt`. That procedure edits the bytes you pass and frees them when you call `i18n.destroy`, so pass a copy made with the catalog's allocator, not `#load` data:

```odin
data := transmute([]u8)strings.clone(TS_SOURCE)
catalog, err := i18n.parse_qt(data, pluralizer = plural.i18n_pluralizer("pl"))
```

`core:text/i18n` ignores the `Plural-Forms` header of a catalog, so the pluralizer alone decides the slot. Some legacy headers use another order. Latvian files from older tools, for example, put zero last. Check the header of your catalog when you switch to this package.

## API overview

| Declaration | Purpose |
| --- | --- |
| `Category` | `enum {Zero, One, Two, Few, Many, Other}` |
| `Category_Set` | `bit_set[Category; u8]` |
| `cardinal(locale, n)` | Category for "N files"; `n` is an `int`, `f64`, string or `Operands` |
| `ordinal(locale, n)` | Category for "Nth place", with the same argument types |
| `categories(locale)` | Cardinal categories the locale uses |
| `ordinal_categories(locale)` | Ordinal categories the locale uses |
| `integer_categories(locale)` | Cardinal categories that whole numbers can select |
| `i18n_pluralizer(locale)` | `proc(int) -> int` for `core:text/i18n` catalogs |
| `i18n_slot(locale, n)` | The slot that the pluralizer returns for `n` |
| `match_locale(locale)` | The rule set a locale tag resolves to, and whether it matched |
| `supported_locales()` | Every locale with its own rules |
| `operands(n)` | CLDR operands `n i v w f t e` of a string, `int` or `f64` |
| `Parse_Error` | Why a number string didn't parse |
| `CLDR_VERSION` | The CLDR release the tables come from |

The `int` and `f64` forms take exactly those types. Cast other numeric types first, for example `plural.cardinal("ru", int(size))` for an `i64` file size.

The string forms of `cardinal` and `ordinal` return `(Category, Parse_Error)`. On an error the category is `.Other`. The `f64` forms return `.Other` for NaN and infinities.

No procedure allocates, and none takes an allocator.

## Numbers as strings

A float can't carry trailing zeros, so `cardinal("en", 1.0)` sees the number 1 and returns `.One`. When you display "1.0", pass the string instead. The parser accepts the CLDR sample syntax:

| Input | `i` | `v` | `f` | `t` | `e` | English | Russian |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `"1"` | 1 | 0 | 0 | 0 | 0 | One | One |
| `"1.0"` | 1 | 1 | 0 | 0 | 0 | Other | Other |
| `"1.50"` | 1 | 2 | 50 | 5 | 0 | Other | Other |
| `"1.2c6"` | 1200000 | 0 | 0 | 0 | 6 | Other | Many |
| `"-21"` | 21 | 0 | 0 | 0 | 0 | Other | One |

The exponent marker can be `c`, `e`, `C` or `E`. Negative numbers use their absolute value. Whitespace, digit grouping and non-ASCII digits are errors, so format the number for display first and then strip the grouping.

## Locales

Locale matching ignores case, treats `_` like `-`, drops a POSIX suffix such as `.UTF-8` or `@euro`, and removes subtags from the right until it finds a rule set. `pt_BR` uses `pt`, `pt_PT` has its own rules, and `zh-Hant-TW` uses `zh`. A tag that matches nothing uses the CLDR root rules, where every number is `.Other`, and `match_locale` returns `false`.

The tables cover `af`, `am`, `ar`, `az`, `be`, `bg`, `bn`, `bs`, `ca`, `cs`, `cy`, `da`, `de`, `el`, `en`, `es`, `et`, `eu`, `fa`, `fi`, `fil`, `fr`, `ga`, `gl`, `gu`, `he`, `hi`, `hr`, `hu`, `hy`, `id`, `is`, `it`, `ja`, `ka`, `kk`, `km`, `kn`, `ko`, `ky`, `lo`, `lt`, `lv`, `mk`, `ml`, `mn`, `mr`, `ms`, `my`, `nb`, `ne`, `nl`, `nn`, `pa`, `pl`, `pt`, `pt-PT`, `ro`, `ru`, `si`, `sk`, `sl`, `sq`, `sr`, `sv`, `sw`, `ta`, `te`, `th`, `tr`, `uk`, `ur`, `uz`, `vi`, `yue`, `zh` and `zu`, plus the legacy codes `in`, `iw`, `no` and `tl`.

## Where the rules come from

`rules.odin` holds one Odin procedure per CLDR rule set, with the CLDR rule text as a comment above each condition. `tools/gen_rules.py` writes it from CLDR 49 `plurals.xml` and `ordinals.xml`. The same script writes `tests/cldr_samples_test.odin`, which checks every `@integer` and `@decimal` sample in those files for every supported locale.

To add a locale, add its CLDR name to `LOCALES` in the script and run it:

```sh
python3 tools/gen_rules.py
odin test tests -vet -strict-style -disallow-do
```

To move to a newer CLDR release, change `CLDR_RELEASE` in the script and run it again.

## Examples

Each directory under `examples/` is a runnable program:

```sh
odin run examples/basic
odin run examples/gettext
```

## Design notes

- The rules never touch floating point. CLDR ranges only match whole numbers, so `n = 1` becomes `t == 0 && i == 1`.
- Integer parts longer than 18 digits keep their last 18 digits, offset by 10^18, so every modulus CLDR uses stays exact.
- The package keeps no mutable state and never allocates, so you can call it from any thread.

## Testing

```sh
odin check . -vet -strict-style -disallow-do -no-entry-point
odin test tests -vet -strict-style -disallow-do
vale sync && vale *.md
```

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md). Commits follow Conventional Commits, and every change that users can see gets a line in [CHANGELOG.md](CHANGELOG.md).

## License

MIT. See [LICENSE](LICENSE). The plural rules come from the Unicode CLDR, which is under the [Unicode License v3](https://www.unicode.org/license.txt).
