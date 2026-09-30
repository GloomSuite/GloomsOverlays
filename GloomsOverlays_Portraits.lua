-- ============================================================
-- GloomsOverlays_Portraits.lua — Gloom's UI: the PORTRAIT overlay type.
-- ★ 2026-09-29, the owner: "I want a portrait to simply be another overlay
-- type." An overlay with `kind = "portrait"` draws a unit — `unit` "player" |
-- "target" — as a 3D model (`mode` "3d") or the game's round 2D portrait
-- ("2d"), at `size` (square), with the 3D camera `facing` (radians) · `zoom` ·
-- `modelYOffset` · `pitch`. Where it sits, its layer, opacity, show conditions,
-- eye, profile and group are every overlay's (GloomsOverlays.lua).
--
-- The instance story below came across from Gloom's Portraits (retired the same
-- day) unchanged — it was measured in a delve and owner-QA'd; the measurements
-- are the Hub's FINDINGS §17. The old Portraits settings were NOT carried over
-- (the owner rebuilds his portraits), and neither were its separate 3D and 2D
-- positions: a portrait has ONE place, and the 2D stand-in wears it.
--
-- Each portrait overlay draws through a pooled SLOT (a PlayerModel + a portrait
-- frame), like the textures' frame pool: the Nth enabled portrait always uses
-- slot N, and the model is only re-asked for its unit when the slot changes
-- hands, the unit or the mode changes, or the game says the unit changed — a
-- dial drag re-applies layout and camera, never reloads the model.
-- ============================================================

local _, addon = ...
local PR = {}
addon.PR = PR

local slots = {}

local function UnitOf(ov) return ov.unit == "target" and "target" or "player" end
function PR.DefaultFacing(unit) return unit == "target" and math.pi or 0 end
-- the windows ask which way a new unit faces (a camera left at the old unit's
-- default turns with it)
GloomsOverlays_PortraitDefaults = { facing = PR.DefaultFacing }

------------------------------------------------------------------------
-- Can a 3D model be shown for this unit at all?
--
-- ⚠ MEASURED IN A DELVE, 2026-09-05: UnitGUID("target") on a HOSTILE npc inside
-- instanced content returns a SECRET value. Model:SetUnit has to resolve the unit
-- to look up its display info, and with the identity withheld it does nothing at
-- all -- it does not clear, it does not error, it just leaves whatever model was
-- there before. That is why targeting a delve mob used to leave your own (or a
-- party member's) model sitting on screen, looking like a working feature showing
-- the wrong unit.
--
-- ★ RE-MEASURED 2026-09-19, same delve: the secrecy is a COMBAT rule, not an
-- instance rule. Out of combat, UnitGUID and UnitName of the same hostile are
-- both readable (issecretvalue → false) and SetUnit works; the moment the pull
-- starts they go secret. Only ENEMY identity is affected either way, which is
-- why friendly and party units keep working in the same delve.
--
-- What that buys: a mob targeted BEFORE the pull gets its real 3D model, and the
-- frame keeps it through the fight because nothing re-asks the game until the
-- target changes. A mob targeted MID-fight cannot be identified — the honest
-- response is the 2D stand-in (PR.Show), never a stale model — and
-- PLAYER_REGEN_ENABLED re-asks so the stand-in yields to 3D when combat ends.
-- There is no addon-side way past the in-combat half: the model IS the identity.
------------------------------------------------------------------------
local function CanShowUnit(unit)
    if not UnitExists(unit) then return false end
    -- issecretvalue is the only safe question to ask: never compare or concatenate
    -- a possibly-secret value first.
    if issecretvalue and issecretvalue(UnitGUID(unit)) then return false end
    return true
end

local function ApplyCamera(model, ov)
    model:SetFacing(ov.facing or PR.DefaultFacing(UnitOf(ov)))
    model:SetPortraitZoom(0)
    model:SetCamDistanceScale(ov.zoom or 2.5)
    model:SetAnimation(0)
    model:SetViewTranslation(0, ov.modelYOffset or 0)
    model:SetPitch(ov.pitch or 0)
end

------------------------------------------------------------------------
-- The NAMEPLATE CACHE — how a mob targeted before the pull keeps its 3D model
-- when you tab BACK to it mid-combat.
--
-- ★ MEASURED IN A DELVE, 2026-09-19 (all with /dump issecretvalue):
--   · UnitGUID("target")     out of combat → false; in combat → true.
--   · UnitGUID("nameplateN") out of combat → TRUE. Plates are secret on the
--     map, combat or not — so "record the whole pack as it comes into view"
--     is impossible; a model of a plate unit never even loads (display 0,
--     OnModelLoaded never fires).
--   · UnitGUID("mouseover")  out of combat → TRUE. Hovering identifies nothing.
--   · UnitIsUnit("target", "nameplateN") in combat → a REAL boolean (one
--     plate true, the rest false, none secret).
-- So the game identifies exactly ONE unit for an addon on a restricted map —
-- the target, out of combat — but will always say WHICH PLATE the target is.
--
-- Hence: each time the target is identifiable, its creature ID (from the
-- GUID) is recorded against the plate it is standing under. In combat, when
-- the identity is withheld, the target's plate is matched and the recorded
-- creature ID goes to SetCreature, which takes a plain number and is not
-- guarded. Plate tokens are REUSED as plates come and go, so an entry dies
-- with NAME_PLATE_UNIT_REMOVED. Players are never recorded (SetUnit works
-- on them anyway, and a creature model is the wrong thing for a player).
------------------------------------------------------------------------
local plateCache = {}     -- "nameplateN" -> creature ID, while that plate is up

-- The plate the target is standing under, or nil. Safe in combat.
local function TargetPlate()
    for i = 1, 40 do
        local token = "nameplate" .. i
        if UnitExists(token) then
            local same = UnitIsUnit("target", token)
            if not (issecretvalue and issecretvalue(same)) and same then return token end
        end
    end
end

-- Called whenever the target changes: record it if the game will identify it.
local function RecordTarget()
    if not UnitExists("target") then return end
    local guid = UnitGUID("target")
    if not guid or (issecretvalue and issecretvalue(guid)) then return end   -- in combat
    local kind, _, _, _, _, npcID = strsplit("-", guid)
    if (kind ~= "Creature" and kind ~= "Vehicle") or not tonumber(npcID) then return end
    local token = TargetPlate()
    if token then plateCache[token] = tonumber(npcID) end
end

local function CachedTargetCreature()
    local token = TargetPlate()
    return token and plateCache[token] or nil
end

------------------------------------------------------------------------
-- A slot: the model and the portrait frame one portrait overlay draws through.
------------------------------------------------------------------------
local function Acquire(i)
    local s = slots[i]
    if s then return s end
    s = {}
    s.model = CreateFrame("PlayerModel", "GloomsOverlays_Model_" .. i, UIParent)
    s.model:EnableMouse(false); s.model:Hide()
    s.port = CreateFrame("Frame", "GloomsOverlays_Portrait_" .. i, UIParent)
    s.port:EnableMouse(false); s.port:Hide()
    s.port.tex = s.port:CreateTexture(nil, "ARTWORK")
    s.port.tex:SetAllPoints(s.port)
    s.anchor = s.model   -- /gui debug reads a frame's place from here
    slots[i] = s
    return s
end

local function SetupModel(s)
    local ov = s.ov
    if not ov then return end
    local unit, model = UnitOf(ov), s.model
    s.blocked = not CanShowUnit(unit)
    if s.blocked and unit == "target" then
        local id = CachedTargetCreature()
        if id then
            -- The identity is secret but the plate isn't: draw what we recorded.
            model:SetCreature(id)
            ApplyCamera(model, ov)
            s.blocked = false
            return
        end
    end
    if s.blocked then
        -- Empty beats WRONG. A stale model is indistinguishable from a correct one.
        -- ⚠ ClearModel is NOT enough on 12.1 (owner-observed in a delve,
        -- 2026-09-19): friendly target → clear → hostile target showed the
        -- FRIENDLY model again. So PR.Show hides the model outright while
        -- `blocked` is set; the clear is belt-and-braces.
        if model.ClearModel then model:ClearModel() end
        return
    end
    model:SetUnit(unit)
    ApplyCamera(model, ov)
end

-- SetPortraitTexture always renders as a circle — engine behavior.
-- ⚠ DELIBERATELY NOT GATED like the 3D path: 12.1 restricted Model:SetUnit and
-- ModelSceneActor:SetModelByUnit by name; SetPortraitTexture is NOT on that
-- list, renders engine-side and hands Lua nothing — so a hostile the game won't
-- identify for a model still gets its correct 2D portrait (owner-QA'd in a
-- delve, 2026-09-19). If it is ever blocked too, it fails to a blank texture.
local function SetupPortrait(s)
    if not s.ov then return end
    SetPortraitTexture(s.port.tex, UnitOf(s.ov))
end

local function Setup(s)
    local unit = UnitOf(s.ov)
    if unit == "target" and not UnitExists("target") then
        s.blocked = false
        return
    end
    if (s.ov.mode or "3d") == "3d" then SetupModel(s) else s.blocked = false end
    SetupPortrait(s)   -- the 2D mode, or the 3D mode's stand-in
end

------------------------------------------------------------------------
-- The engine's side (GloomsOverlays.lua): Build · Layout · Show · ParkFrom.
------------------------------------------------------------------------
function PR.Layout(s, ov)
    local size = GloomsOverlays_BoxSize(ov)          -- the group's scale included
    local rel, x, y = GloomsOverlays_Place(ov)
    local strata = ov.strata or "HIGH"
    local level = ov.level or GloomsOverlays_GetDefaultLevel()
    for _, f in ipairs({ s.model, s.port }) do
        f:SetSize(size, size)
        f:ClearAllPoints()
        f:SetPoint("CENTER", rel, "CENTER", x, y)
        f:SetFrameStrata(strata)
        f:SetFrameLevel(level)
        f:SetAlpha(ov.alpha or 1)
    end
end

function PR.Show(s, condMet)
    local ov = s.ov
    if not ov then return end
    local visible = condMet and (UnitOf(ov) == "player" or UnitExists("target"))
    local mode = ov.mode or "3d"
    -- A blocked 3D model is never shown, whatever ClearModel did or didn't do;
    -- the 2D portrait stands in, in the same place at the same size.
    s.model:SetShown(visible and mode == "3d" and not s.blocked)
    s.port:SetShown(visible and (mode == "2d" or s.blocked == true))
end

function PR.Build(ov, i, condMet)
    local s = Acquire(i)
    local key = UnitOf(ov) .. "|" .. (ov.mode or "3d")
    local fresh = (s.ov ~= ov) or (s.key ~= key)
    s.ov, s.key = ov, key
    PR.Layout(s, ov)
    if fresh then Setup(s)
    elseif (ov.mode or "3d") == "3d" and not s.blocked then ApplyCamera(s.model, ov) end
    PR.Show(s, condMet)
    return { slot = s, config = ov }
end

function PR.ParkFrom(i)
    for j = i, #slots do
        local s = slots[j]
        if s.ov then
            s.ov, s.key, s.blocked = nil, nil, nil
            s.model:Hide(); s.port:Hide()
            if s.model.ClearModel then s.model:ClearModel() end
            s.port.tex:SetTexture(nil)
        end
    end
end

-- /gui plates — a QA probe: what the nameplate cache holds, which plate is the
-- target. (Probes live in the addon: a /run over 255 characters silently does
-- nothing — Hub LESSONS.)
function PR.PlatesProbe()
    local n = 0
    for i = 1, 40 do
        local token = "nameplate" .. i
        local id = plateCache[token]
        if id then
            n = n + 1
            local same = UnitIsUnit("target", token)
            same = not (issecretvalue and issecretvalue(same)) and same
            print(("  %s → creature %d%s"):format(token, id, same and "  ← TARGET" or ""))
        end
    end
    local blocked = false
    for _, s in ipairs(slots) do if s.ov and UnitOf(s.ov) == "target" and s.blocked then blocked = true end end
    print(("|cff936bffGloom's UI:|r %d plate%s cached, target %s."):format(
        n, n == 1 and "" or "s", blocked and "BLOCKED (2D stand-in)" or "3D"))
end

------------------------------------------------------------------------
-- Events — the units change under the portraits.
------------------------------------------------------------------------
local function EachSlot(unit, fn)
    for _, s in ipairs(slots) do
        if s.ov and (unit == nil or UnitOf(s.ov) == unit) then fn(s) end
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("UNIT_MODEL_CHANGED")
ev:RegisterEvent("UNIT_PORTRAIT_UPDATE")
ev:RegisterEvent("NAME_PLATE_UNIT_ADDED")
ev:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_ENTERING_WORLD" then
        RecordTarget()
        EachSlot(nil, Setup)
    elseif event == "PLAYER_TARGET_CHANGED" then
        RecordTarget()
        EachSlot("target", Setup)
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- ★ MEASURED IN A DELVE, 2026-09-19: a hostile's identity is secret ONLY
        -- IN COMBAT, so a model the game refused mid-fight can be asked for again
        -- the moment combat drops — the stand-in gives way to the real 3D model
        -- without re-targeting.
        RecordTarget()
        EachSlot("target", function(s) if s.blocked and UnitExists("target") then SetupModel(s) end end)
    elseif event == "UNIT_MODEL_CHANGED" then
        if arg1 == "player" or arg1 == "target" then
            EachSlot(arg1, function(s) if (s.ov.mode or "3d") == "3d" and UnitExists(arg1) then SetupModel(s) end end)
        end
    elseif event == "UNIT_PORTRAIT_UPDATE" then
        if arg1 == "player" or arg1 == "target" then
            EachSlot(arg1, function(s) if UnitExists(arg1) then SetupPortrait(s) end end)
        end
        return
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        -- The target's own plate may appear after the target did.
        if UnitExists("target") then RecordTarget() end
        return
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        plateCache[arg1] = nil
        return
    end
    if addon.UpdateVisibility then addon.UpdateVisibility() end
end)
