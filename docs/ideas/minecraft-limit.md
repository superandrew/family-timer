# Minecraft limit inside FamilyTimer

Replace minertimer: 45 minutes of Minecraft on weekdays, 60 at the weekend, inside
FamilyTimer, which already recognises Minecraft (also under Lunar Client, Prism, MultiMC).

- Config: `MINECRAFT_LIMIT`, `WEEKEND_MINECRAFT_LIMIT`.
- Core: Minecraft seconds today vs limit: warnings at 5 and 1 minute, then close.
- Agent closes the game after the warnings; the daemon (root) kills the `java` process if it
  is still alive a minute later, from the process list, not trusting the agent.
- `/status` shows the Minecraft time left.

Open questions for the parents:
- Does `/extra` also extend Minecraft, or a separate `/extra 15m minecraft`?
- Is Minecraft blocked during `/studio`?
- Count only active foreground time (FamilyTimer) or open time (minertimer)?
- Holidays: weekend only, a list of dates, or by hand with `/extra`?
