package plural_tests

import plural ".."
import "core:math"
import "core:slice"
import "core:testing"

Category :: plural.Category

expect_cardinal :: proc(t: ^testing.T, locale, n: string, want: Category, loc := #caller_location) {
	got, err := plural.cardinal(locale, n)
	testing.expectf(t, err == .None, "%s %q: parse error %v", locale, n, err, loc = loc)
	testing.expectf(t, got == want, "%s cardinal %q: got %v, want %v", locale, n, got, want, loc = loc)
}

// Trailing zeros ------------------------------------------------------------

@(test)
test_english_one_point_zero_is_other :: proc(t: ^testing.T) {
	expect_cardinal(t, "en", "1", .One)
	expect_cardinal(t, "en", "1.0", .Other)
	expect_cardinal(t, "en", "1.00", .Other)
	testing.expect_value(t, plural.cardinal("en", f64(1.0)), Category.One)
}

@(test)
test_spanish_one_point_zero_is_one :: proc(t: ^testing.T) {
	// es uses n = 1, which ignores trailing zeros, unlike en's i = 1 and v = 0.
	expect_cardinal(t, "es", "1.0", .One)
	expect_cardinal(t, "es", "1.00", .One)
	expect_cardinal(t, "es", "1.5", .Other)
}

@(test)
test_russian_decimals_are_other :: proc(t: ^testing.T) {
	expect_cardinal(t, "ru", "1", .One)
	expect_cardinal(t, "ru", "1.0", .Other)
	expect_cardinal(t, "ru", "2.50", .Other)
	expect_cardinal(t, "ru", "5", .Many)
	expect_cardinal(t, "ru", "5.0", .Other)
}

@(test)
test_french_zero_to_two_exclusive_is_one :: proc(t: ^testing.T) {
	expect_cardinal(t, "fr", "0", .One)
	expect_cardinal(t, "fr", "1.99", .One)
	expect_cardinal(t, "fr", "2", .Other)
	expect_cardinal(t, "pt", "0.5", .One)
	expect_cardinal(t, "hi", "0.5", .One)
}

@(test)
test_lithuanian_fraction_digits :: proc(t: ^testing.T) {
	expect_cardinal(t, "lt", "1.0", .One)
	expect_cardinal(t, "lt", "0.1", .Many)
	expect_cardinal(t, "lt", "2.0", .Few)
	expect_cardinal(t, "lt", "11", .Other)
}

@(test)
test_latvian_visible_fraction_digits :: proc(t: ^testing.T) {
	expect_cardinal(t, "lv", "0", .Zero)
	expect_cardinal(t, "lv", "0.0", .Zero)
	expect_cardinal(t, "lv", "0.1", .One)
	expect_cardinal(t, "lv", "0.01", .One)
	expect_cardinal(t, "lv", "0.11", .Zero)
}

@(test)
test_compact_exponent_selects_many :: proc(t: ^testing.T) {
	expect_cardinal(t, "fr", "1c6", .Many)
	expect_cardinal(t, "fr", "1.1c6", .Many)
	expect_cardinal(t, "fr", "1c3", .Other)
	expect_cardinal(t, "es", "2c6", .Many)
	expect_cardinal(t, "it", "1c6", .Many)
	expect_cardinal(t, "en", "1c6", .Other)
}

@(test)
test_french_million_is_many :: proc(t: ^testing.T) {
	testing.expect_value(t, plural.cardinal("fr", 1_000_000), Category.Many)
	testing.expect_value(t, plural.cardinal("fr", 2_000_000), Category.Many)
	testing.expect_value(t, plural.cardinal("fr", 1_000_001), Category.Other)
	expect_cardinal(t, "fr", "1000000.0", .Other)
}

// Integer rules in languages that core:text/i18n gets wrong -------------------

@(test)
test_polish_integers :: proc(t: ^testing.T) {
	cases := [?]struct {
		n:    int,
		want: Category,
	}{{0, .Many}, {1, .One}, {2, .Few}, {4, .Few}, {5, .Many}, {12, .Many}, {22, .Few}, {25, .Many}, {102, .Few}, {112, .Many}}
	for c in cases {
		testing.expectf(t, plural.cardinal("pl", c.n) == c.want, "pl %d", c.n)
	}
	expect_cardinal(t, "pl", "1.5", .Other)
}

@(test)
test_arabic_uses_all_six_categories :: proc(t: ^testing.T) {
	cases := [?]struct {
		n:    int,
		want: Category,
	}{{0, .Zero}, {1, .One}, {2, .Two}, {3, .Few}, {10, .Few}, {11, .Many}, {99, .Many}, {100, .Other}, {102, .Other}, {103, .Few}}
	for c in cases {
		testing.expectf(t, plural.cardinal("ar", c.n) == c.want, "ar %d", c.n)
	}
	testing.expect_value(t, plural.categories("ar"), plural.Category_Set{.Zero, .One, .Two, .Few, .Many, .Other})
}

@(test)
test_welsh_cardinals :: proc(t: ^testing.T) {
	cases := [?]struct {
		n:    int,
		want: Category,
	}{{0, .Zero}, {1, .One}, {2, .Two}, {3, .Few}, {6, .Many}, {4, .Other}, {7, .Other}, {100, .Other}}
	for c in cases {
		testing.expectf(t, plural.cardinal("cy", c.n) == c.want, "cy %d", c.n)
	}
}

@(test)
test_negative_numbers_use_absolute_value :: proc(t: ^testing.T) {
	testing.expect_value(t, plural.cardinal("ru", -1), Category.One)
	testing.expect_value(t, plural.cardinal("ru", -3), Category.Few)
	testing.expect_value(t, plural.cardinal("en", f64(-1)), Category.One)
	expect_cardinal(t, "en", "-1", .One)
}

@(test)
test_languages_without_plurals :: proc(t: ^testing.T) {
	for locale in ([]string{"ja", "zh", "ko", "th", "id", "km", "my", "yue"}) {
		testing.expectf(t, plural.cardinal(locale, 1) == .Other, "%s 1", locale)
		testing.expectf(t, plural.categories(locale) == {.Other}, "%s set", locale)
	}
}

// Errors ----------------------------------------------------------------------

@(test)
test_cardinal_string_reports_parse_errors :: proc(t: ^testing.T) {
	c, err := plural.cardinal("en", "one")
	testing.expect_value(t, err, plural.Parse_Error.Invalid_Character)
	testing.expect_value(t, c, Category.Other)
	c, err = plural.cardinal("ru", "")
	testing.expect_value(t, err, plural.Parse_Error.Empty)
	testing.expect_value(t, c, Category.Other)
}

@(test)
test_ordinal_string_reports_parse_errors :: proc(t: ^testing.T) {
	c, err := plural.ordinal("en", "1st")
	testing.expect_value(t, err, plural.Parse_Error.Invalid_Character)
	testing.expect_value(t, c, Category.Other)
}

@(test)
test_non_finite_floats_are_other :: proc(t: ^testing.T) {
	testing.expect_value(t, plural.cardinal("ru", math.nan_f64()), Category.Other)
	testing.expect_value(t, plural.cardinal("en", math.inf_f64(1)), Category.Other)
	testing.expect_value(t, plural.ordinal("en", math.inf_f64(-1)), Category.Other)
}

// Ordinals --------------------------------------------------------------------

@(test)
test_english_ordinals_first_to_fourth :: proc(t: ^testing.T) {
	testing.expect_value(t, plural.ordinal("en", 1), Category.One) // 1st
	testing.expect_value(t, plural.ordinal("en", 2), Category.Two) // 2nd
	testing.expect_value(t, plural.ordinal("en", 3), Category.Few) // 3rd
	testing.expect_value(t, plural.ordinal("en", 4), Category.Other) // 4th
	testing.expect_value(t, plural.ordinal("en", 0), Category.Other) // 0th
}

@(test)
test_english_ordinals_teens_are_other :: proc(t: ^testing.T) {
	for n in 11 ..= 13 {
		testing.expectf(t, plural.ordinal("en", n) == .Other, "%dth", n)
		testing.expectf(t, plural.ordinal("en", 100 + n) == .Other, "%dth", 100 + n)
	}
}

@(test)
test_english_ordinals_after_twenty :: proc(t: ^testing.T) {
	testing.expect_value(t, plural.ordinal("en", 21), Category.One) // 21st
	testing.expect_value(t, plural.ordinal("en", 22), Category.Two) // 22nd
	testing.expect_value(t, plural.ordinal("en", 23), Category.Few) // 23rd
	testing.expect_value(t, plural.ordinal("en", 101), Category.One) // 101st
	testing.expect_value(t, plural.ordinal("en", 1002), Category.Two) // 1002nd
	testing.expect_value(t, plural.ordinal("en", -3), Category.Few)
	testing.expect_value(t, plural.ordinal("en", f64(43)), Category.Few)
	c, err := plural.ordinal("en", "52")
	testing.expect_value(t, err, plural.Parse_Error.None)
	testing.expect_value(t, c, Category.Two)
}

@(test)
test_english_ordinal_categories :: proc(t: ^testing.T) {
	testing.expect_value(t, plural.ordinal_categories("en"), plural.Category_Set{.One, .Two, .Few, .Other})
	testing.expect_value(t, plural.ordinal_categories("de"), plural.Category_Set{.Other})
}

@(test)
test_other_ordinal_rules :: proc(t: ^testing.T) {
	testing.expect_value(t, plural.ordinal("sv", 1), Category.One) // 1:a
	testing.expect_value(t, plural.ordinal("sv", 2), Category.One) // 2:a
	testing.expect_value(t, plural.ordinal("sv", 3), Category.Other) // 3:e
	testing.expect_value(t, plural.ordinal("sv", 12), Category.Other) // 12:e
	testing.expect_value(t, plural.ordinal("fr", 1), Category.One) // 1er
	testing.expect_value(t, plural.ordinal("fr", 2), Category.Other) // 2e
	testing.expect_value(t, plural.ordinal("it", 8), Category.Many) // l'8°
}

// Locale matching -------------------------------------------------------------

@(test)
test_region_falls_back_to_language :: proc(t: ^testing.T) {
	for tag in ([]string{"pt_BR", "pt-BR", "pt-br", "PT_BR"}) {
		name, ok := plural.match_locale(tag)
		testing.expectf(t, ok && name == "pt", "%s matched %q", tag, name)
	}
	testing.expect_value(t, plural.cardinal("pt_BR", 0), Category.One)
}

@(test)
test_portugal_has_its_own_rules :: proc(t: ^testing.T) {
	name, ok := plural.match_locale("pt_PT")
	testing.expect(t, ok)
	testing.expect_value(t, name, "pt-pt")
	// Brazilian Portuguese treats 0 like 1; European Portuguese does not.
	testing.expect_value(t, plural.cardinal("pt", 0), Category.One)
	testing.expect_value(t, plural.cardinal("pt-PT", 0), Category.Other)
	testing.expect_value(t, plural.ordinal("pt-PT", 1), Category.Other)
}

@(test)
test_matching_ignores_case :: proc(t: ^testing.T) {
	for tag in ([]string{"RU", "Ru", "ru-RU", "RU_ru"}) {
		name, ok := plural.match_locale(tag)
		testing.expectf(t, ok && name == "ru", "%s matched %q", tag, name)
	}
}

@(test)
test_posix_encoding_and_modifier_are_ignored :: proc(t: ^testing.T) {
	name, ok := plural.match_locale("ru_RU.UTF-8")
	testing.expect(t, ok)
	testing.expect_value(t, name, "ru")
	name, ok = plural.match_locale("ca_ES@valencia")
	testing.expect(t, ok)
	testing.expect_value(t, name, "ca")
	name, ok = plural.match_locale("pl.ISO-8859-2@euro")
	testing.expect(t, ok)
	testing.expect_value(t, name, "pl")
}

@(test)
test_script_and_region_subtags_fall_back :: proc(t: ^testing.T) {
	name, ok := plural.match_locale("zh-Hant-TW")
	testing.expect(t, ok)
	testing.expect_value(t, name, "zh")
	name, ok = plural.match_locale("sr-Latn-RS")
	testing.expect(t, ok)
	testing.expect_value(t, name, "sr")
	name, ok = plural.match_locale("en-")
	testing.expect(t, ok)
	testing.expect_value(t, name, "en")
}

@(test)
test_unknown_locale_falls_back_to_root :: proc(t: ^testing.T) {
	for tag in ([]string{"xx", "tlh-Latn", "", "C", "POSIX", "-", "_", "@", ".UTF-8", "root"}) {
		name, ok := plural.match_locale(tag)
		testing.expectf(t, !ok, "%q should not match", tag)
		testing.expect_value(t, name, plural.ROOT_LOCALE)
		testing.expect_value(t, plural.cardinal(tag, 1), Category.Other)
		testing.expect_value(t, plural.ordinal(tag, 1), Category.Other)
		testing.expect_value(t, plural.categories(tag), plural.Category_Set{.Other})
		testing.expect_value(t, plural.i18n_slot(tag, 1), 0)
	}
}

@(test)
test_prefix_of_a_locale_does_not_match :: proc(t: ^testing.T) {
	// "e" sorts next to "el" and "en" but must not match either.
	_, ok := plural.match_locale("e")
	testing.expect(t, !ok)
	_, ok = plural.match_locale("enx")
	testing.expect(t, !ok)
}

@(test)
test_legacy_language_codes :: proc(t: ^testing.T) {
	pairs := [?][2]string{{"iw", "he"}, {"in", "id"}, {"no", "nb"}, {"tl", "fil"}}
	for p in pairs {
		for n in 0 ..< 30 {
			testing.expectf(t, plural.cardinal(p[0], n) == plural.cardinal(p[1], n), "%s vs %s at %d", p[0], p[1], n)
		}
		testing.expect_value(t, plural.categories(p[0]), plural.categories(p[1]))
	}
}

@(test)
test_supported_locales_are_sorted_and_unique :: proc(t: ^testing.T) {
	names := plural.supported_locales()
	testing.expect(t, len(names) >= 70, "expected the common locales")
	testing.expect(t, slice.is_sorted(names), "names must be sorted for binary search")
	for i in 1 ..< len(names) {
		testing.expectf(t, names[i - 1] != names[i], "duplicate %s", names[i])
	}
	for name in names {
		got, _ := plural.match_locale(name)
		testing.expect_value(t, got, name)
	}
	testing.expect(t, slice.contains(names, "pt-pt"))
	testing.expect(t, slice.contains(names, plural.ROOT_LOCALE))
}

@(test)
test_cldr_version :: proc(t: ^testing.T) {
	testing.expect_value(t, plural.CLDR_VERSION, "49")
}

// Categories and i18n slots ---------------------------------------------------

@(test)
test_integer_categories :: proc(t: ^testing.T) {
	testing.expect_value(t, plural.integer_categories("ru"), plural.Category_Set{.One, .Few, .Many})
	testing.expect_value(t, plural.integer_categories("cs"), plural.Category_Set{.One, .Few, .Other})
	testing.expect_value(t, plural.integer_categories("fr"), plural.Category_Set{.One, .Many, .Other})
	testing.expect_value(t, plural.integer_categories("en"), plural.Category_Set{.One, .Other})
	testing.expect_value(t, plural.integer_categories("ja"), plural.Category_Set{.Other})
	for name in plural.supported_locales() {
		testing.expectf(t, plural.integer_categories(name) <= plural.categories(name), "%s", name)
		testing.expectf(t, .Other in plural.categories(name), "%s lacks Other", name)
	}
}

@(test)
test_i18n_slots_russian :: proc(t: ^testing.T) {
	pluralize := plural.i18n_pluralizer("ru")
	want := [?][2]int{{1, 0}, {2, 1}, {4, 1}, {5, 2}, {11, 2}, {21, 0}, {22, 1}, {0, 2}, {-1, 0}}
	for w in want {
		testing.expectf(t, pluralize(w[0]) == w[1], "ru %d: got %d, want %d", w[0], pluralize(w[0]), w[1])
	}
}

@(test)
test_i18n_slots_arabic :: proc(t: ^testing.T) {
	want := [?][2]int{{0, 0}, {1, 1}, {2, 2}, {3, 3}, {11, 4}, {100, 5}}
	for w in want {
		testing.expectf(t, plural.i18n_slot("ar", w[0]) == w[1], "ar %d", w[0])
	}
}

@(test)
test_i18n_slots_czech_skip_decimal_only_many :: proc(t: ^testing.T) {
	// cs uses Many only for decimals, so integers use slots 0, 1 and 2,
	// which is the order of a three-form Czech .po file.
	testing.expect_value(t, plural.i18n_slot("cs", 1), 0)
	testing.expect_value(t, plural.i18n_slot("cs", 3), 1)
	testing.expect_value(t, plural.i18n_slot("cs", 5), 2)
}

@(test)
test_i18n_slots_english :: proc(t: ^testing.T) {
	testing.expect_value(t, plural.i18n_slot("en", 1), 0)
	testing.expect_value(t, plural.i18n_slot("en", 0), 1)
	testing.expect_value(t, plural.i18n_slot("en", 2), 1)
}

@(test)
test_i18n_pluralizer_shared_by_fallbacks :: proc(t: ^testing.T) {
	testing.expect(t, plural.i18n_pluralizer("pt_BR") == plural.i18n_pluralizer("pt"))
	testing.expect(t, plural.i18n_pluralizer("uk") == plural.i18n_pluralizer("ru"))
	testing.expect(t, plural.i18n_pluralizer("xx") == plural.i18n_pluralizer("ja"))
	testing.expect(t, plural.i18n_pluralizer("pt-PT") != plural.i18n_pluralizer("pt"))
}

@(test)
test_cardinal_operands_reuses_parsed_value :: proc(t: ^testing.T) {
	o, err := plural.operands("21")
	testing.expect_value(t, err, plural.Parse_Error.None)
	testing.expect_value(t, plural.cardinal_operands("ru", o), Category.One)
	testing.expect_value(t, plural.cardinal_operands("en", o), Category.Other)
	testing.expect_value(t, plural.ordinal_operands("en", o), Category.One)
	testing.expect_value(t, plural.cardinal(locale = "pl", o = o), Category.Many)
}
