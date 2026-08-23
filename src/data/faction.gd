class_name Faction
extends Resource
## Who an island belongs to, and what fighting them is like.
##
## Before this, difficulty was one number. Tier decided how many defenders and
## which hulls, and every island in the voyage was the same enemy at a different
## size — the player never had to change *what they did*, only how long they did
## it for. Doctrine ([enum ShipStats.Doctrine]) fixed some of that per hull; a
## faction fixes the rest per island, and it is also what turns a chain of
## islands into a voyage that goes somewhere.
##
## A faction is deliberately more than a palette. It carries:
##
##   * **its own roster** — which hulls it fields and in what order, so meeting
##     the Crown Navy does not put a jungle raft on the water;
##   * **stat multipliers** folded onto those hulls, so the same Sloop hull is a
##     different opponent under a different flag;
##   * **numbers** — how much its garrison swells beyond the island's tier, which
##     is the tribes' entire answer to being outgunned;
##   * **a flag**, which is how the player knows any of the above at a glance.
##
## The multipliers apply on top of the hull, not instead of it. A faction says
## "this navy's gunners are slow and their timber is thick", and the hull still
## says what a Brig is. Two dials, both readable.

## Stable id, used in save data and by [FactionLibrary].
@export var id: StringName = &"tribes"
@export var display_name: String = "Jungle Tribes"
## One line, shown when the player first meets them. This is the whole of the
## game's story delivery, so it has to say what they are and how to fight them.
@export_multiline var briefing: String = ""

@export_group("Colours")
## The field of the flag, and the charge on it. Two colours is enough to tell
## five factions apart at the size a flag is drawn from overhead, and more than
## two on a shape that small is mud.
@export var flag_field: Color = Color("2f6b3a")
@export var flag_charge: Color = Color("e0c060")

@export_group("Roster")
## The hulls this faction fields, in the order it launches them. Index past the
## end wraps, exactly as [SpawnDirector] already did with its per-tier lists.
##
## Empty means "whatever the island's tier would have fielded anyway", which is
## what the neutral home port wants and what any faction added later gets for
## free until somebody writes it a roster.
@export var hulls: Array[StringName] = []
## Extra defenders beyond what the island's tier asks for. The tribes' advantage
## is that there are simply more of them.
@export var extra_garrison: int = 0
## One more defender for each consecutive island already met under this flag.
##
## The tribes' islands are all tier 1–2, and tier is what usually grows a
## garrison, so without this their three islands are the same two canoes three
## times over — which is not "their advantage is numbers", it is a flat opening
## that the player's first Sloop walks through without taking a hit. It does
## exactly what the design asks for: they build up slowly, and the thing that
## makes the third tribal island harder than the first is that there are twice as
## many of them.
@export var garrison_ramp: int = 0
## Multiplier on reinforcement wave size, rounded up. Also theirs.
@export var wave_mul: float = 1.0
## Tier from which this faction's islands have a slipway feeding reinforcements.
##
## The default is the rule the archipelago already had. The tribes get it two
## tiers early — not because a canoe beach is a shipyard, but because "more of
## them keep coming" is the whole of what makes the tribes dangerous, and their
## islands are all tier 1–2. Take the beach and they stop.
@export var shipyard_from_tier: int = 3
## What this faction's guns are loaded with. Everyone but the tribes fires round
## shot; the tribes have no guns at all and shoot arrows, which is why this is a
## faction property rather than a hull one.
@export var gun_ammo: StringName = &"round"

@export_group("Character")
## Folded onto every hull this faction fields. One resource per hull per faction
## would be the obvious alternative and is a combinatorial trap — five factions
## times nine hulls is forty-five tables to keep in step.
@export var hull_mul: float = 1.0
@export var damage_mul: float = 1.0
## Above one is *slower*. Named for what it multiplies rather than for what it
## means, because that is what the arithmetic does and a "fire rate" that you
## divide by is how sign errors get in.
@export var reload_mul: float = 1.0
@export var speed_mul: float = 1.0
@export var range_mul: float = 1.0
## Prize money. A fearsome enemy has to be worth the risk or the player simply
## avoids them, and avoiding the interesting fight is not a strategy the game
## should reward.
@export var bounty_mul: float = 1.0


## The hull id this faction launches as its `index`-th defender, or an empty
## StringName if it has no roster of its own and the caller should fall back to
## the island's tier.
func hull_for(index: int) -> StringName:
	if hulls.is_empty():
		return &""
	return hulls[index % hulls.size()]


## This faction's version of a hull: the base stats with the faction's character
## folded in.
##
## Always a duplicate. [method ShipStatsLibrary.get_stats] hands out one shared
## cached resource per hull id, so writing to it here would re-flag every ship of
## that type in the world — including, eventually, the player's.
func build(hull_id: StringName) -> ShipStats:
	var base: ShipStats = ShipStatsLibrary.get_stats(hull_id)
	if is_neutral():
		return base

	var s: ShipStats = base.duplicate(true) as ShipStats
	s.max_hull *= hull_mul
	s.base_damage *= damage_mul
	s.reload_time *= reload_mul
	s.max_speed *= speed_mul
	s.cannon_range *= range_mul
	s.detonation_damage *= damage_mul
	s.bounty_gold = roundi(float(s.bounty_gold) * bounty_mul)
	s.accent_color = flag_field
	return s


## True when this faction changes nothing about a hull, so [method build] can
## hand back the shared resource instead of a copy. Worth checking: a garrison is
## rebuilt on every wave, and a duplicate per hull per wave is real garbage for
## no gain.
func is_neutral() -> bool:
	return (
		is_equal_approx(hull_mul, 1.0)
		and is_equal_approx(damage_mul, 1.0)
		and is_equal_approx(reload_mul, 1.0)
		and is_equal_approx(speed_mul, 1.0)
		and is_equal_approx(range_mul, 1.0)
		and is_equal_approx(bounty_mul, 1.0)
	)
