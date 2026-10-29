package plural

import "core:math"
import "core:strconv"

/*
Operands holds the CLDR plural operands of one number, as defined in
Unicode Technical Standard #35, part 3, "Plural Operand Meanings".

For the source string "-1.50c3" (that is, 1.50 times 10 to the 3rd):

- n: 1500, the absolute value.
- i: 1500, the integer digits.
- v: 0, the number of visible fraction digits, with trailing zeros.
- w: 0, the number of visible fraction digits, without trailing zeros.
- f: 0, the visible fraction digits as an integer, with trailing zeros.
- t: 0, the visible fraction digits as an integer, without trailing zeros.
- e: 3, the compact decimal exponent (CLDR also calls it c).

For "1.50": n = 1.5, i = 1, v = 2, w = 1, f = 50, t = 5, e = 0.

The rules never read `n` because it is a float. They use `i` and `t`
instead, which is exact. `n` is there for callers that want it.

When the integer part has more than 18 digits, `i` keeps its last 18 digits
plus 10^18, so `i % m` stays exact for every modulus up to 10^18 and `i`
still compares as larger than any smaller integer. `f` and `t` follow the
same scheme. CLDR rules never need more than that.
*/
Operands :: struct {
	n: f64,
	i: u64,
	v: int,
	w: int,
	f: u64,
	t: u64,
	e: int,
}

// Parse_Error lists the ways a number string can fail to parse into Operands.
Parse_Error :: enum u8 {
	None,
	// The string was empty, or held only a sign.
	Empty,
	// The string held a byte that is not a digit, sign, decimal point or exponent marker.
	Invalid_Character,
	// A decimal point or exponent marker had no digits after it, or the number had no digits before its decimal point.
	Missing_Digits,
	// The exponent was negative. CLDR compact exponents are never negative.
	Negative_Exponent,
	// The exponent was larger than MAX_EXPONENT.
	Exponent_Too_Large,
	// The f64 value was NaN or infinite.
	Not_Finite,
}

// MAX_EXPONENT is the largest compact exponent that operands_from_string accepts.
MAX_EXPONENT :: 1000

// operands builds Operands from a string, an int or an f64. See operands_from_string.
operands :: proc {
	operands_from_string,
	operands_from_int,
	operands_from_f64,
}

@(private)
BIG :: u64(1_000_000_000_000_000_000)

// Digit_Accumulator turns a stream of decimal digits into a u64 using the scheme described on Operands.
@(private)
Digit_Accumulator :: struct {
	value: u64,
	big:   bool,
}

@(private)
accumulate :: #force_inline proc "contextless" (acc: ^Digit_Accumulator, digit: u8) {
	acc.value = acc.value * 10 + u64(digit)
	if acc.value >= BIG {
		acc.big = true
		acc.value %= BIG
	}
}

@(private)
accumulated :: #force_inline proc "contextless" (acc: Digit_Accumulator) -> u64 {
	return acc.value + BIG if acc.big else acc.value
}

/*
operands_from_string parses a decimal number string into CLDR plural operands.

The accepted syntax follows the CLDR sample notation:

	["-" | "+"] digits ["." digits] [("c" | "e" | "C" | "E") ["+"] digits]

Visible trailing zeros count, so "1" and "1.0" produce different `v` values,
and some locales put them in different categories. The exponent shifts the
decimal point to the right: "1.2c3" is 1200 with `e` = 3.

The procedure never allocates.

Inputs:
- s: the number, for example "1", "1.50", "-3" or "1.1c6".

Returns:
- result: the operands of the number; zero when `err` is not `.None`.
- err: `.Empty`, `.Invalid_Character`, `.Missing_Digits`, `.Negative_Exponent` or `.Exponent_Too_Large`.
*/
operands_from_string :: proc(s: string) -> (result: Operands, err: Parse_Error) {
	rest := s
	if len(rest) > 0 && (rest[0] == '-' || rest[0] == '+') {
		rest = rest[1:]
	}
	if len(rest) == 0 {
		return {}, .Empty
	}

	// Split into integer digits, fraction digits and exponent digits.
	int_end := 0
	for int_end < len(rest) && is_digit(rest[int_end]) {
		int_end += 1
	}
	int_digits := rest[:int_end]
	mantissa := rest
	rest = rest[int_end:]

	frac_digits: string
	if len(rest) > 0 && rest[0] == '.' {
		rest = rest[1:]
		frac_end := 0
		for frac_end < len(rest) && is_digit(rest[frac_end]) {
			frac_end += 1
		}
		frac_digits = rest[:frac_end]
		rest = rest[frac_end:]
		if len(frac_digits) == 0 {
			return {}, .Missing_Digits
		}
	}
	if len(int_digits) == 0 {
		if len(rest) > 0 && !is_exponent_marker(rest[0]) && rest[0] != '.' {
			return {}, .Invalid_Character
		}
		return {}, .Missing_Digits
	}

	mantissa = mantissa[:len(mantissa) - len(rest)]

	exponent := 0
	if len(rest) > 0 && is_exponent_marker(rest[0]) {
		rest = rest[1:]
		if len(rest) > 0 && rest[0] == '-' {
			return {}, .Negative_Exponent
		}
		if len(rest) > 0 && rest[0] == '+' {
			rest = rest[1:]
		}
		if len(rest) == 0 {
			return {}, .Missing_Digits
		}
		for len(rest) > 0 && is_digit(rest[0]) {
			exponent = exponent * 10 + int(rest[0] - '0')
			if exponent > MAX_EXPONENT {
				return {}, .Exponent_Too_Large
			}
			rest = rest[1:]
		}
	}
	if len(rest) != 0 {
		return {}, .Invalid_Character
	}

	// Moving the decimal point `exponent` places to the right turns the
	// first `shift` fraction digits into integer digits.
	shift := min(exponent, len(frac_digits))
	i_acc: Digit_Accumulator
	for c in transmute([]u8)int_digits {
		accumulate(&i_acc, c - '0')
	}
	for c in transmute([]u8)frac_digits[:shift] {
		accumulate(&i_acc, c - '0')
	}
	for _ in 0 ..< exponent - shift {
		accumulate(&i_acc, 0)
	}

	fraction := frac_digits[shift:]
	trimmed := fraction
	for len(trimmed) > 0 && trimmed[len(trimmed) - 1] == '0' {
		trimmed = trimmed[:len(trimmed) - 1]
	}
	f_acc, t_acc: Digit_Accumulator
	for c in transmute([]u8)fraction {
		accumulate(&f_acc, c - '0')
	}
	for c in transmute([]u8)trimmed {
		accumulate(&t_acc, c - '0')
	}

	result = Operands {
		n = decimal_value(mantissa, exponent),
		i = accumulated(i_acc),
		v = len(fraction),
		w = len(trimmed),
		f = accumulated(f_acc),
		t = accumulated(t_acc),
		e = exponent,
	}
	return result, .None
}

/*
operands_from_int returns the operands of an integer. Negative values use
their absolute value, as CLDR requires. Only `n` and `i` are non-zero.
*/
operands_from_int :: proc "contextless" (value: int) -> Operands {
	magnitude := u64(value) if value >= 0 else u64(-(value + 1)) + 1
	i := magnitude
	if i >= BIG {
		i = i % BIG + BIG
	}
	return {n = f64(magnitude), i = i}
}

/*
operands_from_f64 returns the operands of a float, using the shortest decimal
string that round-trips to `value`. A float has no visible trailing zeros, so
1.0 gives the same operands as 1. Format the number yourself and call
operands_from_string when trailing zeros matter, for example after rounding a
price to two decimals.

Returns:
- result: the operands; zero when `err` is not `.None`.
- err: `.Not_Finite` for NaN and infinities.
*/
operands_from_f64 :: proc(value: f64) -> (result: Operands, err: Parse_Error) {
	if math.is_nan(value) || math.is_inf(value) {
		return {}, .Not_Finite
	}
	// The longest shortest-form f64 in 'f' notation is under 330 bytes.
	buf: [512]u8
	s := strconv.write_float(buf[:], value, 'f', -1, 64)
	return operands_from_string(s)
}

@(private)
is_digit :: #force_inline proc "contextless" (c: u8) -> bool {
	return c >= '0' && c <= '9'
}

@(private)
is_exponent_marker :: #force_inline proc "contextless" (c: u8) -> bool {
	return c == 'c' || c == 'e' || c == 'C' || c == 'E'
}

// decimal_value computes n from the digits before the exponent. Precision doesn't matter, because the rules never read n.
@(private)
decimal_value :: proc(mantissa: string, exponent: int) -> f64 {
	value, _ := strconv.parse_f64(mantissa)
	if exponent > 0 {
		value *= math.pow10(f64(exponent))
	}
	return value
}

// slot_of returns the position of `category` among `set`, in Category order. It is the i18n plural slot.
@(private)
slot_of :: #force_inline proc "contextless" (category: Category, set: Category_Set) -> int {
	slot := 0
	for c in set {
		if c >= category {
			break
		}
		slot += 1
	}
	return slot
}

// between reports whether lo <= x <= hi.
@(private)
between :: #force_inline proc "contextless" (x, lo, hi: $T) -> bool {
	return x >= lo && x <= hi
}
