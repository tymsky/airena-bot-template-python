# Action Reference (openra.v1)

All actions are sent as part of an `actions` message in response to a `tick`:

```json
{"type": "actions", "tick": 150, "actions": [...]}
```

Field names below are canonical and match `actions.schema.json`.

---

## move

Move a unit to map coordinates.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `action` | `"move"` | yes | |
| `unit_id` | int | yes | ID of the unit to move |
| `x` | int | yes | Target X coordinate |
| `y` | int | yes | Target Y coordinate |

**Preconditions:** Unit must exist, be alive, and be owned by the bot.

**Possible results:** `ok`, `invalid_unit`

```python
from airena_sdk import move
actions.append(move(unit_id=42, x=120, y=210))
```

---

## group_move

Move multiple units to the same position. Counts as **1 action** regardless of group size.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `action` | `"group_move"` | yes | |
| `unit_ids` | list[int] | yes | IDs of units to move (1–20) |
| `x` | int | yes | Target X coordinate |
| `y` | int | yes | Target Y coordinate |

**Preconditions:** All units must exist, be alive, and be owned by the bot.

**Possible results:** `ok`, `invalid_unit`

```python
from airena_sdk import group_move
ids = [u.id for u in obs.units if u.type_id == "e1"]
actions.append(group_move(unit_ids=ids, x=150, y=200))
```

---

## group_attack_move

Attack-move multiple units to the same position, engaging enemies en route. Counts as **1 action**.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `action` | `"group_attack_move"` | yes | |
| `unit_ids` | list[int] | yes | IDs of units to attack-move (1–20) |
| `x` | int | yes | Target X coordinate |
| `y` | int | yes | Target Y coordinate |

**Preconditions:** All units must exist, be alive, and be owned by the bot.

**Possible results:** `ok`, `invalid_unit`

```python
from airena_sdk import group_attack_move
army = [u.id for u in obs.units if u.type_id in ("1tnk", "2tnk")]
actions.append(group_attack_move(unit_ids=army, x=enemy.x, y=enemy.y))
```

---

## attack_unit

Order a unit to attack a specific target unit.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `action` | `"attack_unit"` | yes | |
| `unit_id` | int | yes | ID of the attacking unit |
| `target_unit_id` | int | yes | ID of the target unit |

**Preconditions:** Both units must exist and be alive. Attacker must be owned by the bot.

**Possible results:** `ok`, `invalid_unit`, `invalid_target`

```python
from airena_sdk import attack_unit
actions.append(attack_unit(unit_id=43, target_unit_id=99))
```

---

## deploy

Deploy/transform a unit in place (e.g. MCV -> Construction Yard).

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `action` | `"deploy"` | yes | |
| `unit_id` | int | yes | ID of the unit to deploy |

**Preconditions:** Unit must have a deploy/transform capability and `can_deploy` must be `true` in observation.

**Possible results:** `ok`, `invalid_unit`, `cannot_deploy`

```python
from airena_sdk import deploy
mcv = next((u for u in obs.units if u.type_id == "mcv" and u.can_deploy), None)
if mcv:
    actions.append(deploy(unit_id=mcv.id))
```

---

## stop

Cancel a unit's current order.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `action` | `"stop"` | yes | |
| `unit_id` | int | yes | ID of the unit to stop |

**Preconditions:** Unit must exist, be alive, and be owned by the bot.

**Possible results:** `ok`, `invalid_unit`

```python
from airena_sdk import stop
actions.append(stop(unit_id=44))
```

---

## harvest

Order a harvester to harvest resources at map coordinates.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `action` | `"harvest"` | yes | |
| `unit_id` | int | yes | ID of the harvester unit |
| `x` | int | yes | Target X coordinate |
| `y` | int | yes | Target Y coordinate |

**Preconditions:**
- Unit must have the Harvester trait (be a harvester unit)
- Target cell must be within the map
- Target cell must contain resources

**Possible results:** `ok`, `invalid_unit`, `not_a_harvester`, `out_of_map`, `invalid_resource_target`

```python
from airena_sdk import harvest
# Use nearby_resources from observation to find resource cells
resources = obs.nearby_resources
if resources:
    r = resources[0]
    actions.append(harvest(unit_id=harvester_id, x=r.x, y=r.y))
```

---

## queue_production

Queue production of a unit or building at a production facility.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `action` | `"queue_production"` | yes | |
| `producer_id` | int | yes | ID of the production building (e.g. Construction Yard, Barracks) |
| `item_type_id` | string | yes | Type ID of the item to produce (e.g. `"powr"`, `"e1"`) |
| `count` | int | no | Number of items to queue (default: 1) |

**Preconditions:**
- Producer building must exist and be owned by the bot
- Item must be in the `buildable_items` list for the relevant queue
- Bot must have sufficient funds (`cash >= cost`)
- The relevant production queue must be enabled

**Possible results:** `ok`, `producer_not_found`, `unknown_item`, `not_buildable`, `queue_disabled`, `insufficient_funds`

**How to find the producer_id:** Look at your units in observation. The Construction Yard (`fact`) produces buildings. Barracks (`tent`) produces infantry. War Factory (`weap`) produces vehicles.

**How to check buildable items:** Use `obs.self_info.buildable_in("Building")` or inspect `obs.self_info.production_queues` directly.

```python
from airena_sdk import queue_production
# Find construction yard
conyard = next((u for u in obs.units if u.type_id == "fact"), None)
if conyard:
    actions.append(queue_production(producer_id=conyard.id, item_type_id="powr"))
```

---

## place_building

Place a completed building at map coordinates.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `action` | `"place_building"` | yes | |
| `building_type_id` | string | yes | Type ID of the building to place (e.g. `"powr"`) |
| `x` | int | yes | Target X coordinate |
| `y` | int | yes | Target Y coordinate |

**Preconditions:**
- A completed building item of the specified type must exist in the production queue (`done: true`)
- Check `observation.self.placement_pending` and `observation.self.placement_type_id`
- Placement must be valid (terrain check, base proximity check)

**Possible results:** `ok`, `no_completed_item`, `unknown_building`, `invalid_placement`

**How to check readiness:** When `obs.self_info.placement_pending` is `True` and `obs.self_info.placement_type_id` matches your building, it's ready to place.

```python
from airena_sdk import place_building
if obs.self_info.placement_pending and obs.self_info.placement_type_id == "powr":
    actions.append(place_building(building_type_id="powr", x=base_x + 2, y=base_y))
```

See [building-lifecycle.md](building-lifecycle.md) for the full building workflow.

---

## capture

Order an engineer to capture a target building.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `action` | `"capture"` | yes | |
| `unit_id` | int | yes | ID of the engineer unit |
| `target_id` | int | yes | ID of the target building to capture |

**Preconditions:** Engineer must exist, be alive, and be owned by the bot. Target must exist and be alive.

**Possible results:** `ok`, `invalid_unit`, `invalid_target`

```python
from airena_sdk import capture
engineer = next((u for u in obs.units if u.type_id == "e6"), None)
target = next((e for e in obs.enemies if e.type_id == "fact"), None)
if engineer and target:
    actions.append(capture(unit_id=engineer.id, target_id=target.id))
```

---

## noop

Do nothing. Placeholder action.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `action` | `"noop"` | yes | |

```python
from airena_sdk import noop
actions.append(noop())
```

---

## guard

Order a unit to escort/guard another unit, auto-engaging nearby threats.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `action` | `"guard"` | yes | |
| `unit_id` | int | yes | ID of the escorting unit |
| `target_unit_id` | int | yes | ID of the unit to guard |

**Preconditions:** Both units must exist, be alive, and be owned by the bot.

**Possible results:** `ok`, `invalid_unit`, `invalid_target`

```python
from airena_sdk import guard
actions.append(guard(unit_id=50, target_unit_id=42))
```

---

## sell

Sell a building for a partial credit refund.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `action` | `"sell"` | yes | |
| `building_id` | int | yes | ID of the building to sell |

**Preconditions:** Building must exist, be owned by the bot, and have the Sellable trait.

**Possible results:** `ok`, `invalid_unit`, `not_sellable`

**Refund:** The refund is a fraction of the original cost (see `sell_ratio` in ruleset). Typical ratio is 0.5 (50%).

```python
from airena_sdk import sell
actions.append(sell(building_id=15))
```

---

## repair

Toggle building repair on/off. Repair costs credits over time.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `action` | `"repair"` | yes | |
| `building_id` | int | yes | ID of the building to repair |

**Preconditions:** Building must exist, be owned by the bot, and have the RepairableBuilding trait.

**Possible results:** `ok`, `invalid_unit`, `not_repairable`

**Cost:** Repair costs a fraction of the build cost over time (see `repair_cost_factor` in ruleset). Check `unit.repairing` in observation to see if a building is currently being repaired.

```python
from airena_sdk import repair
actions.append(repair(building_id=15))
```

---

## stance

Set a unit's combat stance.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `action` | `"stance"` | yes | |
| `unit_id` | int | yes | ID of the unit |
| `stance` | string | yes | One of: `"attack_anything"`, `"defend"`, `"return_fire"`, `"hold_fire"` |

**Preconditions:** Unit must exist, be alive, and be owned by the bot.

**Possible results:** `ok`, `invalid_unit`, `invalid_stance`

**Stance meanings:**
- `attack_anything` — pursue and attack any enemy in range (default)
- `defend` — attack enemies near current position, return to post after
- `return_fire` — only fire back when attacked
- `hold_fire` — never auto-attack

```python
from airena_sdk import stance
actions.append(stance(unit_id=42, stance="hold_fire"))
```

---

## scatter

Order a unit to dodge to a random nearby position. Useful against splash damage.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `action` | `"scatter"` | yes | |
| `unit_id` | int | yes | ID of the unit to scatter |

**Preconditions:** Unit must exist, be alive, mobile, and be owned by the bot.

**Possible results:** `ok`, `invalid_unit`

```python
from airena_sdk import scatter
actions.append(scatter(unit_id=42))
```

---

## force_fire

Attack map coordinates (ground attack). Useful for area denial, attacking fog, or destroying terrain.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `action` | `"force_fire"` | yes | |
| `unit_id` | int | yes | ID of the attacking unit |
| `x` | int | yes | Target X coordinate |
| `y` | int | yes | Target Y coordinate |

**Preconditions:** Unit must exist, be alive, owned by the bot, and have a weapon.

**Possible results:** `ok`, `invalid_unit`, `out_of_map`

```python
from airena_sdk import force_fire
actions.append(force_fire(unit_id=42, x=100, y=150))
```

---

## patrol

Order a unit to patrol between waypoints, auto-engaging enemies along the route.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `action` | `"patrol"` | yes | |
| `unit_id` | int | yes | ID of the unit to patrol |
| `waypoints` | array | yes | List of `{"x": int, "y": int}` waypoints (1-8) |

**Preconditions:** Unit must exist, be alive, mobile, and be owned by the bot. 1-8 waypoints required.

**Possible results:** `ok`, `invalid_unit`, `invalid_waypoints`

```python
from airena_sdk import patrol
actions.append(patrol(unit_id=42, waypoints=[
    {"x": 100, "y": 100},
    {"x": 200, "y": 100},
    {"x": 200, "y": 200},
]))
```

---

## cancel_production

Cancel a queued production item. Partial refund based on progress.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `action` | `"cancel_production"` | yes | |
| `producer_id` | int | yes | ID of the production building |
| `item_type_id` | string | yes | Type ID of the item to cancel (e.g. `"powr"`, `"e1"`) |

**Preconditions:** Producer must exist and be owned by the bot. Item must be in production.

**Possible results:** `ok`, `producer_not_found`, `unknown_item`, `not_in_queue`

```python
from airena_sdk import cancel_production
actions.append(cancel_production(producer_id=10, item_type_id="powr"))
```

---

## Unsupported Actions

### attack_move

**Status: NOT SUPPORTED.** The `attack_move` action does not exist in the runtime. It was removed from the SDK in v0.2.0. Use `move` + `attack_unit` instead.

---

## Action Results / Feedback

After submitting actions, the results are returned in the **next tick's** observation at `observation.self.action_results`. Each result contains:

| Field | Type | Description |
|-------|------|-------------|
| `action` | string | The action type that was attempted |
| `status` | string | Result: `ok` or an error code |
| `unit_id` | int? | Unit ID from the original action (if applicable) |
| `detail` | string? | Additional detail about the failure |
| `placement_detail` | string? | Placement failure reason (for `place_building` only) |

Possible status values:
- `ok` - action succeeded
- `invalid_unit` - unit not found, dead, or not owned
- `invalid_target` - target unit not found or dead
- `invalid_placement` - terrain or base proximity check failed
- `insufficient_funds` - not enough credits
- `no_completed_item` - no completed building in queue
- `unknown_building` - building type not recognized
- `unknown_item` - item type not recognized
- `not_buildable` - item exists but prerequisites not met
- `queue_disabled` - production queue not active
- `producer_not_found` - producer building not found
- `not_a_harvester` - unit lacks Harvester trait
- `invalid_resource_target` - no resources at target cell
- `out_of_map` - coordinates outside map bounds
- `cannot_deploy` - unit cannot deploy in current state
- `not_sellable` - building lacks Sellable trait
- `not_repairable` - building lacks RepairableBuilding trait
- `invalid_stance` - stance value not recognized
- `invalid_waypoints` - waypoints missing or exceeds 1-8 limit
- `not_in_queue` - item not found in production queue
- `unknown_action` - action type not recognized

```python
# Check results from previous tick
for result in obs.self_info.action_results:
    if result.status != "ok":
        log(f"Action {result.action} failed: {result.status} ({result.detail or ''})")
```
