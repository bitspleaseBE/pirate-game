class_name ShipStats
extends Resource
## Everything that makes one hull different from another.
##
## Authored as `.tres` under `assets/data/ships/`. No balance number belongs in
## code — see docs/ARCHITECTURE.md §10.

@export var id: StringName = &"sloop"
@export var display_name: String = "Sloop"
## 1 = Dinghy … 4 = Galleon. Drives shop ordering and enemy scaling.
@export_range(1, 4) var tier: int = 2

@export_group("Durability")
@export var max_hull: float = 100.0
@export var max_sails: float = 60.0
@export var max_cannons_health: float = 50.0
## Hull points regenerated per second by the Carpenter upgrade.
@export var repair_rate: float = 0.0

@export_group("Movement")
## Pixels per second at full sail. A Sloop is ~160px long, so this is a little
## under two-thirds of a ship-length per second — slow enough that committing to
## a course is a real decision, which is the point of the whole broadside rule.
@export var max_speed: float = 108.0
@export var acceleration: float = 46.0
## Degrees per second at full speed. Big hulls turn like barns.
@export var turn_rate_deg: float = 62.0
## Fraction of turn rate retained when the sails are shredded.
@export var crippled_speed_mul: float = 0.45

@export_group("Gunnery")
@export var cannons_per_side: int = 2
@export var cannon_range: float = 620.0
## Half-angle of the broadside arc, in degrees, measured off the beam.
@export var broadside_arc_deg: float = 55.0
## Seconds between volleys from one side. Long on purpose: a broadside should be
## an event you set up and then watch land, not a stream of fire.
@export var reload_time: float = 5.0
## Seconds between individual guns in one broadside. Long enough that the volley
## rolls audibly down the hull instead of cracking off as one noise.
@export var gun_stagger: float = 0.22
## Damage per ball. High, to match the slow reload — every shot should matter.
@export var base_damage: float = 24.0

@export_group("Physical")
## Used for collision, hit tests, culling extents and ram damage.
@export var hull_radius: float = 48.0
## Ram damage scales with this. Roughly proportional to hull_radius squared.
@export var tonnage: float = 100.0
@export var cargo_capacity: int = 200

@export_group("Presentation")
@export var hull_texture: Texture2D
@export var sail_texture: Texture2D
@export var sprite_scale: float = 1.0
## Multiplied into the hull sprite. White leaves the painted master untouched;
## enemy hulls use a slight cool tint until per-faction accent masks are wired up
## (`hull_sloop_accent_mask.png` exists for that, Wave 1).
@export var accent_color: Color = Color.WHITE


## Effective speed given current sail damage, as a 0..1 fraction of max.
func speed_multiplier(sails_fraction: float) -> float:
	return lerpf(crippled_speed_mul, 1.0, clampf(sails_fraction, 0.0, 1.0))
