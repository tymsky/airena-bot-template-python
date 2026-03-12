# Observation Reference (openra.v1)

Every `tick` message contains an observation of the current game state. Parse it with `Observation.from_tick(msg)`:

```python
from airena_sdk import Observation

@bot.on("tick")
def handle_tick(msg, state):
    obs = Observation.from_tick(msg)
    tick = obs.tick
    # ...
```

All fields are typed dataclasses (frozen, immutable).

---

## Observation

| Field | Type | Description |
|-------|------|-------------|
| `tick` | int | Current game tick |
| `self_info` | `SelfInfo` | Your player state |
| `units` | tuple[Unit, ...] | Your own units and buildings |
| `enemies` | tuple[EnemyUnit, ...] | Enemy units visible through fog of war |
| `nearby_resources` | tuple[ResourceCell, ...] | Resource cells near your base |
| `map` | `MapInfo` | Map dimensions |
| `fow_enforced` | bool | True if fog of war is active (default) |
| `game_events` | tuple[GameEvent, ...] | Notable events since last tick |

---

## SelfInfo (`obs.self_info`)

Your player state.

| Field | Type | Description |
|-------|------|-------------|
| `player_id` | int | Your player ID |
| `faction` | string | Your faction internal name (e.g. `"england"`, `"russia"`) |
| `resources` | `Resources` | Economy state |
| `placement_pending` | bool | True if a completed building is ready for placement |
| `placement_type_id` | string/None | Type ID of building ready to place, or None |
| `build_queue` | tuple[ProductionItem, ...] | Flat list of all items across all production queues |
| `production_queues` | tuple[ProductionQueue, ...] | Per-queue production details |
| `action_results` | tuple[ActionResult, ...] | Results of actions from the previous tick |
| `explored_ratio` | float/None | Fraction of map explored (0.0–1.0) |
| `match_stats` | `MatchStats`/None | Cumulative match statistics |
| `superweapons` | tuple[Superweapon, ...] | Superweapon charge status (empty if none) |

**Helper methods:**

- `self_info.queue_for("Building")` → `ProductionQueue | None` — find a queue by type (case-insensitive)
- `self_info.buildable_in("Infantry")` → `tuple[str, ...]` — shortcut for buildable item type_ids
- `self_info.find_action_result("place_building")` → `ActionResult | None` — find first result by action type

### Resources

| Field | Type | Description |
|-------|------|-------------|
| `cash` | int | Current credits (combined cash + ore value) |
| `power` | int | Power balance (generated minus consumed). Negative = low power, slows production. |

### faction

Your faction determines available units and buildings. Common RA factions:
- `england`, `france`, `germany` (Allied)
- `russia`, `ukraine` (Soviet)

### MatchStats

| Field | Type | Description |
|-------|------|-------------|
| `units_killed` | int | Enemy units destroyed |
| `buildings_killed` | int | Enemy buildings destroyed |
| `units_lost` | int | Own units lost |
| `buildings_lost` | int | Own buildings lost |
| `total_earned` | int | Total credits earned |
| `total_spent` | int | Total credits spent |
| `army_value` | int | Current total value of all owned units/buildings |

### Superweapon

| Field | Type | Description |
|-------|------|-------------|
| `type_id` | string | Superweapon type (e.g. `"nuke"`, `"chronoshift"`, `"iron_curtain"`) |
| `ready` | bool | Whether charged and ready to fire |
| `ticks_remaining` | int | Ticks until charged (0 when ready) |

---

## ProductionQueue (`obs.self_info.production_queues`)

| Field | Type | Description |
|-------|------|-------------|
| `queue_type` | string | Category: `"Building"`, `"Infantry"`, `"Vehicle"`, `"Aircraft"`, `"Ship"` |
| `enabled` | bool | Whether this queue is active (requires a production building) |
| `queue_length` | int | Number of items currently being produced |
| `items` | tuple[ProductionItem, ...] | Items in production |
| `buildable_items` | tuple[str, ...] | Type IDs currently available for production |

**Helper method:** `queue.first_done()` → `str | None` — returns type_id of first completed item.

### ProductionItem

| Field | Type | Description |
|-------|------|-------------|
| `item_type_id` | string | Type ID being produced (e.g. `"powr"`, `"e1"`) |
| `progress` | float | Production progress: 0.0 (just started) to 1.0 (complete) |
| `done` | bool | True when production is finished |
| `paused` | bool | True if production is paused (e.g. low power) |
| `ticks_remaining` | int/None | Estimated ticks until production completes |
| `status` | string/None | Production status: `"queued"`, `"building"`, `"on_hold"`, `"ready"`, `"placing"` |

### buildable_items

List of type IDs that can be produced right now, taking into account faction, tech tree prerequisites, and whether the queue is enabled.

```python
# Shortcut via SelfInfo helper
available = obs.self_info.buildable_in("Building")

# Or manually
queue = obs.self_info.queue_for("Building")
if queue and queue.enabled:
    log(f"Can build: {queue.buildable_items}")
```

---

## SelfInfo.build_queue

Flat list of all items across all production queues. Same format as `items` in each `ProductionQueue`. Convenience shortcut if you don't care which queue an item belongs to.

---

## ActionResult (`obs.self_info.action_results`)

Results of actions submitted in the previous tick.

| Field | Type | Description |
|-------|------|-------------|
| `action` | string | Action type attempted (e.g. `"move"`, `"deploy"`) |
| `status` | string | `"ok"` or an error code |
| `unit_id` | int/None | Unit ID from the original action (if applicable) |
| `detail` | string/None | Additional failure info |
| `placement_detail` | string/None | Placement failure reason (for `place_building`): `"terrain"`, `"too_far"`, `"blocked"` |

**Ordering contract:** Results are returned in the same order as the actions you sent. `action_results[i]` corresponds to `actions[i]` from your previous response.

**Lifecycle:** Results are only present for one tick. If you send no actions, the next tick's `action_results` will be empty.

See [action-reference.md](action-reference.md) for the full list of status codes per action type.

```python
for r in obs.self_info.action_results:
    if r.status != "ok":
        log(f"Action {r.action} failed: {r.status}")

# Or use the helper to find a specific result:
result = obs.self_info.find_action_result("place_building")
if result and result.status == "ok":
    log("Building placed!")
```

---

## Unit (`obs.units`)

Your own units and buildings. Full visibility (no fog of war restriction).

| Field | Type | Always present | Description |
|-------|------|----------------|-------------|
| `id` | int | yes | Unique unit instance ID. Use this for action commands. |
| `type_id` | string | yes | Unit type (e.g. `"mcv"`, `"e1"`, `"1tnk"`, `"fact"`, `"powr"`) |
| `x` | int | yes | X cell coordinate |
| `y` | int | yes | Y cell coordinate |
| `hp` | int | yes | Current hit points |
| `max_hp` | int | yes | Maximum hit points |
| `facing` | int | yes | Direction (0–255) |
| `cooldowns` | dict[str, int] | yes | Weapon cooldowns: `{weapon_id: ticks_remaining}` |
| `can_deploy` | bool | yes | Whether unit can deploy/transform (relevant for MCV) |
| `current_order` | string | yes | Current activity (e.g. `"Idle"`, `"Move"`, `"Attack"`) |
| `cargo_ratio` | float/None | harvesters | Cargo fullness: 0.0 (empty) to 1.0 (full) |
| `harvester_state` | string/None | harvesters | `"harvesting"`, `"delivering"`, or `"idle"` |
| `refinery_queue` | int/None | refineries | Number of harvesters queued/docked |
| `veterancy` | Veterancy/None | if present | `{"level": 0–3, "progress": 0.0–1.0}` |
| `stance` | string/None | if present | Combat stance: `"attack_anything"`, `"defend"`, `"return_fire"`, `"hold_fire"` |
| `passenger_count` | int/None | transports | Number of passengers carried |
| `passengers` | tuple[Passenger, ...] | transports | `[Passenger(id, type_id), ...]` |
| `repairing` | bool/None | buildings | Whether the building is currently being repaired |

**Buildings vs mobile units:** Both appear in `obs.units`. Use `type_id` and the ruleset `is_building` field to distinguish. Common buildings: `fact`, `powr`, `proc`, `tent`, `weap`.

```python
own_units = obs.units
buildings = [u for u in own_units if u.type_id in ("fact", "powr", "proc", "tent", "weap")]
mobile = [u for u in own_units if u.type_id not in ("fact", "powr", "proc", "tent", "weap")]
```

---

## EnemyUnit (`obs.enemies`)

Enemy units visible through fog of war.

| Field | Type | Description |
|-------|------|-------------|
| `id` | int | Unit instance ID |
| `type_id` | string | Unit type |
| `x` | int | X cell coordinate |
| `y` | int | Y cell coordinate |
| `hp` | int | Current hit points |
| `max_hp` | int | Maximum hit points |
| `facing` | int/None | Direction (0–255) |
| `current_order` | string/None | Current activity |

---

## ResourceCell (`obs.nearby_resources`)

Explored resource cells near your base (within ~20-cell radius of your first Refinery or Construction Yard). Up to 200 cells.

| Field | Type | Description |
|-------|------|-------------|
| `x` | int | Cell X coordinate |
| `y` | int | Cell Y coordinate |
| `kind` | string | Resource type: `"gold"` or `"gems"` |
| `density` | float/None | Resource richness: 0.0 (depleted) to 1.0 (full) |

```python
resources = obs.nearby_resources
gold_cells = [r for r in resources if r.kind == "gold"]
```

---

## MapInfo (`obs.map`)

| Field | Type | Description |
|-------|------|-------------|
| `width` | int | Map width in cells |
| `height` | int | Map height in cells |
| `buildable` | string/None | RLE-encoded buildable grid (from ruleset) |

---

## GameEvent (`obs.game_events`)

Notable events since the last tick. Use these to react to important happenings without scanning all units each tick.

| Field | Type | Description |
|-------|------|-------------|
| `event` | string | Event type (see below) |
| `tick` | int | Game tick when the event occurred |
| `unit_id` | int/None | Related unit ID |
| `type_id` | string/None | Related unit type ID |
| `x` | int/None | Event location X |
| `y` | int/None | Event location Y |
| `detail` | string/None | Additional info |

**Event types:**
- `unit_destroyed` — one of your units was destroyed
- `building_captured` — a building was captured
- `building_sold` — a building was sold
- `low_power` — your power balance went negative
- `unit_produced` — a unit finished production
- `building_placed` — a building was placed on the map

```python
for event in obs.game_events:
    if event.event == "unit_destroyed":
        log(f"Lost {event.type_id} at ({event.x}, {event.y})")
```

---

## Ruleset Data

The `ruleset` message (sent once before the first tick) contains static game data:

```python
from airena_sdk import Ruleset

@bot.on("ruleset")
def handle_ruleset(msg, state):
    state["ruleset"] = Ruleset.from_msg(msg)
    state["unit_types"] = {u.type_id: u for u in state["ruleset"].unit_types}
```

### UnitType

| Field | Type | Description |
|-------|------|-------------|
| `type_id` | string | Stable identifier (matches `type_id` in observations) |
| `display_name` | string | Human-readable name |
| `is_building` | bool | Whether this is a structure |
| `max_hp` | int | Maximum hit points |
| `speed` | number | Movement speed (0 for buildings) |
| `cost` | int | Resource cost to produce |
| `build_time` | int | Build duration in ticks |
| `weapons` | list[string] | Weapon IDs this unit uses |
| `armor_type` | string | Armor class |
| `sight_range` | number | Vision range in cells |
| `power_delta` | int | Power generation (positive) or drain (negative) |
| `prerequisites` | list[string] | Required buildings to unlock |
| `transport_capacity` | int | Passenger slots (0 if not a transport) |
| `abilities` | list[string] | Special abilities (e.g. `"nuke"`, `"chronoshift"`) |
| `sell_ratio` | float | Fraction of cost refunded on sell (e.g. 0.5) |
| `repair_cost_factor` | float | Repair cost as fraction of build cost |

### Weapon

| Field | Type | Description |
|-------|------|-------------|
| `weapon_id` | string | Unique identifier |
| `range` | number | Attack range in cells |
| `damage` | int | Raw damage per hit |
| `reload_ticks` | int | Ticks between shots |
| `burst` | int | Shots per magazine |
| `min_range` | number | Minimum attack range (0 if none) |
| `projectile_speed` | number | Projectile speed |
| `can_target` | string | Target type: `"ground"`, `"air"`, `"both"` |
| `splash` | number | Splash damage radius (0 if none) |
| `versus` | dict | Armor damage multipliers: `{armor_type: percentage}` |

### Terrain / Helper functions

```python
from airena_sdk import decode_rle, can_build_at

@bot.on("ruleset")
def handle_ruleset(msg, state):
    state["ruleset"] = Ruleset.from_msg(msg)

# Check if a cell is buildable
if can_build_at(state["ruleset"].terrain, x, y):
    actions.append(place_building(building_type_id="powr", x=x, y=y))
```
