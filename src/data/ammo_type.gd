class_name AmmoType
extends Resource
## One loadable shot type.
##
## Which damage bar a shot attacks is the whole design of the ammo system, so it
## is data, not a special case in code: chain shot is "high damage to SAILS,
## zero to HULL", grape is "damage to CANNONS at very short range".

enum Bar { HULL, SAILS, CANNONS }

@export var id: StringName = &"round"
@export var display_name: String = "Round Shot"
## Two or three words on what this shot is *for*. Shown on the ammo button,
## because a name alone ("chain shot") teaches a player nothing about when to
## reach for it, and blind-cycling five identical-looking options is not a
## decision — it is a guess.
@export var role: String = "all-purpose"
## Colour of the ball in flight and of the ammo button. The single cheapest way to
## make five shot types distinguishable mid-fight without five sprites.
@export var tint: Color = Color(1, 1, 1)
## Ball size relative to round shot, so grape reads as small and chain as heavy.
@export var visual_scale: float = 1.0
@export var icon: Texture2D

@export_group("Damage")
## Multiplier applied to the firing ship's base_damage.
@export var damage_mul: float = 1.0
@export var primary_bar: Bar = Bar.HULL
## Fraction of damage_mul also applied to the two other bars.
@export var splash_bar_mul: float = 0.0
## Radius of area damage at the impact point. 0 = single target.
@export var aoe_radius: float = 0.0

@export_group("Ballistics")
## Pixels per second along the ground track. Slow enough that a ball is visibly
## in flight for the best part of a second at gun range — you should be able to
## watch it travel and see whether you led the target correctly.
@export var muzzle_speed: float = 520.0
## Peak arc height in pixels, scaled by flight distance. Purely visual, but it
## is what makes leading a target feel readable.
@export var arc_height: float = 62.0
## Multiplies the ship's cannon_range.
@export var range_mul: float = 1.0
@export var reload_mul: float = 1.0

@export_group("Effects")
## Burn damage per second applied to the target for burn_duration.
@export var burn_dps: float = 0.0
@export var burn_duration: float = 0.0
## Fraction of the target's reload speed removed (grape shot killing crew).
@export var crew_kill: float = 0.0
@export var projectile_texture: Texture2D
@export var impact_pool: StringName = &"impact"
@export var trail_color: Color = Color(1, 1, 1, 0)

@export_group("Economy")
## true for round shot: always available, never consumed.
@export var unlimited: bool = false
@export var max_stock: int = 20


func damage_for(base_damage: float) -> float:
	return base_damage * damage_mul


func effective_range(ship_range: float) -> float:
	return ship_range * range_mul
