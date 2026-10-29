package plural_tests

import plural ".."
import "core:math"
import "core:testing"

BIG :: u64(1_000_000_000_000_000_000)

expect_operands :: proc(t: ^testing.T, s: string, want: plural.Operands, loc := #caller_location) {
	got, err := plural.operands(s)
	testing.expect_value(t, err, plural.Parse_Error.None, loc = loc)
	testing.expect_value(t, got.i, want.i, loc = loc)
	testing.expect_value(t, got.v, want.v, loc = loc)
	testing.expect_value(t, got.w, want.w, loc = loc)
	testing.expect_value(t, got.f, want.f, loc = loc)
	testing.expect_value(t, got.t, want.t, loc = loc)
	testing.expect_value(t, got.e, want.e, loc = loc)
}

expect_parse_error :: proc(t: ^testing.T, s: string, want: plural.Parse_Error, loc := #caller_location) {
	got, err := plural.operands(s)
	testing.expectf(t, err == want, "%q: got error %v, want %v", s, err, want, loc = loc)
	testing.expectf(t, got == {}, "%q: operands not zeroed on error: %v", s, got, loc = loc)
}

@(test)
test_operands_integer :: proc(t: ^testing.T) {
	expect_operands(t, "5", {i = 5})
	expect_operands(t, "0", {})
	expect_operands(t, "1000", {i = 1000})
}

@(test)
test_operands_keep_visible_trailing_zeros :: proc(t: ^testing.T) {
	expect_operands(t, "1.50", {i = 1, v = 2, w = 1, f = 50, t = 5})
	expect_operands(t, "1.0", {i = 1, v = 1, w = 0, f = 0, t = 0})
	expect_operands(t, "0.000", {i = 0, v = 3})
	expect_operands(t, "1.03", {i = 1, v = 2, w = 2, f = 3, t = 3})
}

@(test)
test_operands_one_and_one_point_zero_differ :: proc(t: ^testing.T) {
	a, _ := plural.operands("1")
	b, _ := plural.operands("1.0")
	testing.expect_value(t, a.n, b.n)
	testing.expect_value(t, a.i, b.i)
	testing.expect(t, a.v != b.v, "v must count the visible zero")
}

@(test)
test_operands_compact_exponent :: proc(t: ^testing.T) {
	expect_operands(t, "1c6", {i = 1_000_000, e = 6})
	expect_operands(t, "1.2c3", {i = 1200, e = 3})
	expect_operands(t, "1.23456c3", {i = 1234, v = 2, w = 2, f = 56, t = 56, e = 3})
	expect_operands(t, "1.0000001c6", {i = 1_000_000, v = 1, w = 1, f = 1, t = 1, e = 6})
	expect_operands(t, "1.50c1", {i = 15, v = 1, w = 0, f = 0, t = 0, e = 1})
}

@(test)
test_operands_exponent_markers :: proc(t: ^testing.T) {
	expect_operands(t, "1e3", {i = 1000, e = 3})
	expect_operands(t, "1E3", {i = 1000, e = 3})
	expect_operands(t, "1C3", {i = 1000, e = 3})
	expect_operands(t, "1e+3", {i = 1000, e = 3})
	expect_operands(t, "1c0", {i = 1})
}

@(test)
test_operands_sign_uses_absolute_value :: proc(t: ^testing.T) {
	expect_operands(t, "-1.5", {i = 1, v = 1, w = 1, f = 5, t = 5})
	expect_operands(t, "+21", {i = 21})
	o, _ := plural.operands("-2.25")
	testing.expect_value(t, o.n, 2.25)
}

@(test)
test_operands_n_value :: proc(t: ^testing.T) {
	o, _ := plural.operands("1.50")
	testing.expect_value(t, o.n, 1.5)
	o, _ = plural.operands("1.2c3")
	testing.expect_value(t, o.n, 1200)
}

@(test)
test_operands_huge_integer_keeps_low_digits :: proc(t: ^testing.T) {
	o, err := plural.operands("123456789012345678901")
	testing.expect_value(t, err, plural.Parse_Error.None)
	testing.expect_value(t, o.i % 1000, 901)
	testing.expect(t, o.i >= BIG, "i must compare above every small integer")
	// v = 0, i % 10 = 1 and i % 100 != 11, so Russian picks One.
	testing.expect_value(t, plural.cardinal_operands("ru", o), plural.Category.One)
	testing.expect_value(t, plural.cardinal_operands("en", o), plural.Category.Other)
}

@(test)
test_operands_huge_exponent_shift :: proc(t: ^testing.T) {
	o, err := plural.operands("1c30")
	testing.expect_value(t, err, plural.Parse_Error.None)
	testing.expect_value(t, o.i, BIG)
	testing.expect_value(t, o.e, 30)
	testing.expect_value(t, plural.cardinal_operands("fr", o), plural.Category.Many)
}

@(test)
test_operands_long_fraction :: proc(t: ^testing.T) {
	expect_operands(t, "0.0000000000000000000001", {v = 22, w = 22, f = 1, t = 1})
	o, _ := plural.operands("0.1000000000000000000001")
	testing.expect(t, o.f >= BIG, "f has 22 significant digits")
	testing.expect_value(t, o.f % 10, 1)
}

@(test)
test_operands_from_int :: proc(t: ^testing.T) {
	o := plural.operands(42)
	testing.expect_value(t, o, plural.Operands{n = 42, i = 42})
	o = plural.operands(-7)
	testing.expect_value(t, o.i, 7)
}

@(test)
test_operands_from_int_min_does_not_overflow :: proc(t: ^testing.T) {
	o := plural.operands(min(int))
	// |min(int)| = 9223372036854775808.
	testing.expect_value(t, o.i % 100, 8)
	testing.expect(t, o.i >= BIG)
	testing.expect_value(t, plural.cardinal("ru", min(int)), plural.Category.Many)
	testing.expect_value(t, plural.cardinal("ru", max(int)), plural.Category.Many)
}

@(test)
test_operands_from_f64 :: proc(t: ^testing.T) {
	o, err := plural.operands(0.1)
	testing.expect_value(t, err, plural.Parse_Error.None)
	testing.expect_value(t, o.v, 1)
	testing.expect_value(t, o.f, 1)
	o, err = plural.operands(f64(1.0))
	testing.expect_value(t, err, plural.Parse_Error.None)
	testing.expect_value(t, o.v, 0)
	testing.expect_value(t, o.i, 1)
	o, err = plural.operands(f64(-2.5))
	testing.expect_value(t, o.i, 2)
	testing.expect_value(t, o.f, 5)
	o, err = plural.operands(f64(1e21))
	testing.expect_value(t, err, plural.Parse_Error.None)
	testing.expect_value(t, o.i, BIG)
}

@(test)
test_operands_from_f64_rejects_non_finite :: proc(t: ^testing.T) {
	_, err := plural.operands(math.nan_f64())
	testing.expect_value(t, err, plural.Parse_Error.Not_Finite)
	_, err = plural.operands(math.inf_f64(1))
	testing.expect_value(t, err, plural.Parse_Error.Not_Finite)
	_, err = plural.operands(math.inf_f64(-1))
	testing.expect_value(t, err, plural.Parse_Error.Not_Finite)
}

@(test)
test_operands_reject_empty :: proc(t: ^testing.T) {
	expect_parse_error(t, "", .Empty)
	expect_parse_error(t, "-", .Empty)
	expect_parse_error(t, "+", .Empty)
}

@(test)
test_operands_reject_invalid_characters :: proc(t: ^testing.T) {
	expect_parse_error(t, "abc", .Invalid_Character)
	expect_parse_error(t, " 1", .Invalid_Character)
	expect_parse_error(t, "1 ", .Invalid_Character)
	expect_parse_error(t, "1,5", .Invalid_Character)
	expect_parse_error(t, "1.5x", .Invalid_Character)
	expect_parse_error(t, "--1", .Invalid_Character)
	expect_parse_error(t, "1e3x", .Invalid_Character)
	expect_parse_error(t, "1.2.3", .Invalid_Character)
	expect_parse_error(t, "١", .Invalid_Character)
}

@(test)
test_operands_reject_missing_digits :: proc(t: ^testing.T) {
	expect_parse_error(t, "1.", .Missing_Digits)
	expect_parse_error(t, ".5", .Missing_Digits)
	expect_parse_error(t, "1e", .Missing_Digits)
	expect_parse_error(t, "1e+", .Missing_Digits)
	expect_parse_error(t, "1.e3", .Missing_Digits)
	expect_parse_error(t, "c3", .Missing_Digits)
}

@(test)
test_operands_reject_bad_exponents :: proc(t: ^testing.T) {
	expect_parse_error(t, "1e-3", .Negative_Exponent)
	expect_parse_error(t, "1c1001", .Exponent_Too_Large)
	expect_parse_error(t, "1c99999999999999999999", .Exponent_Too_Large)
	_, err := plural.operands("1c1000")
	testing.expect_value(t, err, plural.Parse_Error.None)
}
