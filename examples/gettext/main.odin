// Example gettext loads a Russian .mo catalog with CLDR plural rules. Run it with `odin run examples/gettext`.
package main

import plural "../.."
import "core:fmt"
import "core:os"
import "core:text/i18n"

// The catalog translates msgid "file" / msgid_plural "files" into its three Russian forms.
CATALOG :: #load("ru.mo")

main :: proc() {
	catalog, err := i18n.parse_mo(CATALOG, pluralizer = plural.i18n_pluralizer("ru_RU.UTF-8"))
	if err != .None {
		fmt.eprintln("cannot load catalog:", err)
		os.exit(1)
	}
	defer i18n.destroy(catalog)

	for n in ([]int{1, 2, 5, 11, 21, 102}) {
		fmt.println(n, i18n.get_n("file", n, catalog))
	}
}
