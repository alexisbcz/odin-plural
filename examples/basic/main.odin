// Example basic picks plural forms and English ordinal suffixes. Run it with `odin run examples/basic`.
package main

import plural "../.."
import "core:fmt"

// Forms holds one message in every plural category; unused categories stay empty.
Forms :: [plural.Category]string

main :: proc() {
	files_ru := #partial Forms {
		.One   = "файл",
		.Few   = "файла",
		.Many  = "файлов",
		.Other = "файла",
	}
	files_en := #partial Forms {
		.One   = "file",
		.Other = "files",
	}
	suffix_en := #partial Forms {
		.One   = "st",
		.Two   = "nd",
		.Few   = "rd",
		.Other = "th",
	}

	for n in ([]int{1, 2, 5, 21, 22, 25, 111}) {
		fmt.printf("%d %s / %d %s\n", n, files_ru[plural.cardinal("ru", n)], n, files_en[plural.cardinal("en", n)])
	}

	// A string keeps its visible trailing zeros: "1.0" is plural in English.
	for s in ([]string{"1", "1.0", "2.5"}) {
		c, err := plural.cardinal("en", s)
		if err != .None {
			fmt.eprintln("bad number:", s, err)
			continue
		}
		fmt.println(s, files_en[c])
	}

	for n in ([]int{1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 101}) {
		fmt.printf("%d%s ", n, suffix_en[plural.ordinal("en", n)])
	}
	fmt.println()

	fmt.println("Arabic uses:", plural.categories("ar"))
	name, ok := plural.match_locale("pt_BR.UTF-8")
	fmt.println("pt_BR.UTF-8 uses the rules of:", name, ok)
}
