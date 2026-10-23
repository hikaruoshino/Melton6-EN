-- =============================================================================
-- Melton6.lua : a Scholar addon that runs a 6-step skillchain with Immanence and finishes with Kaustra (magic burst) from one macro press (English edition)
-- =============================================================================
-- Usage: put one line `/console m6 go` in an in-game macro, target an enemy and press it.
--
-- Sequence (Tabula Rasa and Dark Arts are skipped if they are already active):
--   Tabula Rasa -> Dark Arts
--   -> Immanence Aero (Detonation) -> Immanence Stone (Scission) = Scission -> Immanence Aero = Detonation
--   -> Immanence Geohelix = Scission -> Immanence Anemohelix = Detonation -> Immanence Noctohelix (Compression) = Gravitation
--   -> Enlightenment -> Ebullience -> Kaustra (Dark on Gravitation = magic burst)
--
-- How it advances: it does not use fixed waits. It confirms each action from the action packets before going on.
--   Abilities: confirm the execution packet (category 6), wait ja_gap_sec (1 s), then go on.
--              Enlightenment -> Ebullience fails if they are not 1 s apart (confirmed in game by the author).
--              Enlightenment and Ebullience can fail because of lag, so if either one ran it goes on to Kaustra
--              (if both failed it stops before Kaustra). It does not retry them.
--   Spells:    confirm the start of casting (category 8) and the landing (category 4). From the 2nd step on it also confirms
--              that the intended skillchain happened (added-effect message), and waits post_land_sec after landing.
--   On any failure (cast interrupted, no skillchain, timeout, target changed, zone change, ...) it stops on the spot.
--
-- Note: this is an auto-cast addon. One macro press sends the ability and spell inputs (up to 17) automatically.
--   One press runs it once; it never repeats. If anything fails it stops where it is.
--   Using external tools is not permitted by the FFXI Terms of Service; use it at your own risk.
--   Do not use it unattended, and do not modify it for automatic combat or repeated casting.
--
-- Text: chat output and input commands are plain ASCII (English client), so there is no Shift-JIS conversion.
-- =============================================================================

_addon.name     = "Melton6"
_addon.author   = "hikaruoshino"
_addon.version  = "1.0.0"
_addon.commands = {"m6", "melton6"}

local config = require("config")
local res    = require("resources")

-- -----------------------------------------------------------------------------
-- Settings (data/settings.xml)
-- -----------------------------------------------------------------------------
local defaults = {
    post_land_sec          = 3.0,   -- seconds from a spell landing to the next ability
    ja_gap_sec             = 1.0,   -- seconds from an ability being used to the next action (like <wait 1>)
    ja_timeout_sec         = 2.5,   -- seconds to wait for an ability to be confirmed after using it
    boost_timeout_sec      = 1.5,   -- the same wait for Enlightenment and Ebullience only (kept short to make the burst window)
    ja_retries             = 1,     -- how many times to use an ability again if it was not executed
    cast_start_timeout_sec = 2.5,   -- seconds to wait for the start of casting after using a spell
    land_timeout_sec       = 12.0,  -- seconds to wait for the landing after the start of casting
    mb_window_sec          = 10.0,  -- seconds the burst window lasts from the Noctohelix landing (8 + 2 s when a helix closes the chain)
    use_tabula_rasa        = true,  -- use Tabula Rasa automatically when it is off (stop if false)
}
local settings = config.load(defaults)

-- -----------------------------------------------------------------------------
-- Constants (the numbers are Windower res values)
-- -----------------------------------------------------------------------------
local JA = {TABULA_RASA = 210, DARK_ARTS = 212, EBULLIENCE = 221, ENLIGHTENMENT = 244, IMMANENCE = 317}
local SPELL = {AERO = 154, STONE = 159, GEOHELIX = 278, ANEMOHELIX = 280, NOCTOHELIX = 284, KAUSTRA = 502}
local BUFF = {DARK_ARTS = 359, ADDENDUM_BLACK = 402, TABULA_RASA = 377}
local RECAST = {TABULA_RASA = 0, ENLIGHTENMENT = 235}   -- ability recast IDs

local CAST_BEGIN, CAST_INTERRUPT = 24931, 28787         -- param of category 8
-- Message IDs for "Magic Burst!" (every message in res/action_messages.lua that contains "Magic Burst").
-- With 252 (damage) alone, a burst that arrives under another ID would be judged "not a burst"
local MSG_MAGIC_BURST = {}
for _, id in ipairs({252, 265, 268, 269, 271, 272, 274, 275, 379, 650, 747, 748, 749, 750, 751, 752, 753, 754, 755, 803, 804}) do
    MSG_MAGIC_BURST[id] = true
end
local MAX_DISTANCE = 21                                 -- rough distance a spell reaches (yalms)

-- Added-effect message ID -> skillchain name (288-301 and 385-398 are the same order; same table as MBReadyTimer and OmniChain)
local SKILLCHAIN_MESSAGES = {}
do
    local order = {"Light", "Darkness", "Gravitation", "Fragmentation", "Distortion", "Fusion", "Compression", "Liquefaction", "Induration", "Reverberation", "Transfixion", "Scission", "Detonation", "Impaction"}
    for i, name in ipairs(order) do
        SKILLCHAIN_MESSAGES[287 + i] = name
        SKILLCHAIN_MESSAGES[384 + i] = name
    end
end

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------
local function chat(msg, color)
    windower.add_to_chat(color or 207, "[Melton6] " .. tostring(msg))
end

local function ja_name(id) return res.job_abilities[id] and res.job_abilities[id].en or tostring(id) end
local function spell_name(id) return res.spells[id] and res.spells[id].en or tostring(id) end

local function send_input(line)
    windower.send_command("input " .. line)
end

local function has_buff(player, id)
    for _, b in ipairs(player and player.buffs or {}) do
        if b == id then return true end
    end
    return false
end

-- -----------------------------------------------------------------------------
-- Steps
-- -----------------------------------------------------------------------------
-- kind = "ja" / "ma". If skip_if returns true the step is skipped. expect_sc is the skillchain the spell should make when it lands
local function build_steps()
    local steps = {
        {kind = "ja", id = JA.TABULA_RASA, target = "<me>",
         skip_if = function(p) return has_buff(p, BUFF.TABULA_RASA) end},
        {kind = "ja", id = JA.DARK_ARTS, target = "<me>",
         skip_if = function(p) return has_buff(p, BUFF.DARK_ARTS) or has_buff(p, BUFF.ADDENDUM_BLACK) end},
    }
    local chain = {
        {SPELL.AERO,       nil},
        {SPELL.STONE,      "Scission"},
        {SPELL.AERO,       "Detonation"},
        {SPELL.GEOHELIX,   "Scission"},
        {SPELL.ANEMOHELIX, "Detonation"},
        {SPELL.NOCTOHELIX, "Gravitation"},
    }
    for i, c in ipairs(chain) do
        table.insert(steps, {kind = "ja", id = JA.IMMANENCE, target = "<me>"})
        table.insert(steps, {kind = "ma", id = c[1], target = "<t>", expect_sc = c[2], chain_no = i})
    end
    -- Enlightenment and Ebullience raise the power. They can fail because of lag, so if either one ran
    -- it goes on to Kaustra (boost). It does not retry them, to make the burst window
    table.insert(steps, {kind = "ja", id = JA.ENLIGHTENMENT, target = "<me>", boost = true})
    table.insert(steps, {kind = "ja", id = JA.EBULLIENCE, target = "<me>", boost = true})
    table.insert(steps, {kind = "ma", id = SPELL.KAUSTRA, target = "<t>", final = true})
    return steps
end

-- -----------------------------------------------------------------------------
-- Pre-start check (before anything is executed, report everything that is missing)
-- -----------------------------------------------------------------------------
local function precheck()
    local problems = {}
    local player = windower.ffxi.get_player()
    if not player then return {"Cannot get character information"}, nil, nil end

    if player.main_job ~= "SCH" then
        table.insert(problems, "Your main job is not Scholar")
    end
    if player.status ~= 0 and player.status ~= 1 then   -- 0: idle / 1: engaged
        table.insert(problems, "You cannot act right now")
    end

    local target = windower.ffxi.get_mob_by_target("t")
    if not target or not target.valid_target or target.hpp == 0 or target.spawn_type ~= 16 then
        table.insert(problems, "Target an enemy")
    elseif target.distance and math.sqrt(target.distance) > MAX_DISTANCE then
        table.insert(problems, string.format("The enemy is too far away (%.1f)", math.sqrt(target.distance)))
    end

    -- Recasts of the helix spells and Kaustra (if it stopped halfway, Tabula Rasa would be wasted, so check first)
    local spell_recasts = windower.ffxi.get_spell_recasts() or {}
    for _, id in ipairs({SPELL.GEOHELIX, SPELL.ANEMOHELIX, SPELL.NOCTOHELIX, SPELL.KAUSTRA}) do
        local r = (spell_recasts[id] or 0) / 60
        if r > 0 then table.insert(problems, string.format("%s is on recast (%.0f s left)", spell_name(id), r)) end
    end
    local ja_recasts = windower.ffxi.get_ability_recasts() or {}
    if (ja_recasts[RECAST.ENLIGHTENMENT] or 0) > 0 then
        table.insert(problems, string.format("Enlightenment is on recast (%d s left)", ja_recasts[RECAST.ENLIGHTENMENT]))
    end
    if not has_buff(player, BUFF.TABULA_RASA) then
        if not settings.use_tabula_rasa then
            table.insert(problems, "Tabula Rasa is not active (Kaustra can only be cast while Tabula Rasa is active)")
        elseif (ja_recasts[RECAST.TABULA_RASA] or 0) > 0 then
            table.insert(problems, string.format("Tabula Rasa is on recast (%d min left)", math.ceil(ja_recasts[RECAST.TABULA_RASA] / 60)))
        end
    end

    -- MP: the 6 spells + Kaustra (20% of max MP)
    local need = math.ceil((player.vitals.max_mp or 0) * 0.2)
    for _, id in ipairs({SPELL.AERO, SPELL.STONE, SPELL.AERO, SPELL.GEOHELIX, SPELL.ANEMOHELIX, SPELL.NOCTOHELIX}) do
        need = need + (res.spells[id].mp_cost or 0)
    end
    if (player.vitals.mp or 0) < need then
        table.insert(problems, string.format("Not enough MP (%d / need %d)", player.vitals.mp or 0, need))
    end

    return problems, player, target
end

-- -----------------------------------------------------------------------------
-- Run state
-- -----------------------------------------------------------------------------
local run = nil   -- information about the run in progress (nil when stopped)
local player_id = nil

local function stop(reason, color)
    if not run then return end
    local step = run.steps[run.index]
    local where = step and string.format(" (%d/%d: %s)", run.index, #run.steps,
        step.kind == "ja" and ja_name(step.id) or spell_name(step.id)) or ""
    chat("Stopped: " .. reason .. where, color or 167)
    run = nil
end

local function finish(msg)
    chat(msg, 158)
    run = nil
end

-- Go to the next step. It is sent after `wait` seconds
local function advance(now, wait)
    run.index = run.index + 1
    run.phase = "wait"
    run.next_at = now + wait
end

-- Send the current step
local function send_step(now)
    local step = run.steps[run.index]
    if step.skip_if and step.skip_if(windower.ffxi.get_player()) then
        run.index = run.index + 1
        run.next_at = now
        return
    end

    if step.final and not (run.boosted[JA.ENLIGHTENMENT] or run.boosted[JA.EBULLIENCE]) then
        stop("Neither Enlightenment nor Ebullience went off")
        return
    end

    if step.kind == "ma" then
        -- Stop if the target changed or died (so a chain is not fired at another enemy)
        local t = windower.ffxi.get_mob_by_target("t")
        if not t or t.id ~= run.target_id or t.hpp == 0 then
            stop("The target changed or died")
            return
        end
        send_input(string.format('/ma "%s" %s', spell_name(step.id), step.target))
        run.phase = "ma_sent"
        run.deadline = now + settings.cast_start_timeout_sec
    else
        send_input(string.format('/ja "%s" %s', ja_name(step.id), step.target))
        run.phase = "ja_sent"
        -- Keep the wait short for Enlightenment and Ebullience: even if both fail, Kaustra must land within 10 s of
        -- the Gravitation landing (with 2.5 s it takes about 10.7 s and misses the burst window)
        run.deadline = now + (step.boost and settings.boost_timeout_sec or settings.ja_timeout_sec)
        run.tries = (run.tries or 0) + 1
    end
end

local function tick(now)
    if not run then return end
    if run.phase == "wait" then
        if run.index > #run.steps then
            finish("Finished")
        elseif now >= run.next_at then
            send_step(now)
        end
    elseif now > run.deadline then
        if run.phase == "ja_sent" then
            local step = run.steps[run.index]
            if step.boost then
                -- A power-up ability goes on even if it fails (if both fail, it stops before Kaustra)
                chat(ja_name(step.id) .. " did not go off (continuing)", 167)
                run.tries = 0
                -- If the next one is also a power-up (Enlightenment -> Ebullience), use it without waiting: to leave room in the burst window.
                -- Even if Enlightenment is delayed by lag and Ebullience fails, Enlightenment is counted and it can go on.
                -- If the next one is Kaustra, wait 1 s (so a delayed Ebullience does not collide with it and bounce the cast)
                local next_step = run.steps[run.index + 1]
                advance(now, (next_step and next_step.boost) and 0 or settings.ja_gap_sec)
            elseif run.tries <= settings.ja_retries then
                send_step(now)   -- if it failed (e.g. waited too little), use it once more
            else
                stop("The ability did not go off")
            end
        elseif run.phase == "ma_sent" then
            stop("Casting did not start (out of range, not enough MP, cannot cast, etc.)")
        elseif run.phase == "casting" then
            stop("Could not confirm the spell landing")
        end
    end
end

windower.register_event("prerender", function()
    if not run then return end
    local ok, err = pcall(tick, os.clock())
    if not ok then
        run = nil
        chat("Stopped because of an error: " .. tostring(err), 167)
    end
end)

-- The name of the skillchain made by the spell that landed (nil if none)
local function skillchain_of(act)
    for _, target in ipairs(act.targets or {}) do
        local a = target.actions and target.actions[1]
        if a and a.has_add_effect and SKILLCHAIN_MESSAGES[a.add_effect_message] then
            return SKILLCHAIN_MESSAGES[a.add_effect_message]
        end
    end
    return nil
end

local function is_magic_burst(act)
    for _, target in ipairs(act.targets or {}) do
        local a = target.actions and target.actions[1]
        if a and MSG_MAGIC_BURST[a.message] then return true end
    end
    return false
end

-- A record for finding causes: the message IDs that arrived on landing (e.g. "2" or "2+add 163")
local function messages_of(act)
    local list = {}
    for _, target in ipairs(act.targets or {}) do
        local a = target.actions and target.actions[1]
        if a then
            local s = tostring(a.message)
            if a.has_add_effect then s = s .. "+add " .. tostring(a.add_effect_message) end
            table.insert(list, s)
        end
    end
    return table.concat(list, ",")
end

local function on_action(act)
    if act.actor_id ~= player_id then return end
    local now = os.clock()
    local step = run.steps[run.index]
    if not step then return end

    if act.category == 6 then
        -- Enlightenment and Ebullience count as used even if they arrive late because of lag
        if act.param == JA.ENLIGHTENMENT or act.param == JA.EBULLIENCE then
            run.boosted[act.param] = true
        end
        -- An ability was executed
        if run.phase == "ja_sent" and step.kind == "ja" and act.param == step.id then
            run.tries = 0
            advance(now, settings.ja_gap_sec)
        end

    elseif act.category == 8 then
        local a = act.targets and act.targets[1] and act.targets[1].actions and act.targets[1].actions[1]
        if act.param == CAST_INTERRUPT and (run.phase == "ma_sent" or run.phase == "casting") then
            stop("The cast was interrupted")
        elseif act.param == CAST_BEGIN and run.phase == "ma_sent" and a and a.param == step.id then
            run.phase = "casting"
            run.deadline = now + settings.land_timeout_sec
        end

    elseif act.category == 4 then
        if run.phase ~= "casting" or act.param ~= step.id then return end
        local sc = skillchain_of(act)

        if step.final then
            local late = run.mb_deadline and now > run.mb_deadline
            local used = {}
            if run.boosted[JA.ENLIGHTENMENT] then table.insert(used, "Enlightenment") end
            if run.boosted[JA.EBULLIENCE] then table.insert(used, "Ebullience") end
            local boosts = table.concat(used, " + ")
            -- seconds from the Noctohelix (Gravitation) landing to the Kaustra landing
            local since_sc = run.sc_landed_at and string.format("%.2f s", now - run.sc_landed_at) or "?"
            if is_magic_burst(act) then
                finish(string.format("Kaustra magic burst! (%d-step chain / %s / %s after Gravitation)", run.chain_count, boosts, since_sc))
            else
                finish((late and "Kaustra landed too late for the burst window (no burst)" or "Kaustra landed but it was not a magic burst")
                    .. string.format(" (%s / %s after Gravitation / messages %s)", boosts, since_sc, messages_of(act)))
            end
            return
        end

        if step.expect_sc then
            if sc ~= step.expect_sc then
                stop(string.format("The skillchain did not happen (intended: %s / result: %s)", step.expect_sc, sc or "none"))
                return
            end
            run.chain_count = step.chain_no
            chat(string.format("Step %d: %s", step.chain_no, sc))
            if sc == "Gravitation" then
                run.sc_landed_at = now
                run.mb_deadline = now + settings.mb_window_sec
            end
        end
        advance(now, settings.post_land_sec)
    end
end

windower.register_event("action", function(act)
    if not run then return end
    local ok, err = pcall(on_action, act)
    if not ok then
        run = nil
        chat("Stopped because of an error: " .. tostring(err), 167)
    end
end)

-- -----------------------------------------------------------------------------
-- Start and cleanup
-- -----------------------------------------------------------------------------
local function start()
    if run then
        chat("Already running. To stop it: //m6 stop", 167)
        return
    end
    local problems, player, target = precheck()
    if #problems > 0 then
        chat("Cannot start:", 167)
        for _, p in ipairs(problems) do chat("- " .. p, 167) end
        return
    end
    player_id = player.id
    run = {
        steps = build_steps(),
        index = 1,
        phase = "wait",
        next_at = os.clock(),
        target_id = target.id,
        chain_count = 0,
        tries = 0,
        boosted = {},   -- [Enlightenment / Ebullience ID] = it was used
    }
    chat("Starting on " .. (target.name or "?"))
end

windower.register_event("zone change", function() stop("You changed zones") end)
windower.register_event("status change", function(new)
    if run and (new == 2 or new == 3) then stop("You were knocked out") end   -- 2: dead / 3: dead (in battle)
end)
windower.register_event("logout", function() stop("You logged out") end)
windower.register_event("unload", function() run = nil end)

-- -----------------------------------------------------------------------------
-- Commands (//m6 or //melton6)
-- -----------------------------------------------------------------------------
local SETTABLE = {
    post = "post_land_sec", gap = "ja_gap_sec", jatimeout = "ja_timeout_sec", boosttimeout = "boost_timeout_sec",
    retries = "ja_retries", casttimeout = "cast_start_timeout_sec", landtimeout = "land_timeout_sec",
}

windower.register_event("addon command", function(cmd, ...)
    local args = {...}
    cmd = cmd and cmd:lower() or "help"

    if cmd == "go" or cmd == "start" then
        start()

    elseif cmd == "stop" then
        if run then stop("Stopped manually", 207) else chat("Not running") end

    elseif cmd == "check" then
        local problems = precheck()
        if #problems == 0 then
            chat("Ready to start")
        else
            for _, p in ipairs(problems) do chat("- " .. p, 167) end
        end

    elseif cmd == "tabula" then
        settings.use_tabula_rasa = not settings.use_tabula_rasa
        config.save(settings)
        chat("Use Tabula Rasa automatically when it is off: " .. (settings.use_tabula_rasa and "ON" or "OFF"))

    elseif cmd == "set" and SETTABLE[(args[1] or ""):lower()] and tonumber(args[2]) then
        local key = SETTABLE[args[1]:lower()]
        settings[key] = tonumber(args[2])
        config.save(settings)
        chat(string.format("%s = %s", key, tostring(settings[key])))

    elseif cmd == "status" then
        chat(string.format("landing->next %.1f s / after ability %.1f s / ability check %.1f s x retries %d (Enlightenment/Ebullience %.1f s) / cast start check %.1f s / landing check %.1f s / auto Tabula Rasa %s",
            settings.post_land_sec, settings.ja_gap_sec, settings.ja_timeout_sec, settings.ja_retries, settings.boost_timeout_sec,
            settings.cast_start_timeout_sec, settings.land_timeout_sec, settings.use_tabula_rasa and "ON" or "OFF"))
        if run then chat(string.format("Running: %d/%d", run.index, #run.steps)) end

    else
        chat("//m6 go      : start the 6-step skillchain into Kaustra (in an in-game macro: /console m6 go)")
        chat("//m6 stop    : stop halfway")
        chat("//m6 check   : only check whether it can start (executes nothing)")
        chat("//m6 status  : show the settings")
        chat("//m6 set post <sec> : from a spell landing to the next ability (default 3.0)")
        chat("//m6 set gap <sec>  : wait after an ability (default 1.0; Enlightenment -> Ebullience needs 1 s)")
        chat("//m6 tabula  : whether to use Tabula Rasa automatically when it is off (ON/OFF)")
    end
end)
