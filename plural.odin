/*
Package plural selects CLDR plural categories for numbers, so that messages
read correctly in Russian, Arabic, Polish, Welsh and every other language
whose plural rules are not "one or many".

It implements the cardinal ("3 files") and ordinal ("3rd place") rules of the
Unicode Common Locale Data Repository for the locales in rules.odin, using
the CLDR operands n, i, v, w, f, t and e. A number passed as a string keeps
its visible trailing zeros, so "1" and "1.0" can fall into different
categories, as CLDR requires.

The package never allocates and keeps no mutable state, so every procedure
is safe to call from any thread.

Example:
	import "core:fmt"
	import plural "shared:plural"

	main :: proc() {
		fmt.println(plural.cardinal("ru", 3))   // Few
		fmt.println(plural.cardinal("ru", 5))   // Many
		fmt.println(plural.ordinal("en", 22))   // Two, as in "22nd"

		c, err := plural.cardinal("en", "1.0")  // Other: "1.0 files"
		if err == .None {
			fmt.println(c)
		}
	}

To use it with core:text/i18n, pass i18n_pluralizer to the catalog loader:

	catalog, err := i18n.parse_mo(data, pluralizer = plural.i18n_pluralizer("pl"))
*/
package plural

/*
Category is a CLDR plural category. Each locale uses a subset of them; see
categories and ordinal_categories. `.Other` is always in the subset.
*/
Category :: enum u8 {
	Zero,
	One,
	Two,
	Few,
	Many,
	Other,
}

// Category_Set is a set of plural categories, such as the ones a locale uses.
Category_Set :: bit_set[Category;u8]

// Rule_Proc is the shape of one locale's cardinal or ordinal rule.
Rule_Proc :: #type proc "contextless" (o: Operands) -> Category

// Locale_Rules is one row of the generated locale table.
@(private)
Locale_Rules :: struct {
	name:         string,
	cardinal:     Rule_Proc,
	ordinal:      Rule_Proc,
	pluralizer:   proc(n: int) -> int,
	cardinal_set: Category_Set,
	ordinal_set:  Category_Set,
	integer_set:  Category_Set,
}

// ROOT_LOCALE is the name that match_locale returns when no rule set matches.
ROOT_LOCALE :: "root"

/*
cardinal returns the cardinal plural category of a number in a locale: the
form to use in "N files". It accepts an int, an f64, a string or Operands.
The string form also returns a Parse_Error.
*/
cardinal :: proc {
	cardinal_int,
	cardinal_f64,
	cardinal_string,
	cardinal_operands,
}

/*
ordinal returns the ordinal plural category of a number in a locale: the
form to use in "Nth place". It accepts an int, an f64, a string or Operands.
The string form also returns a Parse_Error.
*/
ordinal :: proc {
	ordinal_int,
	ordinal_f64,
	ordinal_string,
	ordinal_operands,
}

/*
cardinal_operands returns the cardinal category for already computed
operands. Use it to classify one number in several locales without parsing
it again.

Inputs:
- locale: a BCP 47 or POSIX locale such as "pt-BR", "pt_BR" or "ru_RU.UTF-8". See match_locale.
- o: the operands of the number.
*/
cardinal_operands :: proc(locale: string, o: Operands) -> Category {
	return lookup(locale).cardinal(o)
}

// cardinal_int returns the cardinal category of an integer. Negative numbers use their absolute value.
cardinal_int :: proc(locale: string, n: int) -> Category {
	return lookup(locale).cardinal(operands_from_int(n))
}

/*
cardinal_f64 returns the cardinal category of a float. The float has no
visible trailing zeros: 1.0 behaves like 1. Use cardinal_string with the
formatted number when the displayed digits matter. NaN and infinities
return `.Other`.
*/
cardinal_f64 :: proc(locale: string, n: f64) -> Category {
	o, err := operands_from_f64(n)
	if err != .None {
		return .Other
	}
	return lookup(locale).cardinal(o)
}

/*
cardinal_string returns the cardinal category of a number written as a
string, keeping its visible trailing zeros. Pass the exact digits you
display, for example "1.50".

Returns:
- category: the category; `.Other` when `err` is not `.None`.
- err: the Parse_Error from operands_from_string.
*/
cardinal_string :: proc(locale: string, n: string) -> (category: Category, err: Parse_Error) {
	o: Operands
	o, err = operands_from_string(n)
	if err != .None {
		return .Other, err
	}
	return lookup(locale).cardinal(o), .None
}

// ordinal_operands returns the ordinal category for already computed operands.
ordinal_operands :: proc(locale: string, o: Operands) -> Category {
	return lookup(locale).ordinal(o)
}

// ordinal_int returns the ordinal category of an integer, for example `.Two` for 22 in "en" ("22nd").
ordinal_int :: proc(locale: string, n: int) -> Category {
	return lookup(locale).ordinal(operands_from_int(n))
}

// ordinal_f64 returns the ordinal category of a float. NaN and infinities return `.Other`.
ordinal_f64 :: proc(locale: string, n: f64) -> Category {
	o, err := operands_from_f64(n)
	if err != .None {
		return .Other
	}
	return lookup(locale).ordinal(o)
}

/*
ordinal_string returns the ordinal category of a number written as a string.

Returns:
- category: the category; `.Other` when `err` is not `.None`.
- err: the Parse_Error from operands_from_string.
*/
ordinal_string :: proc(locale: string, n: string) -> (category: Category, err: Parse_Error) {
	o: Operands
	o, err = operands_from_string(n)
	if err != .None {
		return .Other, err
	}
	return lookup(locale).ordinal(o), .None
}

/*
categories returns the cardinal categories that `locale` uses, for example
{.One, .Few, .Many, .Other} for "ru". Unknown locales return {.Other}.
*/
categories :: proc(locale: string) -> Category_Set {
	return lookup(locale).cardinal_set
}

// ordinal_categories returns the ordinal categories that `locale` uses, for example {.One, .Two, .Few, .Other} for "en".
ordinal_categories :: proc(locale: string) -> Category_Set {
	return lookup(locale).ordinal_set
}

/*
integer_categories returns the cardinal categories that a whole number
without an exponent can select in `locale`. For "ru" that is
{.One, .Few, .Many}: `.Other` only applies to decimals. These are the
categories that i18n_pluralizer numbers.
*/
integer_categories :: proc(locale: string) -> Category_Set {
	return lookup(locale).integer_set
}

/*
i18n_pluralizer returns a procedure that core:text/i18n can use as the
`pluralizer` of a catalog, so that `i18n.get_n` picks the right plural form.

The procedure maps the cardinal category of the quantity to its position in
integer_categories(locale), in Category order. For "ru" that is
one = 0, few = 1 and many = 2; for "ar" it is zero = 0 through other = 5;
for "en" it is one = 0 and other = 1. This matches the plural form order that
CLDR-based tools such as Weblate and Pontoon write into .po files.
core:text/i18n clamps a slot past the last form to the last form.

The returned procedure is a plain procedure with no captured state, so it
stays valid for the life of the program. Unknown locales get a procedure
that always returns 0.

Example:
	catalog, err := i18n.parse_mo(data, pluralizer = plural.i18n_pluralizer("ru"))
	if err != .None {
		return
	}
	defer i18n.destroy(catalog)
	fmt.println(i18n.get_n("file", 3, catalog)) // "файла"
*/
i18n_pluralizer :: proc(locale: string) -> proc(n: int) -> int {
	return lookup(locale).pluralizer
}

/*
i18n_slot returns the plural slot for `n` in `locale`: the value that the
procedure from i18n_pluralizer returns. Use it to index plural forms that
you store yourself.
*/
i18n_slot :: proc(locale: string, n: int) -> int {
	return lookup(locale).pluralizer(n)
}

/*
match_locale reports which rule set `locale` uses.

Matching ignores case, treats "_" like "-", and drops a POSIX encoding or
modifier such as ".UTF-8" or "@euro". It tries the whole tag first, then
removes subtags from the right: "pt-BR" uses "pt", "pt_PT" uses "pt-pt"
and "zh-Hant-TW" uses "zh". A tag that matches nothing uses the CLDR root
rules, where every number is `.Other`.

Returns:
- name: the matched table name, such as "pt" or "pt-pt", or ROOT_LOCALE.
- ok: false when the root rules were used.
*/
match_locale :: proc(locale: string) -> (name: string, ok: bool) {
	rules, found := find(locale)
	return rules.name, found
}

// supported_locales returns the names of every locale with its own rules, sorted, plus ROOT_LOCALE. The slice is read-only.
supported_locales :: proc() -> []string {
	return LOCALE_NAMES[:]
}

@(private)
lookup :: proc(locale: string) -> ^Locale_Rules {
	rules, _ := find(locale)
	return rules
}

@(private)
find :: proc(locale: string) -> (rules: ^Locale_Rules, ok: bool) {
	tag := locale
	// Drop a POSIX encoding or modifier: "ru_RU.UTF-8", "ca_ES@valencia".
	for c, i in transmute([]u8)tag {
		if c == '.' || c == '@' {
			tag = tag[:i]
			break
		}
	}
	for len(tag) > 0 {
		if row, found := search(tag); found {
			return row, row.name != ROOT_LOCALE
		}
		cut := len(tag) - 1
		for cut > 0 && tag[cut] != '-' && tag[cut] != '_' {
			cut -= 1
		}
		tag = tag[:cut]
	}
	return root_rules(), false
}

@(private)
root_rules :: proc() -> ^Locale_Rules {
	row, _ := search(ROOT_LOCALE)
	return row
}

// search does a binary search of LOCALE_TABLE, comparing case-insensitively with "_" equal to "-".
@(private)
search :: proc(tag: string) -> (row: ^Locale_Rules, ok: bool) {
	lo, hi := 0, len(LOCALE_TABLE)
	for lo < hi {
		mid := lo + (hi - lo) / 2
		switch order := compare_tag(LOCALE_TABLE[mid].name, tag); {
		case order < 0:
			lo = mid + 1
		case order > 0:
			hi = mid
		case:
			return &LOCALE_TABLE[mid], true
		}
	}
	return nil, false
}

@(private)
compare_tag :: proc(name, tag: string) -> int {
	for k in 0 ..< min(len(name), len(tag)) {
		a := name[k]
		b := fold(tag[k])
		if a != b {
			return -1 if a < b else 1
		}
	}
	switch {
	case len(name) < len(tag):
		return -1
	case len(name) > len(tag):
		return 1
	}
	return 0
}

@(private)
fold :: #force_inline proc "contextless" (c: u8) -> u8 {
	switch c {
	case 'A' ..= 'Z':
		return c + ('a' - 'A')
	case '_':
		return '-'
	}
	return c
}
