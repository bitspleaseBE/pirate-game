class_name Teams
extends Object
## Team ids, in their own file so that [Ship] and [ProjectileSystem] can both
## refer to them without a cyclic `class_name` dependency between the two.

const PLAYER: int = 0
const ENEMY: int = 1


static func grid_kind(team: int) -> int:
	return SpatialGrid.KIND_PLAYER_SHIP if team == PLAYER else SpatialGrid.KIND_ENEMY_SHIP


## Physics layer bit for a team's hulls. Layer 1 = player_ship, 2 = enemy_ship.
static func physics_layer(team: int) -> int:
	return 1 << 0 if team == PLAYER else 1 << 1


static func hostile_grid_kind(team: int) -> int:
	return SpatialGrid.KIND_ENEMY_SHIP if team == PLAYER else SpatialGrid.KIND_PLAYER_SHIP
