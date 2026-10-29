// Package plural_tests holds the unit tests for plural. Run them with `odin test tests`.
package plural_tests

import plural ".."
import "core:strconv"
import "core:testing"

// Sample is one CLDR sample value and the category it must select.
Sample :: struct {
	value:    string,
	category: plural.Category,
}

// expect_cardinal_samples checks a locale's cardinal rules against CLDR samples.
// Plain integers also go through the int, f64 and i18n paths, and decimals
// without trailing zeros also go through the f64 path.
expect_cardinal_samples :: proc(
	t: ^testing.T,
	locale: string,
	want_set: plural.Category_Set,
	want_integers: plural.Category_Set,
	samples: []Sample,
	loc := #caller_location,
) {
	_, matched := plural.match_locale(locale)
	testing.expectf(t, matched, "%s: no rules", locale, loc = loc)
	testing.expect_value(t, plural.categories(locale), want_set, loc = loc)
	testing.expect_value(t, plural.integer_categories(locale), want_integers, loc = loc)

	seen: plural.Category_Set
	for s in samples {
		seen += {s.category}
		got, err := plural.cardinal(locale, s.value)
		testing.expectf(t, err == .None, "%s %q: parse error %v", locale, s.value, err, loc = loc)
		testing.expectf(t, got == s.category, "%s cardinal %q: got %v, want %v", locale, s.value, got, s.category, loc = loc)

		if n, is_int := plain_int(s.value); is_int {
			got = plural.cardinal(locale, n)
			testing.expectf(t, got == s.category, "%s cardinal int %d: got %v, want %v", locale, n, got, s.category, loc = loc)
			got = plural.cardinal(locale, f64(n))
			testing.expectf(t, got == s.category, "%s cardinal f64 %d: got %v, want %v", locale, n, got, s.category, loc = loc)
			testing.expectf(t, s.category in want_integers, "%s: %d selects %v outside integer_categories", locale, n, s.category, loc = loc)
			slot := plural.i18n_slot(locale, n)
			want_slot := rank(s.category, want_integers)
			testing.expectf(t, slot == want_slot, "%s slot %d: got %d, want %d", locale, n, slot, want_slot, loc = loc)
		} else if f, is_float := plain_float(s.value); is_float {
			got = plural.cardinal(locale, f)
			testing.expectf(t, got == s.category, "%s cardinal f64 %v: got %v, want %v", locale, f, got, s.category, loc = loc)
		}
	}
	testing.expectf(t, seen == want_set, "%s: samples cover %v, categories are %v", locale, seen, want_set, loc = loc)
}

// expect_ordinal_samples checks a locale's ordinal rules against CLDR samples.
expect_ordinal_samples :: proc(
	t: ^testing.T,
	locale: string,
	want_set: plural.Category_Set,
	samples: []Sample,
	loc := #caller_location,
) {
	testing.expect_value(t, plural.ordinal_categories(locale), want_set, loc = loc)

	seen: plural.Category_Set
	for s in samples {
		seen += {s.category}
		got, err := plural.ordinal(locale, s.value)
		testing.expectf(t, err == .None, "%s %q: parse error %v", locale, s.value, err, loc = loc)
		testing.expectf(t, got == s.category, "%s ordinal %q: got %v, want %v", locale, s.value, got, s.category, loc = loc)
		if n, is_int := plain_int(s.value); is_int {
			got = plural.ordinal(locale, n)
			testing.expectf(t, got == s.category, "%s ordinal int %d: got %v, want %v", locale, n, got, s.category, loc = loc)
		}
	}
	testing.expectf(t, seen == want_set, "%s: samples cover %v, categories are %v", locale, seen, want_set, loc = loc)
}

// plain_int parses a sample that is a bare run of digits, such as "21".
plain_int :: proc(s: string) -> (n: int, ok: bool) {
	if len(s) == 0 || len(s) > 18 {
		return 0, false
	}
	for c in transmute([]u8)s {
		if c < '0' || c > '9' {
			return 0, false
		}
	}
	return strconv.parse_int(s)
}

// plain_float parses a decimal sample that an f64 can represent without losing
// visible digits: no exponent and no trailing zeros, such as "0.5".
plain_float :: proc(s: string) -> (f: f64, ok: bool) {
	dot := false
	for c in transmute([]u8)s {
		switch c {
		case '0' ..= '9':
		case '.':
			dot = true
		case:
			return 0, false
		}
	}
	if !dot || s[len(s) - 1] == '0' {
		return 0, false
	}
	return strconv.parse_f64(s)
}

// rank returns how many members of set come before c in Category order.
rank :: proc(c: plural.Category, set: plural.Category_Set) -> int {
	r := 0
	for member in set {
		if member < c {
			r += 1
		}
	}
	return r
}
