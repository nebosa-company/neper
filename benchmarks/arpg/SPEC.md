# ARPG engine core -- the benchmark program

A headless Action-RPG engine core, implemented independently in Neper, Rust, Go,
JavaScript and TypeScript. Every implementation runs the same scripted input trace for
the same number of ticks and prints one checksum. **The five checksums must match**;
that is the correctness oracle, and it is what makes the token comparison honest -- five
programs that provably do the same work.

No implementation may use a third-party library. Rendering, audio and sockets are out of
scope on purpose: Neper's `e.ui.*`, `e.gfx.*` and `e.net.*` are all still `planned`, so
comparing them would measure which ecosystem is older, not which language is denser. What
is here is the part that is real engine logic in any engine: simulation, collision,
animation state, combat, dialog, UI layout, particles, and the serialization half of
netcode.

## Determinism rules

These exist so five languages agree bit for bit.

- **All arithmetic is integer.** No floating point anywhere in the simulation.
- **Fixed point is Q8**: a world unit is 256. `FX(n) = n * 256`.
- `fixmul(a, b) = floor(a * b / 256)`. On i64 that is `(a * b) >> 8`; in JavaScript it is
  `Math.floor(a * b / 256)`. These agree for negatives because arithmetic shift right is
  floor division. Every product stays below 2^40, well inside JavaScript's exact integer
  range, so plain `number` is exact.
- **Random numbers are xorshift32** over an unsigned 32-bit word, seeded `0x2545F491`:

      x ^= x << 13;  x ^= x >> 17;  x ^= x << 5      (all modulo 2^32, logical shifts)

  `rand_range(lo, hi)` returns `lo + (next() % (hi - lo))` with `hi > lo`.
- **Checksum is FNV-1a, 32-bit**, seeded `0x811C9DC5`, multiplied by `0x01000193` modulo
  2^32, fed one byte at a time, low byte first for multi-byte values.

## World

- Tilemap `64 x 64`, one byte per tile. Tile `1` is solid, `0` is open. The map is
  generated at startup from the PRNG: a tile is solid when `rand_range(0, 100) < 18`, and
  the border ring is always solid. Generation happens before anything else draws from the
  PRNG, so every implementation consumes the stream in the same order.
- Gravity does not apply; this is top-down. Movement is per-axis with swept AABB
  resolution: move on X, resolve, then move on Y, resolve.

## Entities

A fixed array of 256 slots. Each entity has: `alive`, `kind` (0 player, 1 melee enemy,
2 ranged enemy, 3 projectile, 4 pickup), `x`, `y`, `vx`, `vy` (Q8), `half_w`, `half_h`
(Q8), `hp`, `max_hp`, `team`, `anim_state`, `anim_frame`, `anim_timer`, `cooldown`,
`invuln`, `target`, `seed_tag`.

Spawn order at startup: the player at tile (8, 8), then 24 enemies at PRNG-chosen open
tiles (alternating melee and ranged), then 12 pickups. Ids are assigned lowest free slot
first.

## Systems, run in this exact order each tick

1. **Input** -- the trace supplies a bitmask per tick: 1 left, 2 right, 4 up, 8 down,
   16 attack, 32 interact. The player's velocity is set to +/- `FX(1)*3/2` per axis.
2. **AI** -- a melee enemy within 12 tiles of the player steers toward it at `FX(1)`; a
   ranged enemy holds at 6 tiles and fires a projectile when its cooldown reaches 0.
   Outside range an enemy wanders using the PRNG every 32 ticks.
3. **Physics** -- integrate velocity, swept AABB against the tilemap per axis.
4. **Combat** -- overlapping entities of different teams exchange damage: melee contact
   does `4 + rand_range(0, 3)` when the attack bit is set and the cooldown is 0;
   a projectile does 7 and dies. Damage is ignored while `invuln > 0`; a hit sets
   `invuln = 30`. At `hp <= 0` an entity dies and, if it is an enemy, spawns a pickup.
5. **Animation** -- each entity advances a state machine: idle (4 frames, 8 ticks each),
   run (6 frames, 5 ticks), attack (3 frames, 4 ticks, returns to idle), hurt (2 frames,
   6 ticks). Velocity and the attack bit select the state; a state change resets frame
   and timer.
6. **Particles** -- a pool of 512. A hit spawns 8, a death 24, each with a PRNG velocity
   and a 20-40 tick life. Particles integrate and expire; no collision.
7. **Dialog** -- the interact bit near a pickup opens a branching dialog tree. A node has
   text, a condition over flags, and up to 3 choices; choosing advances and may set a
   flag or grant an item. The trace's interact bit drives choice selection.
8. **UI** -- a widget tree (root, health bar, hotbar of 8 slots, dialog panel, inventory
   grid 4x6) is laid out each tick with a two-pass solve (measure, then arrange) into
   integer rectangles, then hit-tested against a cursor the trace moves.
9. **Netcode** -- every 4th tick the world is serialized to a snapshot byte buffer, delta
   encoded against the previous snapshot, and applied to a shadow world through an
   in-memory transport with a 6-tick delay. The shadow world runs input prediction and
   reconciles when a snapshot arrives; a divergence between predicted and authoritative
   state is counted.

## Output

After `TICKS` ticks (default 3600) print exactly one line:

    <checksum> <alive> <deaths> <particles> <dialog_flags> <ui_hits> <net_divergences>

all decimal, space separated. The checksum accumulates, each tick, every entity's
`x, y, hp, anim_state, anim_frame` and the particle count, in slot order.
