extends RefCounted
## Scripted inputs for measurements and clips: (throttle, turn) at time t. Throttle 0.3 is a walk, 0.6 a trot and
## 1.0 a run on every body, because the table is in Froude units (Fr = 3 * throttle^2 at full table range).

const NAMES: Array[String] = ["demo", "walk", "trot", "run", "turn_in_place", "reversal", "random"]


static func input(program: String, t: float, seed_value := 1) -> Vector2:
	match program:
		"demo":
			if t < 2.5:
				return Vector2(0.3, 0.0)
			if t < 5.0:
				return Vector2(0.6, 0.0)
			if t < 7.0:
				return Vector2(1.0, 0.0)
			if t < 8.5:
				return Vector2(0.6, 0.7)
			return Vector2.ZERO
		"walk":
			return Vector2(0.3, 0.0)
		"trot":
			return Vector2(0.6, 0.0)
		"run":
			return Vector2(1.0, 0.0)
		"turn_in_place":
			return Vector2(0.0, 1.0)
		"reversal":
			return Vector2(0.6, 0.0) if t < 3.0 else Vector2(0.6, 1.0)
		"random":
			# A new random input every half second, the same for the same seed.
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([seed_value, int(floor(t * 2.0))])
			var throttle := rng.randf_range(-0.4, 1.0)
			var turn := rng.randf_range(-1.0, 1.0) if rng.randf() < 0.6 else 0.0
			return Vector2(throttle, turn)
	return Vector2.ZERO
