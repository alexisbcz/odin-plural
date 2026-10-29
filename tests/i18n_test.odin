package plural_tests

import plural ".."
import "core:mem"
import "core:testing"
import "core:text/i18n"

// with_tracking runs body with a tracking allocator and fails the test on any leak or bad free.
with_tracking :: proc(t: ^testing.T, body: proc(t: ^testing.T, allocator: mem.Allocator), loc := #caller_location) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	body(t, mem.tracking_allocator(&track))

	testing.expectf(t, len(track.allocation_map) == 0, "%d allocations leaked", len(track.allocation_map), loc = loc)
	testing.expectf(t, len(track.bad_free_array) == 0, "%d bad frees", len(track.bad_free_array), loc = loc)
}

@(test)
test_i18n_russian_catalog :: proc(t: ^testing.T) {
	with_tracking(t, proc(t: ^testing.T, allocator: mem.Allocator) {
		catalog, err := i18n.parse_mo(MO_RU[:], pluralizer = plural.i18n_pluralizer("ru"), allocator = allocator)
		testing.expect_value(t, err, i18n.Error.None)
		defer i18n.destroy(catalog, allocator)

		cases := [?]struct {
			n:    int,
			want: string,
		}{{1, "файл"}, {2, "файла"}, {4, "файла"}, {5, "файлов"}, {11, "файлов"}, {21, "файл"}, {22, "файла"}, {0, "файлов"}, {111, "файлов"}}
		for c in cases {
			got := i18n.get_n("file", c.n, catalog)
			testing.expectf(t, got == c.want, "ru %d: got %q, want %q", c.n, got, c.want)
		}
		testing.expect_value(t, i18n.get("Hello", catalog), "Привет")
	})
}

@(test)
test_i18n_polish_catalog :: proc(t: ^testing.T) {
	with_tracking(t, proc(t: ^testing.T, allocator: mem.Allocator) {
		catalog, err := i18n.parse_mo(MO_PL[:], pluralizer = plural.i18n_pluralizer("pl_PL.UTF-8"), allocator = allocator)
		testing.expect_value(t, err, i18n.Error.None)
		defer i18n.destroy(catalog, allocator)

		cases := [?]struct {
			n:    int,
			want: string,
		}{{1, "plik"}, {2, "pliki"}, {5, "plików"}, {12, "plików"}, {22, "pliki"}, {25, "plików"}}
		for c in cases {
			got := i18n.get_n("file", c.n, catalog)
			testing.expectf(t, got == c.want, "pl %d: got %q, want %q", c.n, got, c.want)
		}
	})
}

@(test)
test_i18n_arabic_catalog_uses_six_forms :: proc(t: ^testing.T) {
	with_tracking(t, proc(t: ^testing.T, allocator: mem.Allocator) {
		catalog, err := i18n.parse_mo(MO_AR[:], pluralizer = plural.i18n_pluralizer("ar-EG"), allocator = allocator)
		testing.expect_value(t, err, i18n.Error.None)
		defer i18n.destroy(catalog, allocator)

		cases := [?]struct {
			n:    int,
			want: string,
		}{{0, "لا ملفات"}, {1, "ملف واحد"}, {2, "ملفان"}, {3, "ملفات"}, {11, "ملفًا"}, {100, "ملف"}}
		for c in cases {
			got := i18n.get_n("file", c.n, catalog)
			testing.expectf(t, got == c.want, "ar %d: got %q, want %q", c.n, got, c.want)
		}
	})
}

@(test)
test_i18n_french_two_form_catalog_clamps_many :: proc(t: ^testing.T) {
	// fr has three integer categories (one, many, other) but most .po files
	// have two forms. Many and Other both land on the plural form.
	with_tracking(t, proc(t: ^testing.T, allocator: mem.Allocator) {
		catalog, err := i18n.parse_mo(MO_FR[:], pluralizer = plural.i18n_pluralizer("fr"), allocator = allocator)
		testing.expect_value(t, err, i18n.Error.None)
		defer i18n.destroy(catalog, allocator)

		testing.expect_value(t, i18n.get_n("file", 0, catalog), "fichier")
		testing.expect_value(t, i18n.get_n("file", 1, catalog), "fichier")
		testing.expect_value(t, i18n.get_n("file", 2, catalog), "fichiers")
		testing.expect_value(t, i18n.get_n("file", 1_000_000, catalog), "fichiers")
	})
}

@(test)
test_i18n_default_pluralizer_is_wrong_for_russian :: proc(t: ^testing.T) {
	// Without a pluralizer, core:text/i18n uses n != 1 and picks the
	// genitive singular for 5. This is the bug that i18n_pluralizer fixes.
	with_tracking(t, proc(t: ^testing.T, allocator: mem.Allocator) {
		catalog, err := i18n.parse_mo(MO_RU[:], allocator = allocator)
		testing.expect_value(t, err, i18n.Error.None)
		defer i18n.destroy(catalog, allocator)
		testing.expect_value(t, i18n.get_n("file", 5, catalog), "файла")

		catalog.pluralize = plural.i18n_pluralizer("ru")
		testing.expect_value(t, i18n.get_n("file", 5, catalog), "файлов")
	})
}

@(test)
test_i18n_unknown_locale_uses_first_form :: proc(t: ^testing.T) {
	with_tracking(t, proc(t: ^testing.T, allocator: mem.Allocator) {
		catalog, err := i18n.parse_mo(MO_RU[:], pluralizer = plural.i18n_pluralizer("xx"), allocator = allocator)
		testing.expect_value(t, err, i18n.Error.None)
		defer i18n.destroy(catalog, allocator)
		for n in ([]int{0, 1, 2, 5}) {
			testing.expect_value(t, i18n.get_n("file", n, catalog), "файл")
		}
	})
}

@(test)
test_i18n_truncated_catalog_reports_error :: proc(t: ^testing.T) {
	with_tracking(t, proc(t: ^testing.T, allocator: mem.Allocator) {
		catalog, err := i18n.parse_mo(MO_RU[:40], pluralizer = plural.i18n_pluralizer("ru"), allocator = allocator)
		testing.expect(t, err != .None, "a truncated .mo file must not parse")
		i18n.destroy(catalog, allocator)
	})
}
