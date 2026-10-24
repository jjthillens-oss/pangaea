class_name IdeaHints
extends RefCounted
## Idea hints (S2, s2-view 7.5, D-43): one short idea at a time about growing and the sea, shown
## SHOW_S in the HUD's %IdeaHint. At most one new idea every NEW_IDEA_GAP_S; one not followed may
## come back REPEAT_S after it last showed, while its moment lasts; one followed never shows again,
## on this computer (the player memory's hints_followed, saved as each is added).
##
##   eat_to_grow    the first meal with the ring a tenth full at size 1; followed when it fills
##   sea_goes_on    two minutes in the home tile; followed on entering any other
##   smaller_now    2 s into a growth's beat and after, with a jaw; followed by coming near a
##                  smaller body, or hitting one
##   flee_now       the same without a jaw; followed by coming near a smaller body
##   green_rim      a rimmed body in view from 8 s after a growth (5 s after "Now food" ended);
##                  followed by hitting or eating one
##   hunt_for_meat  a meat-only body starving (balance input 6, Q-V4): once a run, never remembered
##
## The HUD feeds it the pool's context (PoolScene.hint_context) every few frames, each sim event
## with the pool's facts about it (PoolScene.hint_facts), and asks step() what shows; every time is
## the sim's, so a pause stops the clocks.

const SHOW_S := 6.0
const NEW_IDEA_GAP_S := 60.0
const REPEAT_S := 180.0
const EAT_SHARE := 0.1
const HOME_S := 120.0
const AFTER_GROWTH_S := 2.0
const GREEN_RIM_AFTER_S := 8.0
const TEXTS := {
	"eat_to_grow": "Eating well makes you grow",
	"sea_goes_on": "The sea goes on",
	"smaller_now": "They're smaller than you now",
	"flee_now": "They flee from you now",
	"green_rim": "Green rim: you can eat it now",
	"hunt_for_meat": "Hunt rammers from behind for meat",
}
## The order in which waiting ideas get their turn.
const ORDER: PackedStringArray = ["hunt_for_meat", "eat_to_grow", "smaller_now", "flee_now", "green_rim", "sea_goes_on"]
## Ideas shown at most once a run and never remembered.
const ONCE_A_RUN: PackedStringArray = ["hunt_for_meat"]

## Where followed ideas are remembered, and how they are saved; with none they last the run.
var memory: UserSettings
var _save := Callable()
var _followed_here := PackedStringArray()
var _wanted := {}            ## idea -> true while its moment lasts
var _shown_at := {}          ## idea -> sim time it last showed
var _last_new_at := -INF
var _showing := ""
var _until := -INF


## Followed ideas are read from and added to `p_memory`, and `save` is called as each is added.
func bind_memory(p_memory: UserSettings, save: Callable) -> void:
	memory = p_memory
	_save = save


func is_followed(id: String) -> bool:
	return _followed_here.has(id) or (memory != null and memory.hints_followed.has(id))


## The player did what idea `id` says: it never shows again (saved, but for ONCE_A_RUN ideas).
func follow(id: String) -> void:
	if ONCE_A_RUN.has(id) or is_followed(id):
		return
	if memory == null:
		_followed_here.append(id)
		return
	memory.hints_followed.append(id)
	if _save.is_valid():
		_save.call()


## The context now (PoolScene.hint_context): the ideas whose moment it is, and what it follows.
func observe(ctx: Dictionary) -> void:
	var beat_t := float(ctx.get("beat_t", -1.0))
	var jaw := bool(ctx.get("has_jaw", false))
	_wanted["sea_goes_on"] = bool(ctx.get("in_home_tile", false)) and float(ctx.get("alive_s", 0.0)) >= HOME_S
	_wanted["smaller_now"] = beat_t >= AFTER_GROWTH_S and jaw
	_wanted["flee_now"] = beat_t >= AFTER_GROWTH_S and not jaw
	_wanted["green_rim"] = beat_t >= GREEN_RIM_AFTER_S and bool(ctx.get("rimmed_in_view", false))
	_wanted["hunt_for_meat"] = bool(ctx.get("meat_only", false)) and bool(ctx.get("starving", false))
	if bool(ctx.get("near_smaller", false)):
		follow("smaller_now")
		follow("flee_now")


## A sim event, with the pool's facts about it ({smaller, rimmed}: whether the body hit or eaten is
## smaller than the cell, and rimmed) and the last context.
func on_event(event: Dictionary, facts: Dictionary, ctx: Dictionary) -> void:
	match str(event.get("type", "")):
		"ate":
			if int(ctx.get("size", 1)) == 1 and float(ctx.get("meter_share", 0.0)) >= EAT_SHARE:
				_wanted["eat_to_grow"] = true
			if bool(facts.get("rimmed", false)):
				follow("green_rim")
		"ring_full":
			follow("eat_to_grow")
		"tile_entered":
			if str(event.get("region", "")) != "home":
				follow("sea_goes_on")
		"hit":
			if event.get("attacker") == CreatureField.PLAYER_ID:
				if bool(facts.get("smaller", false)):
					follow("smaller_now")
				if bool(facts.get("rimmed", false)):
					follow("green_rim")


## The idea to show at sim time `now_s` ("" for none): the one showing until its SHOW_S is up (or it
## is followed), else the first waiting idea by ORDER that may show, at most one new every
## NEW_IDEA_GAP_S.
func step(now_s: float) -> String:
	if _showing != "" and now_s < _until and not is_followed(_showing):
		return _showing
	_showing = ""
	if now_s - _last_new_at < NEW_IDEA_GAP_S:
		return ""
	for id in ORDER:
		if not _wanted.get(id, false) or is_followed(id):
			continue
		if _shown_at.has(id) and (ONCE_A_RUN.has(id) or now_s - float(_shown_at[id]) < REPEAT_S):
			continue
		_showing = id
		_until = now_s + SHOW_S
		_shown_at[id] = now_s
		_last_new_at = now_s
		break
	return _showing


## The idea showing now ("" for none), as of the last step().
func showing() -> String:
	return _showing


static func text_of(id: String) -> String:
	return str(TEXTS.get(id, ""))
