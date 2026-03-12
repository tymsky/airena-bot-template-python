# Building Lifecycle Guide

Building construction in OpenRA is a **two-step process**: queue production, then place the building. This guide explains the full workflow.

## Overview

```
1. queue_production(conyard_id, "powr")     -> starts building
2. wait for done=True in production queue   -> building ready
3. place_building("powr", x, y)            -> places on map
4. check action_results next tick           -> confirm success
```

## Step-by-Step

### Step 1: Find your Construction Yard

The Construction Yard (`fact`) is the producer for buildings. Find it in your units:

```python
conyard = next((u for u in obs.units if u.type_id == "fact"), None)
if not conyard:
    log("No construction yard!")
    return
```

### Step 2: Check what you can build

Use `self_info.buildable_in()` or inspect the Building queue directly:

```python
available = obs.self_info.buildable_in("Building")
# e.g. ("powr", "proc", "tent", "weap", ...)
```

### Step 3: Queue production

```python
from airena_sdk import queue_production

if "powr" in available:
    actions.append(queue_production(producer_id=conyard.id, item_type_id="powr"))
```

### Step 4: Wait for completion

Each tick, check the production queue for progress:

```python
for item in obs.self_info.build_queue:
    if item.item_type_id == "powr":
        log(f"Power plant: {item.progress:.0%} done={item.done}")
```

Or use the convenience fields:

```python
if obs.self_info.placement_pending and obs.self_info.placement_type_id == "powr":
    # Building is ready to place!
    pass
```

### Step 5: Place the building

Once `done=True` (or `placement_pending=True`), place it:

```python
from airena_sdk import place_building

if obs.self_info.placement_pending and obs.self_info.placement_type_id == "powr":
    actions.append(place_building(building_type_id="powr", x=base_x + 3, y=base_y))
```

### Step 6: Check the result

Next tick, check `action_results`:

```python
for result in obs.self_info.action_results:
    if result.action == "place_building":
        if result.status == "ok":
            log("Building placed successfully!")
        elif result.status == "invalid_placement":
            log("Bad location, try different coordinates")
        elif result.status == "no_completed_item":
            log("Building not ready yet")
```

## Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `no_completed_item` | Called place_building before production finished | Wait for `done=True` or `placement_pending=True` |
| `invalid_placement` | Location blocked by terrain, other buildings, or too far from base | Try different coordinates near your base |
| `unknown_building` | Wrong `building_type_id` | Check `buildable_in("Building")` for valid type IDs |
| `insufficient_funds` | Not enough credits for `queue_production` | Wait for more income or build cheaper items |
| `not_buildable` | Prerequisites not met | Check `buildable_in("Building")` — you may need other buildings first |
| `queue_disabled` | No Construction Yard | Build/deploy a CY first |
| `producer_not_found` | Wrong `producer_id` | Use the actual Construction Yard's `id` from observation |

## Complete Example

```python
from airena_sdk import BotRunner, log, send, Observation
from airena_sdk import queue_production, place_building, deploy

bot = BotRunner()

@bot.on("tick")
def handle_tick(msg, state):
    obs = Observation.from_tick(msg)
    actions = []

    # Check action results from previous tick
    for r in obs.self_info.action_results:
        if r.status != "ok":
            log(f"[{r.action}] failed: {r.status}")

    # Phase 1: Deploy MCV if we have one
    mcv = next((u for u in obs.units if u.type_id == "mcv" and u.can_deploy), None)
    if mcv:
        actions.append(deploy(mcv.id))
        send({"type": "actions", "tick": obs.tick, "actions": actions})
        return

    # Find construction yard
    conyard = next((u for u in obs.units if u.type_id == "fact"), None)
    if not conyard:
        send({"type": "actions", "tick": obs.tick, "actions": actions})
        return

    # Phase 2: Place building if ready
    if obs.self_info.placement_pending:
        building_type = obs.self_info.placement_type_id
        # Place near construction yard
        cx, cy = conyard.x, conyard.y
        actions.append(place_building(building_type_id=building_type, x=cx + 3, y=cy))
        send({"type": "actions", "tick": obs.tick, "actions": actions})
        return

    # Phase 3: Queue next building if nothing in production
    queue = obs.self_info.queue_for("Building")
    if queue and queue.enabled and queue.queue_length == 0:
        available = queue.buildable_items
        # Priority: power -> refinery -> barracks
        for target in ("powr", "proc", "tent"):
            if target in available:
                actions.append(queue_production(producer_id=conyard.id, item_type_id=target))
                break

    send({"type": "actions", "tick": obs.tick, "actions": actions})

if __name__ == "__main__":
    bot.run()
```

## Building Order Tips

Typical early game build order:
1. Deploy MCV -> Construction Yard (`fact`)
2. Build Power Plant (`powr`) - provides power
3. Build Refinery (`proc`) - provides income + free harvester
4. Build Barracks (`tent`) - enables infantry production
5. Build more Power Plants as needed (watch `resources.power` going negative)
6. Build War Factory (`weap`) - enables vehicle production

**Power matters:** When `obs.self_info.resources.power` is negative, production slows down significantly. Always ensure positive power before queuing expensive items.
