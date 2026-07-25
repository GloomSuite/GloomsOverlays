-- ============================================================
-- GloomsOverlays.lua
-- Core overlay engine. Overlays stored in VibeOverlayDB.
-- Per-character active profile stored in VibeOverlayDBChar.
-- ============================================================

local addonName, addon = ...

local liveOverlays = {}
-- Live overlay frames, REUSED. WoW never reclaims a frame once created, so
-- building a fresh set on every ApplyAll (which a slider drag fires ~60 times a
-- second) parked thousands of dead frames in memory for the rest of the
-- session. The pool holds one entry per index: the Nth enabled overlay always
-- draws through framePool[N], and any surplus is parked, not discarded.
local framePool    = {}
local defaultLevel            -- WoW's natural frame level for a UIParent child
local inCombat     = false
local hasTarget    = false
local isCasting    = false

-- ============================================================
-- Profile API
-- ============================================================

function GloomsOverlays_GetProfile()
    local name = (VibeOverlayDBChar and VibeOverlayDBChar.activeProfile) or "Default"
    local p = VibeOverlayDB.profiles[name]
    if not p then
        VibeOverlayDB.profiles[name] = { overlays = {} }
        p = VibeOverlayDB.profiles[name]
    end
    return p
end

function GloomsOverlays_GetActiveProfileName()
    return (VibeOverlayDBChar and VibeOverlayDBChar.activeProfile) or "Default"
end

function GloomsOverlays_SetActiveProfile(name)
    VibeOverlayDBChar.activeProfile = name
    GloomsOverlays_ApplyAll()
end

function GloomsOverlays_GetProfileNames()
    local names = {}
    for k in pairs(VibeOverlayDB.profiles) do
        names[#names+1] = k
    end
    table.sort(names)
    return names
end

function GloomsOverlays_NewProfile(name, copyFrom)
    if VibeOverlayDB.profiles[name] then return false, "Profile already exists" end
    if copyFrom and VibeOverlayDB.profiles[copyFrom] then
        local src = VibeOverlayDB.profiles[copyFrom]
        local new = { overlays = {} }
        for _, ov in ipairs(src.overlays) do
            local copy = {}
            for k, v in pairs(ov) do
                if type(v) == "table" then
                    local t2 = {}
                    for k2, v2 in pairs(v) do t2[k2] = v2 end
                    copy[k] = t2
                else
                    copy[k] = v
                end
            end
            new.overlays[#new.overlays+1] = copy
        end
        VibeOverlayDB.profiles[name] = new
    else
        VibeOverlayDB.profiles[name] = { overlays = {} }
    end
    return true
end

function GloomsOverlays_DeleteProfile(name)
    if name == "Default" then return false, "Cannot delete Default profile" end
    VibeOverlayDB.profiles[name] = nil
    if VibeOverlayDBChar.activeProfile == name then
        VibeOverlayDBChar.activeProfile = "Default"
    end
    return true
end

function GloomsOverlays_RenameProfile(oldName, newName)
    if oldName == "Default" then return false, "Cannot rename Default profile" end
    if VibeOverlayDB.profiles[newName] then return false, "Profile name already taken" end
    VibeOverlayDB.profiles[newName] = VibeOverlayDB.profiles[oldName]
    VibeOverlayDB.profiles[oldName] = nil
    if VibeOverlayDBChar.activeProfile == oldName then
        VibeOverlayDBChar.activeProfile = newName
    end
    return true
end

-- ============================================================
-- Condition evaluation
-- ============================================================

local function ShouldShow(ov)
    local c = ov.condition or "always"
    for word in c:gmatch("[^,]+") do
        if word == "always"   then return true end
        if word == "combat"   and inCombat      then return true end
        if word == "nocombat" and not inCombat  then return true end
        if word == "target"   and hasTarget     then return true end
        if word == "casting"  and isCasting     then return true end
    end
    return false
end

-- ============================================================
-- Build a single live overlay frame
-- ============================================================

-- The frame level an overlay draws at when it has never set one. Captured from
-- the first pool frame; the fallback is WoW's documented parent+1 rule, for the
-- case where the editor asks before any overlay has been built.
function GloomsOverlays_GetDefaultLevel()
    return defaultLevel or ((UIParent:GetFrameLevel() or 0) + 1)
end

-- Hand out framePool[index], creating it the first time. The name is the INDEX,
-- not the overlay's name: it never changes, so _G gains one entry per slot
-- instead of one per rebuild. Nothing reads these names — they exist for the
-- frame stack in debuggers.
local function AcquireFrame(index)
    local slot = framePool[index]
    if slot then return slot.frame, slot.tex end

    local f = CreateFrame("Frame", "GloomsOverlays_Live_" .. index, UIParent)
    f:EnableMouse(false)
    -- Whatever level WoW hands a fresh UIParent child is the level EVERY overlay
    -- used to draw at, so it is the right default for one that has never set
    -- `level`. Read it rather than assuming the parent+1 rule, and capture it
    -- once — a recycled frame's level is whatever its last occupant chose.
    defaultLevel = defaultLevel or f:GetFrameLevel()
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(f)
    framePool[index] = { frame = f, tex = tex }
    return f, tex
end

local function BuildOverlayFrame(ov, index)
    local f, tex = AcquireFrame(index)

    -- ★ RESET whatever the PREVIOUS occupant of this slot left behind. Every
    -- property set CONDITIONALLY below has to be cleared here, or it leaks from
    -- one overlay onto the next: the animation script (spritesheets AND spin),
    -- the texture itself, its crop (spritesheet frame / atlas / flip) and its
    -- rotation. The unconditional ones — size, point, strata, blend, alpha,
    -- vertex color — need no reset because they are always reassigned.
    f:SetScript("OnUpdate", nil)
    tex:SetTexture(nil)
    tex:SetTexCoord(0, 1, 0, 1)
    tex:SetRotation(0)

    f:SetSize(math.max(1, ov.width or 200), math.max(1, ov.height or 200))
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", ov.x or 0, ov.y or 0)
    f:SetFrameStrata(ov.strata or "HIGH")
    -- Level orders overlays WITHIN a strata (strata always wins). Set after the
    -- strata, and always — a recycled frame carries its last occupant's level.
    f:SetFrameLevel(ov.level or GloomsOverlays_GetDefaultLevel())

    local t  = ov.texture or ""
    local sh = ov.sheet

    if sh and sh.fileID then
        tex:SetTexture(sh.fileID)
        local cols   = sh.cols or 1
        local rows   = sh.rows or 1
        local uRange = (sh.uRight or 1) - (sh.uLeft or 0)
        local vRange = (sh.vBottom or 1) - (sh.vTop or 0)
        local cw, rh = uRange / cols, vRange / rows
        tex:SetTexCoord(sh.uLeft, sh.uLeft + cw, sh.vTop, sh.vTop + rh)

        local fps      = sh.fps or 15
        local frameDur = 1 / math.max(1, fps)
        local total    = math.max(1, math.min(sh.frames or (cols * rows), cols * rows))
        local elapsed, frame = 0, 0

        f:SetScript("OnUpdate", function(_, dt)
            elapsed = elapsed + dt
            if elapsed >= frameDur then
                elapsed = elapsed - frameDur
                frame   = (frame + 1) % total
                local col = frame % cols
                local row = math.floor(frame / cols)
                tex:SetTexCoord(
                    sh.uLeft + col       * cw, sh.uLeft + (col + 1) * cw,
                    sh.vTop  + row       * rh, sh.vTop  + (row + 1) * rh)
            end
        end)
    else
        local ul, ur, ut, ub = 0, 1, 0, 1

        local mediaPath = GloomsHub and GloomsHub.ResolveAssetPath and GloomsHub:ResolveAssetPath(t)
        local numID  = tonumber(t)
        if mediaPath then
            tex:SetTexture(mediaPath)
        elseif numID then
            tex:SetTexture(numID)
        elseif t ~= "" then
            local info = C_Texture.GetAtlasInfo(t)
            if info then
                tex:SetTexture(info.file)
                ul = info.leftTexCoord
                ur = info.rightTexCoord
                ut = info.topTexCoord
                ub = info.bottomTexCoord
            else
                tex:SetTexture(t)
            end
        end

        if ov.flipH then ul, ur = ur, ul end
        if ov.flipV then ut, ub = ub, ut end
        tex:SetTexCoord(ul, ur, ut, ub)
    end

    tex:SetBlendMode(ov.blendMode or "BLEND")
    tex:SetAlpha(ov.alpha or 1.0)
    tex:SetVertexColor(ov.tintR or 1, ov.tintG or 1, ov.tintB or 1)

    local startRad  = math.rad(ov.rotation or 0)
    local spinSpeed = ov.spinSpeed or 0
    local spinDir   = ov.spinDir or "cw"

    if spinSpeed ~= 0 then
        local radsPerSec = math.rad(spinSpeed) * (spinDir == "ccw" and -1 or 1)
        local angle = startRad
        local existingOnUpdate = f:GetScript("OnUpdate")
        if existingOnUpdate then
            f:SetScript("OnUpdate", function(self, dt)
                existingOnUpdate(self, dt)
                angle = angle + radsPerSec * dt
                tex:SetRotation(angle)
            end)
        else
            f:SetScript("OnUpdate", function(_, dt)
                angle = angle + radsPerSec * dt
                tex:SetRotation(angle)
            end)
        end
    else
        if startRad ~= 0 then tex:SetRotation(startRad) end
    end

    -- SetShown, not Hide: a recycled slot may have come back hidden, and a
    -- hidden frame never runs its OnUpdate, so a spinning overlay would sit
    -- frozen. (WoW skipping OnUpdate on hidden frames is also why a parked
    -- frame costs nothing per frame.)
    f:SetShown(ShouldShow(ov))

    return f, tex
end

-- ============================================================
-- GloomsOverlays_ApplyAll
-- ============================================================

-- Park every slot from `index` up: the overlays that used to own them are gone
-- (switched off, deleted, or a smaller profile is now active). Parked frames
-- keep their place in the pool for the next ApplyAll.
local function ParkFramesFrom(index)
    for i = index, #framePool do
        local slot = framePool[i]
        slot.frame:Hide()
        slot.frame:SetScript("OnUpdate", nil)   -- stop animating something nothing points at
        slot.tex:SetTexture(nil)                -- and let go of the texture's memory
    end
end

function GloomsOverlays_ApplyAll()
    wipe(liveOverlays)

    local profile = VibeOverlayDB and GloomsOverlays_GetProfile()
    if not profile then return ParkFramesFrom(1) end

    -- `n` walks the POOL, not the overlay list: switched-off overlays take no
    -- slot, so the enabled ones always occupy 1..n with no gaps.
    local n = 0
    for _, ov in ipairs(profile.overlays) do
        if ov.enabled ~= false then
            n = n + 1
            local f, tex = BuildOverlayFrame(ov, n)
            liveOverlays[ov.name] = { frame=f, tex=tex, config=ov }
        end
    end
    ParkFramesFrom(n + 1)
end

-- ============================================================
-- GloomsOverlays_ApplyLayout — the live path for the editor's WHERE controls
--
-- ApplyAll reconfigures EVERY overlay in the profile — re-resolving each
-- texture name through the Hub, re-cropping it and re-wiring its animation —
-- which is a lot of work to repeat ~60 times a second for the whole profile
-- while ONE overlay's size slider is being dragged. Size, position, strata and
-- level are the fields that can be re-applied in place instead, which is what
-- this does. Anything that changes the ART or the animation (texture, flip,
-- rotation, spin) still needs the full ApplyAll.
-- (Frame CHURN used to be the bigger cost here; the pool above fixed that.)
--
-- No live frame (the overlay is switched off, or two overlays share a name so
-- only one owns the key) means there is nothing on screen to move: the caller
-- has already written the value, and the next ApplyAll picks it up.
-- ============================================================

function GloomsOverlays_ApplyLayout(ov)
    if not ov then return end
    local entry = liveOverlays[ov.name]
    local f = entry and entry.frame
    if not f then return end
    f:SetSize(math.max(1, ov.width or 200), math.max(1, ov.height or 200))
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", ov.x or 0, ov.y or 0)
    f:SetFrameStrata(ov.strata or "HIGH")
    f:SetFrameLevel(ov.level or GloomsOverlays_GetDefaultLevel())
end

-- ============================================================
-- Update visibility on state changes
-- ============================================================

local function UpdateVisibility()
    for _, entry in pairs(liveOverlays) do
        if ShouldShow(entry.config) then
            entry.frame:Show()
        else
            entry.frame:Hide()
        end
    end
end

-- ============================================================
-- MAIN INIT
-- ============================================================

local mainFrame = CreateFrame("Frame", "GloomsOverlaysMain", UIParent)
mainFrame:RegisterEvent("PLAYER_LOGIN")
mainFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
mainFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
mainFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
mainFrame:RegisterEvent("UNIT_SPELLCAST_START")
mainFrame:RegisterEvent("UNIT_SPELLCAST_STOP")
mainFrame:RegisterEvent("UNIT_SPELLCAST_FAILED")
mainFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
mainFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
mainFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")

mainFrame:SetScript("OnEvent", function(self, event, unit)
    if event == "PLAYER_LOGIN" then
        if not VibeOverlayDBChar then VibeOverlayDBChar = {} end
        if not VibeOverlayDBChar.activeProfile then VibeOverlayDBChar.activeProfile = "Default" end

        if not VibeOverlayDB then VibeOverlayDB = {} end

        -- One-time migration: fold old flat structure into Default profile
        if VibeOverlayDB.overlays and not VibeOverlayDB.profiles then
            VibeOverlayDB.profiles = {
                ["Default"] = { overlays = VibeOverlayDB.overlays }
            }
            VibeOverlayDB.overlays = nil
            print("|cff936bffGloom's Overlays|r: migrated overlays to Default profile.")
        end

        if not VibeOverlayDB.profiles then VibeOverlayDB.profiles = {} end
        if not VibeOverlayDB.profiles["Default"] then
            VibeOverlayDB.profiles["Default"] = { overlays = {} }
        end

        inCombat  = UnitAffectingCombat("player")
        hasTarget = UnitExists("target")
        isCasting = (UnitCastingInfo("player") ~= nil) or (UnitChannelInfo("player") ~= nil)
        GloomsOverlays_ApplyAll()
        print("|cff936bffGloom's Overlays|r loaded. |cffcccccc/go|r opens the Overlays tab.")

    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        UpdateVisibility()

    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        UpdateVisibility()

    elseif event == "PLAYER_TARGET_CHANGED" then
        hasTarget = UnitExists("target")
        UpdateVisibility()

    elseif event == "UNIT_SPELLCAST_START"
        or event == "UNIT_SPELLCAST_CHANNEL_START" then
        if unit == "player" then
            isCasting = true
            UpdateVisibility()
        end

    elseif event == "UNIT_SPELLCAST_STOP"
        or event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_INTERRUPTED"
        or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if unit == "player" then
            isCasting = false
            UpdateVisibility()
        end
    end
end)

-- ============================================================
-- SLASH COMMANDS
-- ============================================================

-- Phase E gate B: the config renders ONLY inside the Suite window (the Overlays
-- tab). Bare `/go` toggles that tab — the family pattern (`/gb`, `/ga`); the
-- shell owns open/close/switch semantics (CONTRACTS §2). `list`, `debug` and
-- `reload` stay chat-only. The old PLAYER_LOGIN slash-wrapping in
-- GloomsOverlays_Preview.lua is gone: every branch lives here now.
SLASH_GLOOMSOVERLAYS1 = "/go"
SlashCmdList["GLOOMSOVERLAYS"] = function(msg)
    msg = msg and msg:lower():match("^%s*(.-)%s*$") or ""

    if msg == "" or msg == "overlays" or msg == "o" or msg == "config" then
        GloomsHub:ToggleWindow("overlays")

    elseif msg == "preview" or msg == "p" then
        if GloomsOverlays_ToggleAssetBrowser then GloomsOverlays_ToggleAssetBrowser() end

    elseif msg == "reload" then
        ReloadUI()

    elseif msg == "list" then
        local profile  = GloomsOverlays_GetProfile()
        local overlays = profile and profile.overlays or {}
        print("|cff936bffGloom's Overlays|r — profile: |cffcccccc" .. GloomsOverlays_GetActiveProfileName() .. "|r — " .. #overlays .. " overlay(s):")
        for i, ov in ipairs(overlays) do
            local state = (ov.enabled ~= false) and "|cff00ff00on|r" or "|cffaaaaaa off|r"
            print(string.format("  %d. %s [%s]", i, ov.name or "?", state))
        end

    elseif msg == "debug" then
        local profile  = GloomsOverlays_GetProfile()
        local overlays = profile and profile.overlays or {}
        local liveCount = 0
        for _ in pairs(liveOverlays) do liveCount = liveCount + 1 end
        print("|cff9966ffGloomsOverlays DEBUG|r — profile: " .. GloomsOverlays_GetActiveProfileName() .. " — " .. #overlays .. " saved, " .. liveCount .. " live, combat=" .. tostring(inCombat))
        for name, entry in pairs(liveOverlays) do
            local fr    = entry.frame
            local shown = fr:IsShown() and "|cff00ff00SHOWN|r" or "|cffff4444HIDDEN|r"
            local x, y  = fr:GetCenter()
            local w, h  = fr:GetSize()
            print(string.format("  [%s] %s  center=(%.0f,%.0f) size=%dx%d alpha=%.2f condition=%s",
                name, shown, x or -1, y or -1, w, h,
                entry.tex:GetAlpha(), entry.config.condition or "always"))
        end
        if next(liveOverlays) == nil then
            print("  (no live frames)")
        end

    else
        print("|cff936bffGloom's Overlays|r commands:")
        print("  |cffcccccc/go|r                         — open the Overlays tab")
        print("  |cffcccccc/go preview|r   (or /go p)    — open the asset browser")
        print("  |cffcccccc/go list|r                    — list overlays in chat")
        print("  |cffcccccc/go debug|r                   — print live frame info")
        print("  |cffcccccc/go reload|r                  — reload the UI")
    end
end
