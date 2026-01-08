# Flagspawn (PD Fuel) — Technical Implementation Checklist

## Hammer Entity Reference

### Required Entity Names

| Entity Name | Type | Purpose |
|-------------|------|---------|
| `flagspawn_controller` | `logic_script` | Runs `flagspawn.nut` |
| `red_enemy_tap` | `prop_dynamic` | RED base tap (BLU interacts) |
| `blu_enemy_tap` | `prop_dynamic` | BLU base tap (RED interacts) |
| `red_fuel_digit` | `prop_dynamic` | Shows BLU Fuel at RED tap |
| `blu_fuel_digit` | `prop_dynamic` | Shows RED Fuel at BLU tap |
| `red_spawner` | `prop_dynamic` | RED team pickup spawner |
| `blu_spawner` | `prop_dynamic` | BLU team pickup spawner |
| `red_capture_zone` | `trigger_multiple` | RED team capture area |
| `blu_capture_zone` | `trigger_multiple` | BLU team capture area |
| `red_deepbase` | `info_target` | RED hotspot (Optional A) |
| `blu_deepbase` | `info_target` | BLU hotspot (Optional A) |
| `filter_red_team` | `filter_activator_tfteam` | TeamNum = 2 |
| `filter_blu_team` | `filter_activator_tfteam` | TeamNum = 3 |

---

## VScript Function Reference

### Core Functions

| Function | Description |
|----------|-------------|
| `InitializeFlagspawn()` | Initialize state, find entities, reset Fuel |
| `FlagspawnThink()` | Main loop (returns, glow updates, flicker) |

### Fuel Management

| Function | Parameters | Description |
|----------|------------|-------------|
| `AddFuel(team, amount)` | team: 2/3, amount: int | Add Fuel (clamped 0-100) |
| `GetFuel(team)` | team: 2/3 | Returns current Fuel |
| `UpdateFuelDisplay(team)` | team: 2/3 | Update digit prop |

### Tap Interaction

| Function | Parameters | Description |
|----------|------------|-------------|
| `OnEnemyTapTouched(tap, player)` | entities | Handle tap interaction |
| `Callback_RedTapTouched()` | — | Hammer output callback |
| `Callback_BluTapTouched()` | — | Hammer output callback |

### Pickup Management

| Function | Parameters | Description |
|----------|------------|-------------|
| `SpawnPickupForPlayer(player, value, team)` | — | Spawn carried pickup |
| `SpawnDroppedPickup(origin, value, team, vel)` | — | Spawn dropped pickup |
| `OnPickupTouched(pickup, player)` | — | Handle pickup collection |
| `ProcessPickupReturns()` | — | Check/process 60s returns |

### Carrying System

| Function | Parameters | Description |
|----------|------------|-------------|
| `AddCarriedPoints(player, amount)` | — | Add to player's carry |
| `GetCarriedPoints(player)` | — | Get player's carry |
| `SetCarriedPoints(player, amount)` | — | Set player's carry |

### Anti-Hoard

| Function | Parameters | Description |
|----------|------------|-------------|
| `OnPlayerDamaged(player, damage)` | — | Piñata spill logic |
| `OnPlayerDeath(player)` | — | Death drop (5 chunks) |

### Glow Budget

| Function | Parameters | Description |
|----------|------------|-------------|
| `UpdateGlowBudget()` | — | Recalculate Top-K glow |
| `SelectTopKGlow(pickups, team)` | — | Sort and apply glow |
| `EnablePickupGlow(data)` | pickup data | Create tf_glow |
| `DisablePickupGlow(data)` | pickup data | Remove tf_glow |

### Optional Features

| Function | Parameters | Description |
|----------|------------|-------------|
| `UpdatePickupFlicker(data)` | pickup data | Optional B: Flicker |
| `UpdatePickupTimer(data)` | pickup data | Optional C: Timer text |
| `DisablePickupTimer(data)` | pickup data | Remove timer text |

---

## State Tables

### FlagspawnState

```squirrel
FlagspawnState <- {
    Fuel = { [2] = 0, [3] = 0 },           // Per-team fuel (0-100)
    DroppedPickups = [],                    // Array of pickup data
    DamageAccum = {},                       // Per-player damage accumulator
    Entities = { ... },                     // Entity references
    LastGlowUpdate = 0.0,                   // Timestamp
    Initialized = false
}
```

### Pickup Data Structure

```squirrel
{
    ent = <entity>,              // The pickup entity
    value = <int>,               // Point value
    beneficiary_team = <2|3>,    // Team that gets Fuel on return
    spawn_time = <float>,        // Time() when spawned
    expiry_time = <float>,       // Time() when it returns
    has_glow = <bool>,           // Currently glowing?
    glow_ent = <entity>,         // tf_glow entity (or null)
    timer_ent = <entity>,        // point_worldtext (or null)
    entindex = <int>             // For stable sorting
}
```

---

## Configuration Table

```squirrel
FLAGSPAWN_CONFIG <- {
    ROUND_TIME              = 300.0,    // 5:00
    TAP_TIME_BONUS          = 3.0,      // +3s per tap
    RETURN_DELAY            = 60.0,     // 60s return
    FUEL_MAX                = 100,
    FUEL_MIN                = 0,
    PINATA_DAMAGE_THRESHOLD = 15,
    PINATA_DIVISOR          = 5,
    DEATH_MAX_CHUNKS        = 5,
    GLOW_TOP_K              = 5,
    GLOW_UPDATE_INTERVAL    = 0.5,
    HOTSPOT_ENABLED         = true,     // Optional A
    FLICKER_ENABLED         = true,     // Optional B
    FLICKER_THRESHOLD       = 10.0,
    FLICKER_RATE            = 0.125,    // 8 Hz
    RETURN_TIMER_ENABLED    = true,     // Optional C
    CLASS_BONUS             = { ... }
}
```

---

## Hammer Entity Outputs

### Tap Triggers

```
red_tap_trigger:
  OnStartTouch -> flagspawn_controller -> RunScriptCode -> Callback_RedTapTouched()

blu_tap_trigger:
  OnStartTouch -> flagspawn_controller -> RunScriptCode -> Callback_BluTapTouched()
```

### Capture Zones

```
red_capture_zone:
  OnStartTouch -> flagspawn_controller -> RunScriptCode -> Callback_PointsCaptured()

blu_capture_zone:
  OnStartTouch -> flagspawn_controller -> RunScriptCode -> Callback_PointsCaptured()
```

### Game Events

```
event_player_hurt (logic_eventlistener):
  OnEventFired -> flagspawn_controller -> RunScriptCode -> OnGameEvent_player_hurt(event_data)

event_player_death (logic_eventlistener):
  OnEventFired -> flagspawn_controller -> RunScriptCode -> OnGameEvent_player_death(event_data)
```

---

## Testing Checklist

- [ ] Map compiles without errors
- [ ] VScript loads on map spawn
- [ ] RED can touch BLU tap, BLU can touch RED tap
- [ ] Fuel digits update correctly
- [ ] Timer extends on tap interaction
- [ ] Pickups spawn with correct values
- [ ] Piñata triggers at 15 damage
- [ ] Death drops 5 chunks + remainder
- [ ] Top-K glow selection works
- [ ] Glow flickers below 10s remaining
- [ ] Return timer text appears
- [ ] Pickups return after 60s and add Fuel
- [ ] Capture zone scores points and adds Fuel
- [ ] Round ends when timer hits 0