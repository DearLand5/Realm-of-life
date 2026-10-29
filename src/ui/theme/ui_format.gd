class_name UIFormat
extends RefCounted
## Locale-aware text formatting for the Russian UI: decimal comma, grouped
## thousands, plural forms, local date/time.

const DECIMAL := ","
const GROUP := "\u00a0"  # no-break space


## 1234.5 → "1 234,5". decimals < 0 → trims trailing zeros (max 3).
static func number(v: float, decimals: int = -1) -> String:
	if is_nan(v) or is_inf(v):
		return "—"
	var d := decimals if decimals >= 0 else 3
	var s := String.num(absf(v), d)
	if decimals < 0 and s.contains("."):
		s = s.rstrip("0").rstrip(".")
	elif decimals > 0 and not s.contains("."):
		s += "." + "0".repeat(decimals)
	elif decimals > 0:
		var have := s.length() - s.find(".") - 1
		if have < decimals:
			s += "0".repeat(decimals - have)
	var parts := s.split(".")
	var out := _group(parts[0])
	if parts.size() > 1 and parts[1] != "":
		out += DECIMAL + parts[1]
	if v < 0.0 and out.strip_edges() != "0":
		out = "−" + out
	return out


static func integer(n: int) -> String:
	return ("−" if n < 0 else "") + _group(str(absi(n)))


static func _group(digits: String) -> String:
	if digits.length() <= 4:
		return digits
	var out := ""
	var cnt := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			out = GROUP + out
	return out


## Parses user input: accepts "," or "." decimals, spaces, unicode minus. Returns null if invalid.
static func parse(text: String) -> Variant:
	var s := text.strip_edges().replace(" ", "").replace(GROUP, "").replace("\u202f", "").replace(",", ".").replace("−", "-")
	if s == "" or not s.is_valid_float():
		return null
	return s.to_float()


## Number of decimals needed to show values snapped to `step`.
static func decimals_for_step(step: float) -> int:
	if step <= 0.0:
		return 2
	var d := 0
	var x := step
	while d < 4 and absf(x - roundf(x)) > 0.0001:
		x *= 10.0
		d += 1
	return d


## Russian plural: plural(5, "вид", "вида", "видов") → "видов".
static func plural(n: int, one: String, few: String, many: String) -> String:
	var a := absi(n) % 100
	var b := a % 10
	if a >= 11 and a <= 14:
		return many
	if b == 1:
		return one
	if b >= 2 and b <= 4:
		return few
	return many


## "5 видов"
static func count(n: int, one: String, few: String, many: String) -> String:
	return "%s %s" % [integer(n), plural(n, one, few, many)]


## UTC ISO datetime ("2026-10-29T08:08:00") → local "29.10.2026, 11:08".
static func datetime(iso_utc: String) -> String:
	if iso_utc == "":
		return "—"
	var unix := Time.get_unix_time_from_datetime_string(iso_utc)
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	var d := Time.get_datetime_dict_from_unix_time(unix + bias * 60)
	return "%02d.%02d.%04d, %02d:%02d" % [d["day"], d["month"], d["year"], d["hour"], d["minute"]]
