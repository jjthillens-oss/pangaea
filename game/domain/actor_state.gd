class_name ActorState
extends RefCounted
## Current condition of one organism: health and energy (Bible section 12, "actor state").
## Separate from the genome (what it is) and the phenotype (what it can do).
##
## Energy drains with upkeep and movement; eating refills it. At zero energy the organism
## starves: it moves at STARVING_SPEED and loses health, so finding food is always a way back.

const STARVING_SPEED := 0.5           ## speed multiplier while energy is zero
const STARVATION_DAMAGE := 1.5        ## health per second while energy is zero
const REGEN_THRESHOLD := 0.5          ## health regenerates only above half energy
const REGEN_RATE := 0.02              ## share of max health per second

var health: float = 0.0
var energy: float = 0.0
var max_health: float = 0.0
var energy_capacity: float = 0.0


static func fresh(p: Phenotype) -> ActorState:
	var s := ActorState.new()
	s.max_health = p.max_health
	s.energy_capacity = p.energy_capacity
	s.health = p.max_health
	s.energy = p.energy_capacity * 0.6
	return s


func is_alive() -> bool:
	return health > 0.0


func is_starving() -> bool:
	return energy <= 0.0


func speed_multiplier() -> float:
	return STARVING_SPEED if is_starving() else 1.0


## Advance metabolism by dt seconds, having moved distance_m meters.
func tick(p: Phenotype, dt: float, distance_m: float) -> void:
	if not is_alive():
		return
	energy -= p.upkeep * dt + p.move_cost * distance_m
	if energy <= 0.0:
		energy = 0.0
		health = maxf(0.0, health - STARVATION_DAMAGE * dt)
	elif energy >= energy_capacity * REGEN_THRESHOLD:
		health = minf(max_health, health + max_health * REGEN_RATE * dt)


## Returns the energy actually absorbed (a full stomach wastes the rest).
func eat(amount: float) -> float:
	var absorbed := minf(amount, energy_capacity - energy)
	energy += absorbed
	return absorbed


## Returns the damage actually taken after defense.
func take_damage(amount: float, defense: float) -> float:
	var dealt := amount * (1.0 - clampf(defense, 0.0, 0.95))
	health = maxf(0.0, health - dealt)
	return dealt
