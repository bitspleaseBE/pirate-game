class_name UnlockTable
extends Object
## What the player is allowed to own yet, and when it opens up.
##
## ## Why anything is locked at all
##
## Everything in this game was available from the first minute. A brand new
## player, still working out that guns fire sideways, was handed five shot types
## and five upgrade lines — eleven decisions, none of which they had the
## information to make, all presented at once. The predictable result is that
## they pick nothing: they fire round shot for the whole voyage and buy hull
## plating because it is at the top of the list, and every other system in the
## game may as well not exist.
##
## Locking is not about pacing power. It is about only ever asking a question
## the player can answer. The opening voyage is one shot type and three upgrades
## — hull, guns, reload, which are "tougher", "hits harder", "shoots faster" and
## need no explanation at all. Everything after that arrives one at a time, on a
## beat the player already understands as a reward, with a toast that says what
## it is for.
##
## ## The counter
##
## Islands captured, across the save. Not gold, not voyages, not a quest flag:
## it is the one number that means "how much of this game have you actually
## done", it survives a wipe, and the player is already watching it because it
## is the thing they are doing. It also means the ramp is the same for a careful
## player and a reckless one, which a gold threshold would not be.
##
## The tiers are deliberately spaced so nothing lands on the same island as
## anything else. Two things unlocking at once is one thing unlocking and one
## thing being missed.

## Shot types, by islands captured. Round shot is free forever; the rest arrive
## in the order they are useful:
##
##   * **grape** first, on the second island. It is the boarding enabler, and
##     capturing a hull instead of sinking it is the single biggest thing the
##     player has not yet discovered.
##   * **chain** on the fourth, which is about where the first enemy runs from a
##     fight — [TutorialDirector] teaches chain at exactly that moment and until
##     now was teaching a button they already had and had ignored.
##   * **fire** on the sixth, when hulls are big enough for a burn to matter.
##   * **explosive** last, because it is the only shot type whose case is
##     "there are several of them", and there are not several of them until the
##     Brethren.
const AMMO: Dictionary = {
	&"round": 0,
	&"grape": 2,
	&"chain": 4,
	&"fire": 6,
	&"explosive": 8,
}

## What the player is given the moment a shot type opens up. Enough to use it
## through the fight it was unlocked for without a shopping trip first — an
## unlock the player cannot immediately try is an announcement, not a reward.
const AMMO_GRANT: int = 10

## Upgrade lines, by islands captured.
##
## The three that start unlocked are the three that need no explanation:
## `plating` is "tougher", `gunnery` is "hits harder", `crew` is "shoots
## faster". Those are the whole shop for the tribal islands.
##
## The two held back are the two that are about *position* rather than about
## numbers, and neither means anything until the player has met an enemy who can
## outrun or outrange them — which is the navy. `rigging` opens on the first
## navy island and `lookout` (long guns) two islands later, once the Crown's
## reach has been felt.
const UPGRADES: Dictionary = {
	&"plating": 0,
	&"gunnery": 0,
	&"crew": 0,
	&"rigging": 3,
	&"lookout": 5,
}


## Islands the player must have captured before `id` is theirs. Zero for
## anything not in the table — an id nobody has written a rule for is available,
## because the alternative is a shot type that silently cannot be fired.
static func ammo_requirement(id: StringName) -> int:
	return int(AMMO.get(id, 0))


static func upgrade_requirement(id: StringName) -> int:
	return int(UPGRADES.get(id, 0))


static func ammo_unlocked(id: StringName) -> bool:
	return GameState.stats_islands_captured >= ammo_requirement(id)


static func upgrade_unlocked(id: StringName) -> bool:
	return GameState.stats_islands_captured >= upgrade_requirement(id)


## "Take 2 islands" — the line shown on a locked row, so a lock is a signpost
## rather than a closed door. A player who can see what is coming and what it
## costs is being given a reason to sail on; one who can only see a grey box is
## being told off.
static func requirement_phrase(needed: int) -> String:
	var short: int = needed - GameState.stats_islands_captured
	if short <= 0:
		return ""
	return "Take 1 more island" if short == 1 else "Take %d more islands" % short


## Everything that has just become available, given how many islands were
## captured before this one.
##
## Returns entries of `{"kind": &"ammo"|&"upgrade", "id": StringName}`. Driven
## off the *change* rather than off a stored set of owned unlocks, so there is
## exactly one source of truth — the capture count — and a save from before this
## existed opens the right doors the moment it is loaded rather than having to be
## migrated.
static func newly_unlocked(previous_captures: int) -> Array[Dictionary]:
	var now: int = GameState.stats_islands_captured
	var out: Array[Dictionary] = []
	for id: StringName in AmmoLibrary.ORDER:
		var needed: int = ammo_requirement(id)
		if needed > previous_captures and needed <= now:
			out.append({"kind": &"ammo", "id": id})
	for id: StringName in UpgradeLibrary.ORDER:
		var needed: int = upgrade_requirement(id)
		if needed > previous_captures and needed <= now:
			out.append({"kind": &"upgrade", "id": id})
	return out
