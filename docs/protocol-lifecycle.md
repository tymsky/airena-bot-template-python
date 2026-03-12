# Protocol Lifecycle (openra.v1)

## Message Flow

```
Runner (adapter)              Bot (your code)
     |                            |
     |--- hello ----------------->|   Match config, limits, protocol
     |<-- ready ------------------|   Bot confirms protocol support
     |                            |
     |--- ruleset --------------->|   Static game data (unit types, weapons)
     |                            |
     |--- tick (tick=0) --------->|   First observation
     |<-- actions (tick=0) -------|   Bot's commands
     |                            |
     |--- tick (tick=N) --------->|   Observation every decision_interval_ticks
     |<-- actions (tick=N) -------|   Bot's commands
     |          ...               |
     |                            |
     |--- game_over ------------->|   Match result (winner, reason)
     |                            |
```

## Messages in Detail

### 1. hello (Runner -> Bot)

Sent once at match start. Contains match configuration and resource limits.

```json
{
  "type": "hello",
  "protocol": "openra.v1",
  "match": {
    "match_id": "eval-abc123",
    "seed": 42,
    "map": "a-nuclear-winter",
    "ruleset": "standard"
  },
  "limits": {
    "decision_interval_ticks": 5,
    "action_budget_per_second": 60,
    "max_actions_per_tick": 10,
    "bot_response_timeout_ms": 2000
  }
}
```

**Bot must respond with `ready`.** The SDK's `BotRunner` handles this automatically.

### 2. ready (Bot -> Runner)

Bot acknowledges the protocol.

```json
{
  "type": "ready",
  "protocol": "openra.v1"
}
```

**Handled automatically by SDK.** You don't need to implement this unless you override the default hello handler.

### 3. ruleset (Runner -> Bot)

Sent once after handshake, before the first tick. Contains static game data: all unit types and weapons.

```json
{
  "type": "ruleset",
  "protocol": "openra.v1",
  "mod_id": "ra",
  "ruleset_id": "standard",
  "ruleset_version": "...",
  "unit_types": [...],
  "weapons": [...],
  "terrain": { "width": 128, "height": 128, "passability": "...", "terrain_types": "..." }
}
```

**Recommended:** Parse and store unit/weapon data in `state` for later reference.

### 4. tick (Runner -> Bot)

Sent every `decision_interval_ticks` game ticks. Contains the bot's current observation of the world.

```json
{
  "type": "tick",
  "tick": 150,
  "observation": {
    "self": { ... },
    "units": [ ... ],
    "visible_enemies": [ ... ],
    "nearby_resources": [ ... ],
    "map": { "width": 128, "height": 128 },
    "fow_enforced": true
  }
}
```

**Bot must respond with `actions`.** See [observation-reference.md](observation-reference.md) for field details.

### 5. actions (Bot -> Runner)

Bot's response to a tick. The `tick` field **must match** the tick being responded to.

```json
{
  "type": "actions",
  "tick": 150,
  "actions": [
    {"action": "move", "unit_id": 42, "x": 120, "y": 210},
    {"action": "queue_production", "producer_id": 10, "item_type_id": "e1", "count": 1}
  ]
}
```

An empty actions array is valid (bot does nothing this tick).

### 6. game_over (Runner -> Bot)

Sent when the match ends.

```json
{
  "type": "game_over",
  "result": {
    "winner": 1,
    "reason": "annihilation",
    "duration_ticks": 6000
  }
}
```

Possible reasons: `annihilation`, `timeout` (tick limit reached), `bot_crashed`, `surrender`.

---

## Timeouts and Limits

### Response timeout

Each tick must be responded to within `bot_response_timeout_ms` (typically 2000ms).

- **If you time out:** Your response is treated as empty actions (no-op). The game continues. A `timeout_count` counter is incremented.
- **No notification:** The bot does not learn it timed out.

### Handshake timeout

The `ready` response must arrive within `2 * bot_response_timeout_ms`.

- **If you time out:** The match is aborted.

### Action limits

Two layers of rate limiting:

1. **Per-tick cap:** `max_actions_per_tick` (default 10). Actions beyond this limit are dropped (from the end of the array).
2. **Per-second budget:** `action_budget_per_second` (default 60). Total actions across all ticks in a 1-second window.

If you exceed limits, excess actions are silently dropped and a `budget_infractions` counter is incremented.

### Tick mismatch

If the `tick` field in your `actions` response doesn't match the tick you're responding to, the entire response is discarded.

---

## Error Handling

### Invalid JSON

If the bot sends malformed JSON, the line is logged and treated as a no-op. The `invalid_json_count` counter is incremented.

### Bot crash

If the bot process exits (broken pipe, non-zero exit code):
- The match ends immediately
- `reason` is set to `"bot_crashed"` in the result
- The bot's exit code is recorded

### Unknown action types

Unknown action types in the `actions` array are silently ignored.

---

## Transport

- **Channel:** JSON Lines over STDIN (input) / STDOUT (output)
- **Encoding:** UTF-8
- **Framing:** One JSON object per line, terminated by `\n`
- **Logging:** Use STDERR for debug output (the `log()` function from SDK does this)

**Important:** Never write non-JSON data to STDOUT. Use `log()` (which writes to STDERR) for any debug output.

---

## SDK BotRunner Pattern

The SDK provides `BotRunner` which handles the message loop:

```python
from airena_sdk import BotRunner, log, send, Observation, Ruleset

bot = BotRunner()

@bot.on("ruleset")
def handle_ruleset(msg, state):
    state["ruleset"] = Ruleset.from_msg(msg)

@bot.on("tick")
def handle_tick(msg, state):
    obs = Observation.from_tick(msg)
    actions = []
    # ... strategy logic ...
    send({"type": "actions", "tick": obs.tick, "actions": actions})

@bot.on("game_over")
def handle_game_over(msg, state):
    log(f"Game over: {msg['result']}")

if __name__ == "__main__":
    bot.run()
```
