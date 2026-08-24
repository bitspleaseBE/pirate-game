class_name FactionLibrary
extends Object
## Who is out there, in the order the player meets them.
##
## Same shape as [AmmoLibrary] and [ShipStatsLibrary]: a `.tres` wins if one has
## been authored, and the code table below is the balance until one is. The
## voyage's *story* is here rather than in a script somewhere, because the story
## this game can tell is entirely "whose flag is on the island in front of you"
## and it should be readable as one column.
##
## The arc, and why it is this arc:
##
##   1. **Jungle tribes** — the opening. They do not sail, they shoot arrows, and
##      one canoe is nothing. What they have is numbers, and the numbers climb
##      over three islands, so the first thing the game teaches is not "shoot the
##      enemy" but "do not let three of them get behind you". Fought in a Dinghy
##      with one gun, which is why every number on them is small.
##   2. **The Crown Navy** — the first proper warships. Disciplined and slow:
##      thick timber, long guns, a leisurely rate of fire. They punish being
##      caught in the open and reward closing, which is the exact opposite of the
##      tribes, so the lesson has to be un-learned and re-learned.
##   3. **The Armada** and **the Marine Royale** — the same idea taken apart in
##      two directions. The Armada is heavier and slower still; the French are
##      lighter, faster and lean on the bomb ketch, so the shape of a navy fight
##      stops being one shape.
##   4. **The Brethren of the Coast** — other pirates, and the most dangerous
##      thing in the game. No discipline, no line, everything fast and everything
##      aimed at you: swarming skiffs, fireships and a rate of fire nothing else
##      matches. They are also worth the most, which is the point — the fight you
##      would avoid has to be the fight that pays.
##   5. **Mixed** — the last stretch alternates, so the player can no longer
##      prepare for one kind of enemy on the way in. The flag on the horizon is
##      the information, and by then they can read it.
##
## Multipliers are all relative to the same hull under a neutral flag, so a line
## in this table reads as a sentence about a navy rather than as nine numbers.

const ORDER: Array[StringName] = [
	&"tribes", &"navy_crown", &"navy_armada", &"navy_marine", &"brethren",
]

const PATHS: Dictionary = {
	&"tribes": "res://assets/data/factions/tribes.tres",
	&"navy_crown": "res://assets/data/factions/navy_crown.tres",
	&"navy_armada": "res://assets/data/factions/navy_armada.tres",
	&"navy_marine": "res://assets/data/factions/navy_marine.tres",
	&"brethren": "res://assets/data/factions/brethren.tres",
}

static var _cache: Dictionary = {}


static func get_faction(id: StringName) -> Faction:
	if _cache.has(id):
		return _cache[id]

	var path: String = PATHS.get(id, "")
	var faction: Faction = null
	if not path.is_empty() and ResourceLoader.exists(path):
		faction = load(path) as Faction
	if faction == null:
		faction = _fallback(id)

	_cache[id] = faction
	return faction


static func clear_cache() -> void:
	_cache.clear()


static func _fallback(id: StringName) -> Faction:
	var f := Faction.new()
	f.id = id

	match id:
		&"tribes":
			f.display_name = "Jungle Tribes"
			f.briefing = (
				"Outrigger canoes off the reef. No guns — bows, and they have to be"
				+ " close to use them. There will be more of them than you."
			)
			# Palm green on a band of ochre: the only flag in the game that is not a
			# European heraldic one, and the only one that is cloth on a paddle.
			f.flag_field = Color("2f6b3a")
			f.flag_charge = Color("d9a441")
			f.hulls = [&"war_canoe", &"war_canoe", &"war_raft"]
			f.gun_ammo = &"arrows"
			# The numbers advantage, and the whole of their threat. One extra hull
			# per island rather than two: their islands are tier 1–2, which is a
			# Dinghy with one gun a side, and being outnumbered three to one before
			# the player knows guns fire sideways is not a difficulty curve.
			f.extra_garrison = 1
			# Two canoes, then three, then four across their three islands, which is
			# about one Navy Sloop's worth of trouble by the end of it. See
			# [member Faction.garrison_ramp].
			f.garrison_ramp = 1
			f.wave_mul = 1.0
			# See [member Faction.shipyard_from_tier]. Their beach launches canoes
			# from the second island on, slowly, and burning it stops them.
			f.shipyard_from_tier = 2
			# Everything about a canoe is small. These are on top of hulls that are
			# already the lightest in the game — see ShipStatsLibrary.
			f.hull_mul = 1.0
			f.damage_mul = 1.0
			f.reload_mul = 1.0
			f.speed_mul = 1.0
			f.range_mul = 1.0
			f.bounty_mul = 1.0
		&"navy_crown":
			f.display_name = "Crown Navy"
			f.briefing = (
				"Ships of the line. Heavier than you, longer guns than you, and slow"
				+ " to reload. Take the punch, get inside their reach, and work."
			)
			f.flag_field = Color("1d3a75")
			f.flag_charge = Color("e8e2d0")
			# A Sloop, then a Cutter, and the Brig no sooner than third.
			#
			# The roster is walked in order and a garrison takes the front of it, so
			# these first two entries *are* the player's first navy island. Leading
			# with two warships would make it two full Sloops' worth of hull at the
			# same tier the old mix fielded a Sloop and a fireship — the tier-3
			# spike the ladder harness was built to catch. The Cutter exists exactly
			# so a navy can pad a garrison without adding another warship.
			f.hulls = [&"enemy_sloop", &"navy_cutter", &"enemy_brig", &"enemy_sloop"]
			# Thick timber and long guns, paid for at the gun captain's pace. The
			# reload penalty is what makes closing on them the right answer.
			f.hull_mul = 1.12
			f.damage_mul = 1.0
			f.reload_mul = 1.18
			f.speed_mul = 0.96
			f.range_mul = 1.15
			f.bounty_mul = 1.1
		&"navy_armada":
			f.display_name = "The Armada"
			f.briefing = (
				"Spanish hulls, built like forts and handled like them. They will not"
				+ " chase you. What they will do is hit once, very hard."
			)
			f.flag_field = Color("8c1c1c")
			f.flag_charge = Color("e6b52c")
			f.hulls = [&"enemy_sloop", &"navy_cutter", &"enemy_brig", &"bomb_ketch"]
			f.hull_mul = 1.3
			f.damage_mul = 1.2
			f.reload_mul = 1.3
			f.speed_mul = 0.86
			f.range_mul = 1.05
			f.bounty_mul = 1.35
		&"navy_marine":
			f.display_name = "Marine Royale"
			f.briefing = (
				"French squadron. Lighter than the Crown and much quicker on the"
				+ " helm, and there is a bomb ketch behind them dropping shells."
			)
			f.flag_field = Color("f0efe6")
			f.flag_charge = Color("2f5fb8")
			f.hulls = [&"enemy_sloop", &"navy_cutter", &"bomb_ketch", &"enemy_brig"]
			f.hull_mul = 0.92
			f.damage_mul = 1.05
			f.reload_mul = 0.94
			f.speed_mul = 1.14
			f.range_mul = 1.0
			f.bounty_mul = 1.2
		&"brethren":
			f.display_name = "Brethren of the Coast"
			f.briefing = (
				"Pirates, like you, and better at it. They come fast, they come from"
				+ " every side, and one of those hulls is full of powder."
			)
			# Bone on black. The only flag that is not a nation's.
			f.flag_field = Color("15161a")
			f.flag_charge = Color("ded8c4")
			# Sloop, fireship, skiff is the garrison the player meets, and it is
			# their signature — a gun duel, a bomb and a knife all at once.
			#
			# The Brig is *last*, and that placement is the whole difference
			# between a hard island and an unwinnable one. Positions 3 and 4 are
			# the first reinforcement wave, and with the Brig there the wave that
			# arrived immediately after that three-hull fight was a Brethren Brig —
			# 32 damage a second against a player who has just spent their whole
			# hull and cannot repair until the island is theirs. Both full-chain
			# ladder runs died exactly there. Two more cheap hulls instead is still
			# relentless, which is the point of them, and the Brig turns up on the
			# wave after that for a player who is taking too long.
			f.hulls = [
				&"enemy_sloop", &"fireship", &"skiff", &"skiff", &"fireship", &"enemy_brig",
			]
			# Thin timber, fast hulls, guns worked by people with nothing to lose.
			# No range bonus: everything about the Brethren is about being close.
			f.hull_mul = 0.94
			f.damage_mul = 1.22
			f.reload_mul = 0.82
			f.speed_mul = 1.18
			f.range_mul = 0.92
			# Worth the most in the game by a distance. A fight the player is
			# entitled to be frightened of has to pay, or the correct play is to
			# sail round it, and sailing round the interesting fight is not a
			# strategy this game should reward.
			f.bounty_mul = 1.8
		&"player":
			# Your own colours. Not in [constant ORDER] — that is the list of people
			# who shoot at you — and it fields no hulls and bends no stats, because
			# the player's ships are built from [GameState.fleet] and upgraded in a
			# port. All this exists for is the flag.
			#
			# Deliberately not the Brethren's black: those are the *other* pirates,
			# and at the point they turn up the player has to be able to tell their
			# own hulls from theirs at a glance in a fight where both are fast and
			# both are coming from every angle.
			f.display_name = "Your Colours"
			f.flag_field = Color("8f1f2e")
			f.flag_charge = Color("efe6cf")
		_:
			# Neutral: the home port, and the safety net for an id that has been
			# renamed out from under a save. Changes nothing about a hull, so
			# [method Faction.is_neutral] lets the whole faction layer cost nothing.
			f.id = &"neutral"
			f.display_name = "No Colours"
			f.flag_field = Color("6b6b6b")
			f.flag_charge = Color("cfcfcf")

	return f
