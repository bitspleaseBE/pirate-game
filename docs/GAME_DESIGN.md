# Pirates: Treasure Hunt — Game Design Outline

> Status: v0.1 outline. Everything here is a starting point, not a contract.

## 1. Pitch

A one-thumb naval action game. You start in a rowed dinghy in a hostile archipelago.
Tap to sail, tap to fire. Break an island's defences, plant your flag, moor at its
harbour and take the treasure off its quay — then spend the gold on a bigger, meaner
fleet. Up to three ships under your command.

**Feel:** the weight of a sailing ship. You cannot stop or strafe. Every fight is won by
positioning before it is won by shooting.

## 2. Platform targets & constraints

| | |
|---|---|
| Primary | Mobile web (iOS Safari, Android Chrome) |
| Secondary | Native iOS / Android, desktop web |
| Renderer | Godot GL Compatibility (WebGL2) — one renderer for every target |
| Perf target | 60 fps on a 2019 mid-range Android **in a browser**; 30 fps floor |
| Input | One finger. Everything must be reachable with a thumb. No text entry in gameplay. |
| Orientation | Landscape (sensor landscape) |
| Session | 3–8 minutes per island, 20–40 minutes per voyage, resumable at any port |

These constraints are the reason for most decisions below. See
[ARCHITECTURE.md](ARCHITECTURE.md) for how they are enforced in code.

## 3. Camera & presentation

Top-down 2D, orthographic, slight zoom-out. Camera follows the fleet centroid with
smoothing, clamps to the voyage bounds, and pinch-zooms between "read the whole fight"
and "see one ship's detail". Ships point bow-up at rotation 0.

## 4. Controls

| Gesture | Result |
|---|---|
| Tap open water | Selected ship sets course for that point — **and keeps its target** |
| Tap enemy ship / fort | Mark as target — your ships auto-fire when it enters a broadside arc |
| Tap the marked target again | Break off |
| Tap **BOARD** | Put a party onto a hull whose crew can no longer hold her |
| Tap own ship | Select it |
| Tap the fleet badge | Open the roster — a card per hull, tap one to take its helm |
| Tap Hideout | Set a course for the home port; it opens when you arrive |
| Tap captured island | Open the port screen |
| Tap ammo button | Cycle loaded shot type |
| Drag empty water | Pan camera freely; snaps back to the fleet after 2s |
| Pinch | Zoom (clamped) |
| Long-press enemy | Order a ram / boarding approach instead of a gun run |

**Automatic behaviours** (so the player is never punished for not micromanaging):

- Return fire when hit, if the attacker is in range and arc.
- Steer onto a firing beam **only while the player is not steering**. A course order takes
  the helm and the assist keeps its hands off until the ship arrives. This is the single
  most important rule in the combat model: engagement steering used to own the helm
  outright, so tapping an enemy played the fight for you and the player's whole
  contribution was one tap.
- Unselected ships hold a loose escort formation on the selected one.
- Auto-reload; auto-anchor at the beach node once an island is cleared.
- Ships steer around land rather than beaching themselves.

## 4b. Seamanship

Three rules make a hull feel like a hull rather than a sprite being dragged around.

### Steering needs way on

A rudder is a wing in moving water: no flow, no authority. Turn rate scales with speed, so
a ship that has lost way has lost its helm. Hard helm also scrubs speed — you cannot corner
and keep way — and the hull pivots about a point forward of amidships, throwing the stern
wide. Velocity lags heading, so a turning ship skids before it bites.

The lesson the player should absorb without being told: **keep moving**.

### Wind

The wind is a slowly-turning vector that gives the map a permanent tactical axis unrelated
to where the islands are. Being **upwind of your enemy** — the weather gage, the thing
age-of-sail captains actually fought over — means you choose when to close and they cannot
run from you.

| Angle off the wind | Point of sail | Speed |
|---|---|---|
| 0–50° | into the wind | 0.55 |
| 50–75° | close-hauled | 0.72 |
| 75–105° | beam reach | 0.95 |
| 105–150° | **broad reach** | **1.00** |
| 150–180° | running | 0.85 |

The fastest point of sail is a broad reach, not downwind — running dead before the wind,
the sails blanket each other. That is real, and it is more interesting than the intuition.

**Deliberately soft.** There is no no-go zone and no being caught in irons. You can steer
anywhere; a bad angle costs time, not control. An unforgiving wind on a one-thumb mobile
game reads as a broken game rather than a deep one, and the tactical payoff survives the
softening intact.

**And it is visible on the ships themselves.** *Built.* Every sailed hull carries canvas
composed at runtime over the hull (docs/ASSETS.md §Ships), and the rig is a read-out of
this model rather than decoration: yards brace sharp when a ship is trying to point and
square as the wind draws aft, the canvas fills and brightens on a good point of sail and
slats on a bad one, and it thins away as chain shot takes the rigging. Oared hulls carry
none, so the first Sloop is a visible promotion. Before this the only thing on screen that
knew the wind existed was a compass ring in the corner of the HUD — now the enemy's canvas
tells you where *they* can go, which is what the weather gage is for.

**It arrives as a progression beat.** Your first hull is oared, so the opening islands
teach tap-to-move, broadsides and the capture loop on a still sea. The wind wakes up the
moment you first command a sailed hull, with a one-time explanation — it is something the
upgrade gave you to think about, not a rule you were silently failing at while learning
everything else.

### Sail versus oar

| | Oared (dinghy, skiff, longboat) | Sailed (sloop and up) |
|---|---|---|
| Wind | ignores it entirely | governed by it |
| Top speed | low but constant | high, situational |
| Steering at low speed | fine — oars give steerage way | poor |
| Turns in place | yes (back one bank) | no |
| Slowed by | crew losses | rigging damage |

This makes two ammo types counter each other for free, out of the physics rather than a
special case: **chain shot** shreds rigging and is nearly useless against oars, while
**grape shot** kills the rowers an oared hull depends on. It also gives skiff swarms a
proper reason to exist — they are most dangerous exactly when you are struggling upwind.

## 5. Combat

### 5.1 Broadsides, not turrets

Cannons are mounted port and starboard with a ~120° firing arc each. You must *present a
side*. This is the whole reason tap-to-move is interesting: the fight is a dance of
crossing angles, and "sail past and rake them" is a real, learnable move.

### 5.2 Ballistic shot

Cannonballs have travel time and an arc — they render with a shadow beneath so you can
read altitude, and they splash on a miss. You lead a moving target. Range is a hard cap;
beyond it the ball splashes short.

### 5.2b Where the shot came from is worth as much as what it was loaded with

Two multipliers, and between them they are what makes holding the helm worth anything.

- **Range falloff.** A ball that has flown to the edge of its reach arrives spent (0.62x),
  full weight inside 45% of reach. Plinking from maximum range — the safest and by far the
  most boring thing a player can do — is also the weakest.
- **Raking.** A ball that arrives along a hull's bow-to-stern axis runs the length of her
  gun deck: **2.15x** damage, tapering to nothing by ~55 degrees off the axis. Crossing an
  enemy's stern is the age-of-sail tactic, and it is precisely the angle that auto-orbit
  never produces — a beam-to-beam circle rakes nobody.

### 5.3 Three damage bars, not one

Readable at a glance, and each one changes how the ship plays:

| Bar | Hit by | Effect at zero |
|---|---|---|
| **Hull** | Round, explosive, ram | Ship sinks |
| **Sails** | Chain shot, fire | Crippled — half speed, sluggish turn |
| **Cannons** | Grape, explosive, ram | Can't shoot — must flee or board |

### 5.4 Shot types

| Shot | Role | Cost |
|---|---|---|
| **Round shot** | Baseline hull damage | Free, unlimited |
| **Fire shot** | Burn-over-time, spreads between hulls | Low impact damage |
| **Explosive shot** | Small AoE — answer to swarms | Slow reload, limited stock |
| **Chain shot** | Shreds sails; stops runners and chargers | No hull damage; near-useless vs oars |
| **Grape shot** | Kills crew → cuts fire rate, cripples oared hulls, enables boarding | Very short range |

### 5.5 Melee

- **Ram & batter** — *built.* Hulls always collided; the collision did nothing. It now
  costs **both** parties, scaled by closing speed and by the tonnage ratio between them
  (capped at 3.2x either way). A Galleon running down a skiff is a massacre and the same
  manoeuvre in a Dinghy is suicide, and neither is special-cased — it falls out of the
  ratio. A fireship answers contact by detonating rather than by being crushed, which is
  the one exception and the reason the collision hook is virtual.
- **Board** — *built.* Grape shot sweeps a deck until its crew can no longer hold her
  (crew <= 0.62, or hull <= 0.35); pull alongside and a **BOARD** prompt appears. Hold the
  grapples ~2.8s — seconds spent stopped, alongside, in the middle of a fight, which is
  the cost — and she is yours: a hull that joins the fleet if a berth is standing empty,
  or three times her prize money and a restock of shot if not. This is the only reason
  grape shot exists; before it, grape cut a reload speed the player could not see on a
  ship they were about to sink anyway.

### 5.6 Enemy roster

Each hull carries a **doctrine** (`ShipStats.Doctrine`) rather than every enemy running one
brain. Skiff, Sloop and Brig used to be literally the same behaviour at three sizes, so the
only thing that changed across a whole voyage was how much health was pointed at you, and
the player was never asked to *do* anything different. LINE is the honest broadside duel;
SWARM presses to knife range and never runs; RAMMER and MORTAR are the important two,
because they are the only enemies that make the player move.

| Enemy | Behaviour |
|---|---|
| **Skiff** | Swarms, fast, one pop-gun, dies to anything. Appears in packs of 4–8. |
| **Sloop** | The standard duel. Circles for broadsides. |
| **Brig** | Tanky, heavy broadside, slow to turn — punish its stern. |
| **Bomb ketch** | *Built.* Out-ranges every hull in the game and lobs telegraphed shells — an honest ring on the water, re-solved while the tube charges. Cannot be traded with; has to be closed on. Runs if you get inside 32% of its reach. |
| **Fireship** | *Built.* No guns at all: it *is* the weapon. Beelines at you and detonates for 70 in a 210 radius. Glass — two clean hits kill it — and it steers for where you are rather than where you will be, so committing to a turn makes it overshoot. |
| **Fort cannon** | Static, long range, high damage, long visible wind-up. |
| **Shipyard** | *Built.* Not a combatant. Stands on the far side of the island from its harbour, so reaching it means a circuit of the coast past the batteries while the garrison is still afloat. Burn it and the waves stop. That trip is the decision inside every island fight. |
| **Castle keep** | *Built.* The one boss in a voyage, and a **two-phase** fight. A ring of four batteries plus a guard fleet, and a keep that is **armoured — 10% damage — while any battery still stands**. Silence the ring, then break the walls. It lobs a scattered three-shell salvo behind the same honest telegraph the bomb ketch uses. The island cannot be captured while it stands. |

## 6. The island loop

This is the beat the whole game repeats.

1. **Approach.** Sail into the island's alert radius. Defenders spawn, fort batteries wake,
   music layers in.
2. **Fight.** Waves come from the island's shipyard. Killing the shipyard cuts off
   reinforcements — the tactical decision of the fight is whether to push for it early.
3. **Clear.** All defenders and batteries destroyed → the island flips to your flag. A
   defender that breaks off and gets well clear counts as **routed**: it stops holding the
   island hostage, but it takes its prize money over the horizon with it. That is the
   choice at the end of most fights, and it is what chain shot is *for* — a hull with its
   rigging shredded makes 45% speed and gets nowhere. (Skiffs are SWARM doctrine and never
   break off, so they can never rout.)
4. **Moor.** Every island has a harbour on its sheltered coast — a quay, a jetty and a
   mooring buoy off the end of it. Your ship auto-sets a course for the buoy.
5. **Unload.** A longboat leaves the quay with the chest and rows out to you. The whole
   transaction happens at one visible place, so the reward lands somewhere rather than
   at a point in open water the player cannot see. (Player can watch or sail off and
   come back — the cargo stays on the quay until collected.)
6. **Loot.** Reward popup — see the loot table below.
7. **Port.** The harbour is now yours: repair, restock ammo, buy upgrades, respawn here.

## 7. Treasure map (the minimap)

Always-visible parchment minimap in a corner, tappable to expand full-screen.

- Island silhouettes — only for discovered islands
- Your fleet as small ship icons, heading indicated
- Enemy contacts as red skulls, only inside your lookout radius
- A red **X** on the harbour of every island with treasure still on its quay
- Fog on undiscovered water; dashed line to your current course

It draws from the same polygon data the islands are built from, so it costs almost nothing
to render. The map *is* the world data, not a second copy of it.

## 8. Fleet & progression

### 8.1 Currencies

- **Gold** — from treasure, wrecks, cargo. Buys upgrades and repairs. Only *banked* at a
  port; gold on a sunk ship is lost.
- **Diamonds** — rare, from bosses and successful boardings. Buys fleet slots and tier
  jumps.

### 8.2 Fleet slots

Start with one ship. Slot 2 unlocks around the third island, slot 3 after the first
castle. Both diamond-gated.

A hull bought in a port does not exist until the fleet sails — the roster grows at the
counter, the ship is built on the way out. That gap is invisible and it made the most
expensive purchase in the game look like it had failed, so three places now say so: the
port's shop row ("joins your fleet when you set sail"), the fleet line under the purse,
and a card in the roster reading **at the yard**.

The **fleet roster**, behind the HUD badge, is a card per hull: condition in the same
three bars painted over the ships themselves, what the crew are doing to the reload, guns
and reach, drive and refits. Tapping a card takes that hull's helm, which is also the only
way to select an escort that has drifted off screen.

### 8.3 Ship tiers

Per slot, upgradeable with gold + diamonds. Tiers are **tradeoffs, not strict upgrades**:

| Tier | Drive | Rig | Hull | Cannons/side | Cargo | Speed | Turn |
|---|---|---|---|---|---|---|---|
| Dinghy | oars | — | ▁ | 1 | ▁ | ▆ | ▆ |
| Sloop | sail | fore-and-aft | ▃ | 2 | ▃ | ▆ | ▅ |
| Brig | sail | mixed | ▅ | 4 | ▅ | ▄ | ▃ |
| Galleon | sail | square | ▇ | 6 | ▇ | ▂ | ▁ |

Rig is a real tradeoff, not flavour: a fore-and-aft Sloop points higher upwind, while a
square-rigged Galleon owns the broad reach and is miserable beating into it. And the
Dinghy is not simply the worst ship — it is the only one that does not care about the
wind at all, which on the wrong day is worth more than a gun deck.

A three-Sloop fleet and a single Galleon are both valid answers.

### 8.4 Upgrade slots (gold)

Hull plating · Sail rigging · Cannon count · Reload crew · Powder magazine (ammo
capacity) · Lookout (vision + minimap radius) · Carpenter (slow auto-repair)

### 8.5 Loot table

Gold · Diamond · Ammo crate (per shot type) · Repair kit · Extra life (respawn without
losing cargo) · Temporary boost — Double Shot / Ghost Sails / Iron Hull / Powder Monkey ·
Upgrade blueprint · Map fragment (reveals a distant island)

### 8.6 Failure

A sunk ship is lost, along with its unbanked cargo. Whole fleet wiped → back to the last
port with only what you banked. The tension is deliberate: *push one more island, or sail
home and bank it?*

## 9. World structure

- **Home port** — persistent, safe, always yours, and one tap away: the **Hideout**
  button carries the range home and sets the course, and the port opens when the fleet
  moors. That range is the other half of "push one more island, or sail home and bank
  it?" — it is not a decision the player can weigh without it.
- **Voyage** — a generated archipelago of 8–12 islands with a castle at the far end,
  laid out as a **chain** that works its way outward from home. Island tier (1–5) rises
  along the chain, and every island sits further from home than the one before it, so
  tier and distance say the same thing and the player picks their own difficulty by
  picking how far out to push.
- **Legs of 2,000–3,000 m.** Sailing is connective tissue, not content. Each hop is
  solved for directly rather than falling out of a ring radius, which is how the
  previous layout ended up with 8,000 m gaps between neighbours.
- Clear the castle → voyage complete, everything you carry is banked, next voyage seeds
  harder.

### 9.1 The ramp

Difficulty is a written-out ladder, not a formula, because it *is* the argument:

| Island | Tier | Garrison | Batteries | Shipyard |
|---|---|---|---|---|
| 1st | 1 | one skiff | — | — |
| 2nd–3rd | 2 | **one Navy Sloop** | — | — |
| 4th–6th | 3 | a sloop and a skiff | 1 | 1 hull a wave |
| 7th–9th | 4 | a brig and two sloops | 2 | 2 hulls a wave |
| 10th+ | 5 | brigs and sloops, four hulls | 3 | 2 hulls a wave |
| Castle | 5 | four hulls, **four batteries and an armoured keep**, twice the treasure | — | — |

The second island is the one that decides whether a new player keeps playing, and for a
while it was a Navy Sloop *and* a skiff, with a shore battery and two reinforcement waves
behind them, against a one-gun Dinghy. The step from the first island to the second is now
a step in **weight** — one proper warship instead of one pop-gun boat — and numbers do not
start climbing until tier 3.

Islands also alert **one at a time**. At 2,000–3,000 m apart a fleet cutting through a
channel can stand inside two alert radii at once, and two garrisons arriving together is
not a harder island, it is two islands. A fight the fleet has left astern releases the
hold, so running from a losing fight still works.

## 10. Audio direction

Sea ambience under everything. Creaking timbers when a hull is damaged. Cannon report with
a distant echo tail. Splashes, wood splinter, crew shouts on a hit. Shanty music that
layers instruments in as a fight escalates and strips back to solo accordion at sea.

### 10.1 The score is a gameplay system

*Built.* Three stems — `calm`, `tense`, `combat` — in one key, one tempo, and the same
length to the sample. They all start together, none of them ever stops, and
[MusicDirector] moves their volumes. Escalation is **additive**: the calm bed never fades,
because `tense` and `combat` are things laid on top of it rather than replacements for it.

This is information, not decoration. Music that thickens the moment a garrison wakes tells
the player something has changed before they have finished parsing the screen, through the
one channel nothing else in the game is using — the HUD is busy, the screen is busy, and
the ears are free.

Intensity is read off the world at 4 Hz, and the loudest of three things wins:

| Source | What it catches |
|---|---|
| **Company** — hostile hulls and shore guns near the fleet | first contact through to the last kill |
| **Violence** — damage dealt *or taken* in the last 6 s | the difference between circling and fighting |
| **The castle** — flat maximum | the end of a voyage |

Company alone tops out at 0.72, so a stand-off never sounds like a melee. Gains rise fast
and fall slowly: the music should arrive with the fight, and a reload lull is not the end
of a battle.

Whole-track crossfading was rejected. It needs a musically safe moment to switch, which
means either waiting for one — so the music reacts after the fight it is reacting to — or
cutting on the beat, which puts a seam in every time a skiff appears.

## 11. Out of scope for v1

Multiplayer · weather simulation · crew management sim · dialogue trees · 3D · IAP

## 12. Open questions

1. Should captured ships (from boarding) occupy a fleet slot, or be a separate salvage
   currency?
2. Is fog-of-war per-voyage or persistent across voyages?
3. How much of the landing-party sequence is interactive vs. a 4-second cutscene?
4. Does the player ever *lose* a captured island (counter-attack), or is capture permanent?
