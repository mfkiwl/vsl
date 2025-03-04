module float32

import rand
import math

const (
	// Offset sets for testing alignment handling in Unitary assembly functions
	align1 = [0, 1]
	align2 = new_inc_set(0, 1)
	align3 = new_inc_to_set(0, 1)
)

struct IncSet {
	x int
	y int
}

// new_inc_set will generate all (x,y) combinations of the input increment set.
fn new_inc_set(inc ...int) []IncSet {
	n := inc.len
	mut inc_set := []IncSet{len: n * n}
	for i, x in inc {
		for j, y in inc {
			inc_set[i * n + j] = IncSet{x, y}
		}
	}
	return inc_set
}

struct IncToSet {
	dst int
	x   int
	y   int
}

// new_inc_to_set will generate all (dst,x,y) combinations of the input increment set.
fn new_inc_to_set(inc ...int) []IncToSet {
	n := inc.len
	mut inc_to_set := []IncToSet{len: n * n * n}
	for i, dst in inc {
		for j, x in inc {
			for k, y in inc {
				inc_to_set[i * n * n + j * n + k] = IncToSet{dst, x, y}
			}
		}
	}
	return inc_to_set
}

// same returns true when the inputs have the same value, allowing NaN equality.
fn same(a f32, b f32) bool {
	return a == b || (math.is_nan(f64(a)) && math.is_nan(f64(b)))
}

fn tolerance(a f32, b f32, tol f32) bool {
	mut e_ := tol
	// Multiplying by e_ here can underflow denormal values to zero.
	// Check a==b so that at least if a and b are small and identical
	// we say they match.
	if same(a, b) {
		return true
	}
	mut d := a - b
	if d < 0 {
		d = -d
	}
	// note: b is correct (expected) value, a is actual value.
	// make error tolerance a fraction of b, not a.
	if b != 0 {
		e_ = e_ * b
		if e_ < 0 {
			e_ = -e_
		}
	}
	return d < e_
}

pub fn arrays_tolerance(data1 []f32, data2 []f32, tol f32) bool {
	if data1.len != data2.len {
		return false
	}
	for i := 0; i < data1.len; i++ {
		if !tolerance(data1[i], data2[i], tol) {
			return false
		}
	}
	return true
}

// new_guarded_vector allocates a new slice and returns it as three subslices.
// v is a strided vector that contains elements of data at indices i*inc and
// nan elsewhere. frontGuard and backGuard are filled with nan values, and
// their backing arrays are directly adjacent to v in memory. The three slices
// can be used to detect invalid memory reads and writes.
fn new_guarded_vector(data []f32, inc int) ([]f32, []f32, []f32) {
	mut inc_ := inc
	if inc_ < 0 {
		inc_ = -inc_
	}
	guard := 2 * inc_
	size := (data.len - 1) * inc_ + 1
	mut whole := []f32{len: size + 2 * guard}
	mut v := whole[guard..whole.len - guard]
	for i, _ in whole {
		whole[i] = f32(math.nan())
	}
	for i, d in data {
		v[i * inc_] = d
	}
	return v, whole[..guard], whole[whole.len - guard..]
}

// all_nan returns true if x contains only nan values, and false otherwise.
fn all_nan(x []f32) bool {
	for _, v in x {
		if !math.is_nan(v) {
			return false
		}
	}
	return true
}

// equal_strided returns true if the strided vector x contains elements of the
// dense vector ref at indices i*inc, false otherwise.
fn equal_strided(ref []f32, x []f32, inc int) bool {
	mut inc_ := inc
	if inc_ < 0 {
		inc_ = -inc_
	}
	for i, v in ref {
		if !same(x[i * inc_], v) {
			return false
		}
	}
	return true
}

// non_strided_write returns false if all elements of x at non-stride indices are
// equal to nan, true otherwise.
fn non_strided_write(x []f32, inc int) bool {
	mut inc_ := inc
	if inc_ < 0 {
		inc_ = -inc_
	}
	for i, v in x {
		if i % inc_ != 0 && !math.is_nan(v) {
			return true
		}
	}
	return false
}

// guard_vector copies the source vector (vec) into a new slice with guards.
// Guards guarded[..gd_ln] and guarded[len-gd_ln..] will be filled with sigil value gd_val.
fn guard_vector(vec []f32, gd_val f32, gd_ln int) []f32 {
	mut guarded := []f32{len: vec.len + gd_ln * 2}
	for i in 0 .. vec.len {
		guarded[gd_ln + i] = vec[i]
	}
	for i in 0 .. gd_ln {
		guarded[i] = gd_val
		guarded[guarded.len - 1 - i] = gd_val
	}
	return guarded
}

// is_valid_guard will test for violated guards, generated by guard_vector.
fn is_valid_guard(vec []f32, gd_val f32, gd_ln int) bool {
	for i in 0 .. gd_ln {
		if !same(vec[i], gd_val) || !same(vec[vec.len - 1 - i], gd_val) {
			return false
		}
	}
	return true
}

// guard_inc_vector copies the source vector (vec) into a new incremented slice with guards.
// End guards will be length gd_len.
// Internal and end guards will be filled with sigil value gd_val.
fn guard_inc_vector(vec []f32, gd_val f32, inc int, gd_len int) []f32 {
	mut inc_ := inc
	if inc_ < 0 {
		inc_ = -inc_
	}
	inr_len := vec.len * inc_
	mut guarded := []f32{len: inr_len + gd_len * 2}
	for i, _ in guarded {
		guarded[i] = gd_val
	}
	for i, v in vec {
		guarded[gd_len + i * inc_] = v
	}
	return guarded
}

// is_valid_inc_guard will test for violated guards, generated by guard_inc_vector.
fn is_valid_inc_guard(vec []f32, gd_val f32, inc int, gd_ln int) bool {
	for i in 0 .. vec.len {
		if (i - gd_ln) % inc == 0 && (i - gd_ln) / inc < vec.len {
			continue
		}
		if !same(vec[i], gd_val) {
			return false
		}
	}
	return true
}

fn random_slice(n int, inc int) []f32 {
	inc_ := if inc < 0 { -inc } else { inc }
	mut x := []f32{len: (n - 1) * inc_ + 1}
	for i in 0 .. x.len {
		x[i] = rand.f32()
	}
	return x
}
