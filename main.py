"""AiRENA bot template — entry point.

Edit this file to implement your bot strategy.
See docs/ for action reference, observation fields, and protocol lifecycle.
"""

from airena_sdk import BotRunner, log, send
from airena_sdk import move, attack_unit, deploy, harvest, queue_production, noop
from airena_sdk import Observation
from airena_sdk.mods import ra

bot = BotRunner()


@bot.on("ruleset")
def handle_ruleset(msg: dict, state: dict) -> None:
    """Called once before the first tick with static game data (unit types, weapons, tech tree)."""
    log("Ruleset received")


@bot.on("tick")
def handle_tick(msg: dict, state: dict) -> None:
    """Called every decision interval with the current game observation.

    Build a list of actions and send it via send(). See docs/action-reference.md for all actions.
    """
    obs = Observation.from_tick(msg)
    actions: list[dict] = []

    # Example: deploy MCV on first tick
    if obs.tick == 0:
        for u in obs.units:
            if u.type_id == ra.Units.MCV and u.can_deploy:
                actions.append(deploy(u.id))
                log(f"Deploying MCV {u.id}")
                break

    # TODO: implement your strategy here
    #
    # Useful starting points:
    #   conyard = next((u for u in obs.units if u.type_id == ra.Buildings.CONSTRUCTION_YARD), None)
    #   actions.append(queue_production(producer_id=conyard.id, item_type_id=ra.Buildings.POWER_PLANT))
    #   actions.append(move(unit_id, x, y))
    #   actions.append(attack_unit(attacker_id, target_id))
    #   resources = obs.nearby_resources
    #   actions.append(harvest(harvester_id, resources[0].x, resources[0].y))
    #   actions.append(noop())
    #
    # See docs/building-lifecycle.md for the full build→place flow.

    send({"type": "actions", "tick": obs.tick, "actions": actions})


@bot.on("game_over")
def handle_game_over(msg: dict, state: dict) -> None:
    """Called when the match ends."""
    result = msg.get("result", {})
    log(f"Game over — winner: {result.get('winner')}, reason: {result.get('reason')}")


if __name__ == "__main__":
    bot.run(initial_state={})
