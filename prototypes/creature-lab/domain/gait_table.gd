extends RefCounted
## Dimensionless gait table (PROPOSED). Every speed is a Froude number Fr = v^2 / (g * h), with h the hip height,
## and every length is relative to the leg, so one table serves every leg length. Pure rules: no scene or file access.

var g_eff := 9.8
var stance_height_ratio := 0.8
var reach_margin := 0.97
var foot_splay_ratio := 0.1
var stride_coeff := 2.3
var stride_exp := 0.3
var min_rel_stride := 0.25
var swing_lift_ratio := 0.2
var max_swing_time := 0.5
var min_swing_time := 0.12
var band_hysteresis := 0.1
var phase_coupling := 1.0
var accel_cycles := 1.0
var settle_threshold_ratio := 0.15
var settle_idle_time := 0.25
## Each band: {name: String, fr_max: float, duty: float, pattern: "walk" | "trot"}, sorted by fr_max.
var bands: Array = []


static func from_dict(d: Dictionary) -> RefCounted:
	var t = load("res://domain/gait_table.gd").new()
	for key in ["g_eff", "stance_height_ratio", "reach_margin", "foot_splay_ratio", "stride_coeff", "stride_exp",
			"min_rel_stride", "swing_lift_ratio", "max_swing_time", "min_swing_time", "band_hysteresis",
			"phase_coupling", "accel_cycles", "settle_threshold_ratio", "settle_idle_time"]:
		if d.has(key):
			t.set(key, float(d[key]))
	for b in d.get("bands", []):
		t.bands.append({"name": String(b["name"]), "fr_max": float(b["fr_max"]), "duty": float(b["duty"]),
				"pattern": String(b["pattern"])})
	assert(not t.bands.is_empty(), "gait table needs at least one band")
	return t


## The fastest Froude number the table allows.
func fr_top() -> float:
	return bands[bands.size() - 1]["fr_max"]


## Stride length (body travel per cycle) over hip height, from the Froude number.
func rel_stride(fr: float) -> float:
	return maxf(min_rel_stride, stride_coeff * pow(maxf(fr, 0.0), stride_exp))


## Picks the band for `fr`. Shifts up as soon as fr passes the band's limit (so a band never runs past the speed its
## duty factor was checked for) and shifts down only once fr is below the lower band's limit by the hysteresis margin.
func pick_band(current: int, fr: float) -> int:
	var b := clampi(current, 0, bands.size() - 1)
	while b < bands.size() - 1 and fr > bands[b]["fr_max"]:
		b += 1
	while b > 0 and fr < bands[b - 1]["fr_max"] * (1.0 - band_hysteresis):
		b -= 1
	return b
