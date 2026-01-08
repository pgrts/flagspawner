// ============================================================
// flagspawn_pd_fuel_fs_gm1.nut
// ------------------------------------------------------------
// Matches fs_gm1.vmf TODAY (no renames required):
// - logic_script name: "scripter" calling flagspawn.Init()
// - triggers call:
//     flagspawn.OnSpawnerTouch(activator, 2/3)  // enemy-base "tap"
//     flagspawn.OnCaptureTouch(activator, 2/3)  // deposit
//
// Adds PD Fuel:
// - Fuel per team (0..100)
// - OnSpawnerTouch: dispense pooled PD flag + add Fuel + add round time
// - OnCaptureTouch: if carrying flag -> bank its PointsValue into Fuel + reset gate
//
// Digit props are optional; if missing, script skips display updates.
//
// ============================================================

local rt = getroottable();
if (!("flagspawn" in rt)) rt["flagspawn"] <- {};
::flagspawn <- rt["flagspawn"];

// ------------------------------------------------------------
// Constants / Config
// ------------------------------------------------------------
::flagspawn.TEAM_RED <- 2;
::flagspawn.TEAM_BLU <- 3;

::flagspawn.DEBUG <- true;

::flagspawn.POOL_PER_TEAM <- 25;
::flagspawn.POOL_NAME_RED_PREFIX <- "fs_pool_red_";
::flagspawn.POOL_NAME_BLU_PREFIX <- "fs_pool_blu_";
::flagspawn.POOL_HIDE_ORIGIN <- Vector(0, 0, -8000);

// One-per-life gate (resets on spawn AND on capture)
::flagspawn.SPAWNER_TOUCH_COOLDOWN <- 0.35;
::flagspawn.PICKUP_RETRY_COUNT <- 12;
::flagspawn.PICKUP_RETRY_INTERVAL <- 0.10;

// Fuel
::flagspawn.FUEL_MIN <- 0;
::flagspawn.FUEL_MAX <- 100;
::flagspawn.Fuel <- { [::flagspawn.TEAM_RED] = 0, [::flagspawn.TEAM_BLU] = 0 };

// Tap bonus time
::flagspawn.TAP_TIME_BONUS <- 3.0;

// Digit display (optional entities you will add later)
::flagspawn.RED_FUEL_DIGIT_NAME <- "red_fuel_digit"; // shows BLU fuel at RED base
::flagspawn.BLU_FUEL_DIGIT_NAME <- "blu_fuel_digit"; // shows RED fuel at BLU base

// Round timer (fs_gm1.vmf uses "round_timer")
::flagspawn.ROUND_TIMER_NAME <- "round_timer";

// ------------------------------------------------------------
// Logging helpers
// ------------------------------------------------------------
::flagspawn.Log <- function(s) { printl("[flagspawn] " + s); };

::flagspawn._SafeName <- function(ent) {
    if (!ent) return "null";
    local nm = "";
    try { nm = ent.GetName(); } catch(e) { nm = ""; }
    if (nm == null || nm == "") {
        try { nm = ent.GetClassname() + "#" + ent.entindex(); } catch(e2) { nm = "ent"; }
    }
    return nm;
};

::flagspawn._GetTeamNum <- function(ent) {
    if (!ent) return 0;
    local t = 0;
    try { t = ent.GetTeam(); return t; } catch(e) {}
    try { t = NetProps.GetPropInt(ent, "m_iTeamNum"); } catch(e2) { t = 0; }
    return t;
};

::flagspawn._OppTeam <- function(team) {
    if (team == ::flagspawn.TEAM_RED) return ::flagspawn.TEAM_BLU;
    if (team == ::flagspawn.TEAM_BLU) return ::flagspawn.TEAM_RED;
    return 0;
};

::flagspawn._FindByName <- function(name) {
    local f = null;
    try { f = Entities.FindByName(null, name); } catch(e) { f = null; }
    return f;
};

// ------------------------------------------------------------
// Class bonus (keep your current tuning)
// ------------------------------------------------------------
::flagspawn._GetPlayerClassNum <- function(player) {
    if (!player) return 0;
    try { return NetProps.GetPropInt(player, "m_PlayerClass.m_iClass"); } catch(e) {}
    return 0;
};

::flagspawn.GetClassBonus <- function(player) {
    local cls = ::flagspawn._GetPlayerClassNum(player);
    switch (cls) {
        case 6: return 5; // Heavy
        case 2: return 3; // Sniper
        case 3: return 2; // Soldier
        default: return 1;
    }
};

// ------------------------------------------------------------
// Fuel helpers
// ------------------------------------------------------------
::flagspawn._ClampFuel <- function(v) {
    if (v < ::flagspawn.FUEL_MIN) return ::flagspawn.FUEL_MIN;
    if (v > ::flagspawn.FUEL_MAX) return ::flagspawn.FUEL_MAX;
    return v;
};

::flagspawn.AddFuel <- function(team, amount) {
    if (!(team in ::flagspawn.Fuel)) return;
    local oldV = ::flagspawn.Fuel[team];
    local newV = ::flagspawn._ClampFuel(oldV + amount);
    ::flagspawn.Fuel[team] = newV;
    if (newV != oldV) {
        ::flagspawn.UpdateFuelDisplay(team);
        if (::flagspawn.DEBUG) ::flagspawn.Log("Fuel " + team + ": " + oldV + " -> " + newV);
    }
};

::flagspawn.GetFuel <- function(team) {
    if (!(team in ::flagspawn.Fuel)) return 0;
    return ::flagspawn.Fuel[team];
};

// Fuel is shown at ENEMY base digits:
// - RED fuel shown at BLU base => blu_fuel_digit
// - BLU fuel shown at RED base => red_fuel_digit
::flagspawn.UpdateFuelDisplay <- function(team) {
    local ent = null;
    if (team == ::flagspawn.TEAM_RED) ent = ::flagspawn._FindByName(::flagspawn.BLU_FUEL_DIGIT_NAME);
    else if (team == ::flagspawn.TEAM_BLU) ent = ::flagspawn._FindByName(::flagspawn.RED_FUEL_DIGIT_NAME);

    if (!ent || !ent.IsValid()) return;

    local fuel = ::flagspawn.GetFuel(team);

    // Placeholder: try common inputs. Your digit model will decide final approach.
    try { EntFireByHandle(ent, "SetBodyGroup", fuel.tostring(), 0, null, null); } catch(e) {}
    try { EntFireByHandle(ent, "Skin", fuel.tostring(), 0, null, null); } catch(e2) {}
};

// Add time to the team_round_timer (best-effort)
::flagspawn.AddRoundTime <- function(seconds) {
    local t = ::flagspawn._FindByName(::flagspawn.ROUND_TIMER_NAME);
    if (!t || !t.IsValid()) return;
    // Many timers support AddTime; if it doesn't, this just does nothing.
    try { EntFireByHandle(t, "AddTime", seconds.tostring(), 0, null, null); } catch(e) {}
};

// ------------------------------------------------------------
// PD PointsValue on item_teamflag
// ------------------------------------------------------------
::flagspawn._SetFlagPointsValue <- function(flag, v) {
    if (!flag) return;
    try { flag.ValidateScriptScope(); flag.GetScriptScope().fs_value <- v; } catch(e) {}
    try { flag.__KeyValueFromInt("PointsValue", v); } catch(e2) {}
    try { flag.__KeyValueFromInt("pointsvalue", v); } catch(e3) {}
};

::flagspawn._GetFlagPointsValue <- function(flag) {
    if (!flag) return 0;
    try {
        flag.ValidateScriptScope();
        local ss = flag.GetScriptScope();
        if ("fs_value" in ss) return ss.fs_value.tointeger();
    } catch(e) {}
    return 1;
};

// ------------------------------------------------------------
// Carry detection
// ------------------------------------------------------------
::flagspawn._FlagOwner <- function(flag) {
    if (!flag) return null;
    local owner = null;
    try { owner = NetProps.GetPropEntity(flag, "m_hOwnerEntity"); } catch(e) { owner = null; }
    return owner;
};

::flagspawn._IsFlagCarriedBy <- function(flag, player) {
    if (!flag || !player) return false;
    local owner = ::flagspawn._FlagOwner(flag);
    if (owner == player) return true;
    local parent = null;
    try { parent = flag.GetMoveParent(); } catch(e2) { parent = null; }
    return parent == player;
};

::flagspawn._ResolveCarriedFlag <- function(player) {
    if (!player) return null;
    local f = null;
    while ((f = Entities.FindByClassname(f, "item_teamflag")) != null) {
        if (::flagspawn._IsFlagCarriedBy(f, player)) return f;
    }
    return null;
};

// ------------------------------------------------------------
// Player state
// ------------------------------------------------------------
::flagspawn._ps <- {};

::flagspawn._PS <- function(player) {
    local k = 0;
    try { k = player.entindex(); } catch(e) { k = 0; }
    if (!(k in ::flagspawn._ps)) {
        ::flagspawn._ps[k] <- {
            used_this_life = false,
            last_spawner_touch = -9999.0,
            pending_flag_eidx = -1
        };
    }
    return ::flagspawn._ps[k];
};

// ------------------------------------------------------------
// Pool
// ------------------------------------------------------------
::flagspawn._Pool <- { red = [], blu = [], red_i = 0, blu_i = 0 };

::flagspawn._HideFlag <- function(flag) {
    if (!flag) return;
    try { flag.SetAbsOrigin(::flagspawn.POOL_HIDE_ORIGIN); } catch(e) {}
    try { EntFireByHandle(flag, "ForceReset", "", 0, null, null); } catch(e2) {}
    try { EntFireByHandle(flag, "Disable", "", 0, null, null); } catch(e3) {}
};

::flagspawn._InitPool <- function() {
    ::flagspawn._Pool.red.clear();
    ::flagspawn._Pool.blu.clear();
    ::flagspawn._Pool.red_i = 0;
    ::flagspawn._Pool.blu_i = 0;

    for (local i = 1; i <= ::flagspawn.POOL_PER_TEAM; i++) {
        local nR = format("%s%02d", ::flagspawn.POOL_NAME_RED_PREFIX, i);
        local nB = format("%s%02d", ::flagspawn.POOL_NAME_BLU_PREFIX, i);
        local fR = ::flagspawn._FindByName(nR);
        local fB = ::flagspawn._FindByName(nB);
        if (fR) ::flagspawn._Pool.red.append(fR);
        if (fB) ::flagspawn._Pool.blu.append(fB);
    }

    if (::flagspawn.DEBUG) ::flagspawn.Log("Pool init: red=" + ::flagspawn._Pool.red.len() + " blu=" + ::flagspawn._Pool.blu.len());
};

::flagspawn._TakeNextFromPool <- function(team) {
    if (team == ::flagspawn.TEAM_RED) {
        if (::flagspawn._Pool.red.len() == 0) return null;
        local f = ::flagspawn._Pool.red[::flagspawn._Pool.red_i % ::flagspawn._Pool.red.len()];
        ::flagspawn._Pool.red_i++;
        try { EntFireByHandle(f, "Enable", "", 0, null, null); } catch(e) {}
        return f;
    }
    if (team == ::flagspawn.TEAM_BLU) {
        if (::flagspawn._Pool.blu.len() == 0) return null;
        local f = ::flagspawn._Pool.blu[::flagspawn._Pool.blu_i % ::flagspawn._Pool.blu.len()];
        ::flagspawn._Pool.blu_i++;
        try { EntFireByHandle(f, "Enable", "", 0, null, null); } catch(e2) {}
        return f;
    }
    return null;
};

::flagspawn._NudgeForPickup <- function(flag, player) {
    if (!flag || !player) return;
    // Put the flag on the player's feet; PD pickup should grab it immediately.
    try { flag.SetAbsOrigin(player.GetOrigin() + Vector(0,0,24)); } catch(e) {}
};

// Best-effort verify: if carried, mark used_this_life.
::flagspawn._StartVerifyPickup <- function(player, flag, attempt) {
    if (!player || !flag) return;

    if (::flagspawn._IsFlagCarriedBy(flag, player)) {
        local ps = ::flagspawn._PS(player);
        ps.used_this_life = true;
        ps.pending_flag_eidx = -1;
        return;
    }

    if (attempt >= ::flagspawn.PICKUP_RETRY_COUNT) {
        local ps2 = ::flagspawn._PS(player);
        ps2.pending_flag_eidx = -1;
        return;
    }

    local code = "if (::flagspawn!=null) ::flagspawn._VerifyPickup(" + player.entindex() + "," + flag.entindex() + "," + (attempt+1) + ");";
    try { EntFireByHandle(player, "RunScriptCode", code, ::flagspawn.PICKUP_RETRY_INTERVAL, null, null); } catch(e2) {}
};

::flagspawn._VerifyPickup <- function(playerEidx, flagEidx, attempt) {
    local player = null; local flag = null;
    try { player = EntIndexToHScript(playerEidx); } catch(e) {}
    try { flag = EntIndexToHScript(flagEidx); } catch(e2) {}
    if (!player || !flag) return;
    ::flagspawn._StartVerifyPickup(player, flag, attempt);
};

// ------------------------------------------------------------
// VMF entry: enemy tap / spawner touch
// teamParam is the TOUCHING PLAYER TEAM in fs_gm1.vmf.
// We spawn the OPPOSITE team's pooled flag.
// ------------------------------------------------------------
::flagspawn.OnSpawnerTouch <- function(activator, teamParam) {
    local player = activator;
    if (!player) return;

    local ps = ::flagspawn._PS(player);

    local now = Time();
    if (now - ps.last_spawner_touch < ::flagspawn.SPAWNER_TOUCH_COOLDOWN) return;
    ps.last_spawner_touch = now;

    local requested = (typeof teamParam == "integer") ? teamParam : 0;
    if (requested != ::flagspawn.TEAM_RED && requested != ::flagspawn.TEAM_BLU) {
        ::flagspawn.Log("OnSpawnerTouch DENY: bad teamParam");
        return;
    }

    local spawnTeam = ::flagspawn._OppTeam(requested); // take enemy pool

    // If already carrying, STACK (optional; remove if you want)
    local carried = ::flagspawn._ResolveCarriedFlag(player);
    if (carried) {
        local add = ::flagspawn.GetClassBonus(player);
        local cur = ::flagspawn._GetFlagPointsValue(carried);
        local nxt = cur + add;
        ::flagspawn._SetFlagPointsValue(carried, nxt);

        // PD Fuel: tapping while already carrying still counts as tap reward
        ::flagspawn.AddFuel(requested, add);
        ::flagspawn.AddRoundTime(::flagspawn.TAP_TIME_BONUS);

        ::flagspawn.Log("STACK: " + cur + " -> " + nxt);
        return;
    }

    // One-per-life gate (resets on capture too)
    if (ps.used_this_life) { ::flagspawn.Log("DENY: used_this_life=true"); return; }
    if (ps.pending_flag_eidx != -1) { ::flagspawn.Log("DENY: pending flag already dispensed"); return; }

    local flag = ::flagspawn._TakeNextFromPool(spawnTeam);
    if (!flag) { ::flagspawn.Log("DENY: pool empty for spawnTeam=" + spawnTeam); return; }

    local val = ::flagspawn.GetClassBonus(player);
    ::flagspawn._SetFlagPointsValue(flag, val);

    ps.pending_flag_eidx = flag.entindex();

    ::flagspawn._NudgeForPickup(flag, player);

    // PD Fuel: tapping adds Fuel + extends timer
    ::flagspawn.AddFuel(requested, val);
    ::flagspawn.AddRoundTime(::flagspawn.TAP_TIME_BONUS);

    ::flagspawn.Log("DISPENSE: enemyTeam=" + spawnTeam + " val=" + val);

    ::flagspawn._StartVerifyPickup(player, flag, 0);
};

// ------------------------------------------------------------
// VMF entry: capture touch (bank points + reset gate)
// teamParam is the CAPTURE TEAM in fs_gm1.vmf (2 for redcapper, 3 for blucapper).
// ------------------------------------------------------------
::flagspawn.OnCaptureTouch <- function(activator, teamParam) {
    local player = activator;
    if (!player) return;

    local capTeam = (typeof teamParam == "integer") ? teamParam : 0;
    if (capTeam != ::flagspawn.TEAM_RED && capTeam != ::flagspawn.TEAM_BLU) return;

    if (::flagspawn._GetTeamNum(player) != capTeam) return;

    local flag = ::flagspawn._ResolveCarriedFlag(player);
    if (!flag) return;

    local pts = ::flagspawn._GetFlagPointsValue(flag);
    if (pts <= 0) pts = 1;

    // Bank into Fuel (your “PD Fuel” mechanic)
    ::flagspawn.AddFuel(capTeam, pts);

    // Reset gate so you can tap again this life after a capture
    local ps = ::flagspawn._PS(player);
    ps.used_this_life = false;
    ps.pending_flag_eidx = -1;

    // Return the carried flag to pool storage (best-effort)
    ::flagspawn._HideFlag(flag);

    ::flagspawn.Log("CAPTURE: +" + pts + " fuel to " + capTeam + " (gate reset)");
};

// ------------------------------------------------------------
// Events: reset gate on spawn
// ------------------------------------------------------------
::flagspawn.OnGameEvent_player_spawn <- function(params) {
    local player = null;
    if ("userid" in params) { try { player = GetPlayerFromUserID(params.userid); } catch(e) { player = null; } }
    if (!player) return;

    local ps = ::flagspawn._PS(player);
    ps.used_this_life = false;
    ps.pending_flag_eidx = -1;
    ps.last_spawner_touch = -9999.0;
};

::flagspawn.RegisterEvents <- function() {
    try { __CollectGameEventCallbacks(::flagspawn); } catch(e) {}
};

::flagspawn.Init <- function() {
    ::flagspawn.Log("Init @ t=" + Time());
    ::flagspawn._InitPool();
    ::flagspawn.RegisterEvents();

    // initialize digits if present
    ::flagspawn.UpdateFuelDisplay(::flagspawn.TEAM_RED);
    ::flagspawn.UpdateFuelDisplay(::flagspawn.TEAM_BLU);

    ::flagspawn.Log("READY: fs_gm1-compatible (OnSpawnerTouch/OnCaptureTouch) + Fuel added.");
};

::flagspawn.Init();
