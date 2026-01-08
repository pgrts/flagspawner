# Flagspawn (PD Fuel) — Final Plan

A hybrid TF2 game mode combining **Player Destruction** mechanics with **Fuel-based objective scaling**.

---

## Terminology

| Term | Definition |
|------|------------|
| **Fuel** | Team-owned resource (0–100) determining giant pickup size at your Spawner |
| **Enemy Tap** | Objective in enemy base — interact to generate points and Fuel for your team |
| **Spawner** | Your team's home location where Fuel converts into larger pickups |

> The enemy base object fuels your team. Captures and returns convert carried points into Fuel.

---

## Core Mode

- **Base:** Player Destruction (HUD, carrying, merging, scoring, timer)
- **Round Timer:** Starts at 5:00
- **Win Condition:** Team with more captured points when timer hits 0
- **Timer Extension:** +3 seconds per successful Enemy Tap interaction (tunable)
- **Return Timer:** Dropped pickups return/reset after 60 seconds

---

## Map Objects & Visuals

### Enemy Tap (per team base)

| Component | Description |
|-----------|-------------|
| Tap Prop | `prop_dynamic` studiomodel with glow outline |
| Digit Display | Centered `prop_dynamic` showing Fuel of the *stealing* team |
| Visibility | `tf_glow` outline visible through walls to both teams |

**Example:**
- Tap in BLU base displays **RED Fuel**
- Tap in RED base displays **BLU Fuel**

### Spawner

Each team has a home Spawner that generates pickups sized by that team's Fuel.

---

## Fuel Rules

### Fuel Meter
- `Fuel[RED]` and `Fuel[BLU]` per team
- Clamped: `0 ≤ Fuel ≤ 100`
- Overflow beyond 100 is discarded

### How Fuel Is Gained

Fuel is always credited to the **beneficiary team** (the team the points belong to):

| Action | Effect |
|--------|--------|
| **Enemy Tap** | Spawns pickup for attacker; Fuel added to attacker's team |
| **Capture** | PD score increases; captured value added to capturing team's Fuel |
| **Return** | Dropped pickup's value added back to its tagged beneficiary team's Fuel |

---

## Spawning Points

### Enemy Tap Pull
- Always spawns a pickup for the attacker
- Base value: **1 point**
- Optional class bonus applies ("1 or bonus" rule)
- Pickup behaves like standard PD points (carry, merge, drop)

### Fuel Usage
- Fuel does **not** gate spawning
- Fuel determines how large the next giant pickup can be at the Spawner
- Exact payout curve is tunable; Fuel is the scaling input

---

## Anti-Merge / Anti-Hoard Mechanics

### Piñata on Damage

While carrying points, every **15 damage** taken triggers a spill:

1. Exactly **one** dropped pickup spawned and launched away
2. Chunk math:
   - Let `n` = carried value
   - `P = ceil(n / 5)`
   - Clamp so carrier keeps at least 1: `P = min(P, n - 1)`
3. Carrier loses `P`, one `P`-value pickup spawns

### On Death

If a carrier dies with `n` points:

```
base = floor(n / 5)
rem  = n % 5
```

Spawn:
- Up to **5 pickups** worth `base` each (if `base > 0`)
- Plus **1 remainder** pickup worth `rem` (if `rem > 0`)
- Burst in circular pattern

This spreads value while strictly limiting entity count.

---

## Through-Walls Readability (Glow Budget)

### Base Glow Rules
- Enemy Tap digits: **always glow** through walls
- Carried flags: **always glow**
- Dropped flags: **selective glow**

### Glow Selection (Top-K)

Every **0.5 seconds** (and immediately on spawn/capture/return/value-change):

1. Select **Top K** dropped pickups per team by point value (default `K = 5` per team)
2. Sorting:
   - `value` (descending)
   - `distance to team hotspot` (ascending, squared) — *Optional A*
   - `entindex / age` (stable tie-break)
3. Only selected pickups receive through-walls glow

---

## Optional Features (All Enabled)

### Optional A: Static Hotspot Bias

- One `info_target` per team: `red_deepbase`, `blu_deepbase`
- Glow tie-breaker becomes:
  1. `value` (descending)
  2. `distance to team hotspot` (ascending, squared)
  3. `entindex / age`

### Optional B: Return-Time Flicker

- Track remaining return time for dropped pickups
- When below threshold (e.g. **10 seconds**): glow flickers
- Applies only to **Top-K** pickups

### Optional C: Visible Return Timer

- Display remaining seconds near important pickups using:
  - Circular CTF-style timer prop, **or**
  - `point_worldtext` counting down
- Applies only to **Top-K** pickups

---

## Design Intent

1. **Enemy bases generate Fuel for your team**
2. **Carrying points is powerful but unstable under pressure**
3. **Damage and death redistribute value without flooding entities**
4. **Fuel converts gameplay success into bigger future plays**
5. **The map can fill with flags while only the most meaningful ones demand attention**

---

## Quick Reference

| Parameter | Default | Notes |
|-----------|---------|-------|
| Round Timer | 5:00 | |
| Timer Extension | +3s | Per Enemy Tap interaction |
| Return Delay | 60s | Dropped pickups |
| Fuel Cap | 100 | Per team |
| Piñata Threshold | 15 dmg | Triggers spill |
| Glow Budget (K) | 5 | Per team |
| Flicker Threshold | 10s | Before return |
