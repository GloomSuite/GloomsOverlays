-- ============================================================
-- GloomsOverlays.lua — Gloom's UI (the folder keeps its old name: see the TOC)
-- Core overlay engine. Overlays stored in VibeOverlayDB.
-- Per-character active profile stored in VibeOverlayDBChar.
-- ★ GLOOM'S UI (2026-09-29, the owner): Portraits folded in as one more overlay
-- TYPE (`ov.kind = "portrait"`, drawn by GloomsOverlays_Portraits.lua; nil =
-- a texture, every overlay saved before), and GROUPS: `profile.groups` =
-- { id, name, x, y, collapsed }, and a member's `ov.group` = the id — its x/y
-- are then an OFFSET from the group's anchor, so moving the group moves them
-- all (Unit Frames' unit + pieces). The old Portraits settings were NOT
-- carried over (the owner: he rebuilds them).
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

local function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = DeepCopy(x) end
    return t
end

function GloomsOverlays_NewProfile(name, copyFrom)
    if VibeOverlayDB.profiles[name] then return false, "Profile already exists" end
    if copyFrom and VibeOverlayDB.profiles[copyFrom] then
        -- every overlay AND every group (a member's `group` id stays valid)
        VibeOverlayDB.profiles[name] = DeepCopy(VibeOverlayDB.profiles[copyFrom])
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
-- Groups — a shared anchor; a member's x/y are an offset from it
-- ============================================================

function GloomsOverlays_GetGroups()
    local p = GloomsOverlays_GetProfile()
    p.groups = p.groups or {}
    return p.groups
end

function GloomsOverlays_FindGroup(id)
    if id == nil or not VibeOverlayDB then return nil end
    for _, g in ipairs(GloomsOverlays_GetGroups()) do
        if g.id == id then return g end
    end
end

function GloomsOverlays_NewGroup(name)
    local p = GloomsOverlays_GetProfile()
    local groups = GloomsOverlays_GetGroups()
    -- ids never repeat within a profile, so a stale `ov.group` can't adopt a new group
    local id = p.nextGroup or 1
    for _, g in ipairs(groups) do if (g.id or 0) >= id then id = g.id + 1 end end
    p.nextGroup = id + 1
    local g = { id = id, name = name, x = 0, y = 0 }
    groups[#groups + 1] = g
    return g
end

function GloomsOverlays_GroupMembers(g)
    local out = {}
    if not g then return out end
    for _, ov in ipairs(GloomsOverlays_GetProfile().overlays) do
        if ov.group == g.id then out[#out + 1] = ov end
    end
    return out
end

-- ★ ATTACHING AND SCALING A GROUP (2026-09-30, the owner). A group may be
-- ATTACHED to a frame another tool offers (the Hub's Anchors.lua — Unit
-- Frames' Player / Target Frame): `g.attach` = the anchor's id (nil = the
-- screen). Its x / y are then measured from that frame's CENTRE, and every
-- member is pinned to the frame itself, so moving the unit frame moves them
-- LIVE, mid-drag too. `g.hideWithAnchor`: the members show only while that
-- frame does. `g.scale` (nil = 1) multiplies every member's size AND its
-- offset from the group's anchor. Strata and level stay each overlay's own.

-- What a group is pinned to: the anchor's frame, or the screen.
function GloomsOverlays_GroupRel(g)
    local f = g and g.attach and GloomsHub.AnchorFrame and GloomsHub:AnchorFrame(g.attach)
    return f or UIParent, f ~= nil
end
local function GroupScale(g) return (g and g.scale) or 1 end

-- Where a frame's centre is, from the screen's centre, in UIParent units.
local function CenterOffset(f)
    if f == UIParent then return 0, 0 end
    local cx, cy = f:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (cx and ux) then return 0, 0 end
    local k = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return cx * k - ux, cy * k - uy
end
-- An offering tool's frames arrived after we placed things (Unit Frames loads
-- after us): place everything again, so an attached group finds its frame.
if GloomsHub.OnAnchorsChanged then
    GloomsHub:OnAnchorsChanged(function() if VibeOverlayDB and VibeOverlayDB.profiles then GloomsOverlays_ApplyAll() end end)
end

-- A group's anchor point on the screen (from the screen's centre).
function GloomsOverlays_GroupOrigin(g)
    local ax, ay = CenterOffset((GloomsOverlays_GroupRel(g)))
    return ax + (g.x or 0), ay + (g.y or 0)
end

-- Where an overlay is PINNED: the frame, and its offset from that frame's centre.
function GloomsOverlays_Place(ov)
    local g = ov.group and GloomsOverlays_FindGroup(ov.group)
    if not g then return UIParent, ov.x or 0, ov.y or 0 end
    local k = GroupScale(g)
    return (GloomsOverlays_GroupRel(g)), (g.x or 0) + (ov.x or 0) * k, (g.y or 0) + (ov.y or 0) * k
end
-- Where an overlay SITS on screen (from the screen's centre).
function GloomsOverlays_Pos(ov)
    local rel, x, y = GloomsOverlays_Place(ov)
    local ax, ay = CenterOffset(rel)
    return ax + x, ay + y
end

-- An overlay's box: a texture's width x height, a portrait's square — times
-- its group's scale.
function GloomsOverlays_BoxSize(ov)
    local g = ov.group and GloomsOverlays_FindGroup(ov.group)
    local k = GroupScale(g)
    if ov.kind == "portrait" then
        local s = math.max(1, ov.size or 350) * k
        return s, s
    end
    return math.max(1, ov.width or 200) * k, math.max(1, ov.height or 200) * k
end

-- Into a group (nil = out of any), KEEPING its place on screen: the offset is
-- re-based on the new group's anchor (and its scale).
function GloomsOverlays_SetGroup(ov, id)
    local x, y = GloomsOverlays_Pos(ov)
    local g = id and GloomsOverlays_FindGroup(id)
    ov.group = g and g.id or nil
    if g then
        local ox, oy = GloomsOverlays_GroupOrigin(g)
        local k = GroupScale(g)
        ov.x = math.floor((x - ox) / k + 0.5)
        ov.y = math.floor((y - oy) / k + 0.5)
    else
        ov.x, ov.y = math.floor(x + 0.5), math.floor(y + 0.5)
    end
end

-- Attach a group to an anchor (nil = the screen), KEEPING it where it is.
function GloomsOverlays_SetAttach(g, id)
    local ox, oy = GloomsOverlays_GroupOrigin(g)
    g.attach = id
    local ax, ay = CenterOffset((GloomsOverlays_GroupRel(g)))
    g.x, g.y = math.floor(ox - ax + 0.5), math.floor(oy - ay + 0.5)
end

-- Delete a group; its members stay where they are, ungrouped.
function GloomsOverlays_DeleteGroup(g)
    for _, ov in ipairs(GloomsOverlays_GroupMembers(g)) do GloomsOverlays_SetGroup(ov, nil) end
    local groups = GloomsOverlays_GetGroups()
    for i, gg in ipairs(groups) do if gg == g then table.remove(groups, i); break end end
end

-- ============================================================
-- Condition evaluation
-- ============================================================

-- PREVIEW (2026-09-27, the owner: a lit eye should show the overlay NOW, out
-- of combat too, while the windows are open — Auras' eye). While the windows
-- are open, the eye alone decides: lit shows it whatever its conditions say —
-- even one switched off — and unlit hides it, even an Always Visible one
-- (2026-09-29, Auras' rule). Closing the windows ends it; conditions rule
-- again. The eye (the owner, 2026-09-27, as Auras'): `ov.preview` is saved and
-- is the overlay's state while NOT selected; the SELECTED one shows at once
-- whatever that says (`pickShow`, fresh on every new selection), and its eye
-- toggles only that — deselected, it goes back to its saved eye.
local previewing, pick, pickShow = false, nil, true
function GloomsOverlays_EyeOn(ov)
    if not ov then return false end
    if ov == pick then return pickShow end
    return ov.preview == true
end
local function Previewed(ov) return previewing and GloomsOverlays_EyeOn(ov) end
function GloomsOverlays_SetPreview(on) previewing = on and true or false; GloomsOverlays_ApplyAll() end
function GloomsOverlays_SetPick(ov)
    if ov ~= pick then pick, pickShow = ov, true end
    GloomsOverlays_ApplyAll()
end
function GloomsOverlays_ToggleEye(ov)
    if not ov then return end
    if ov == pick then pickShow = not pickShow else ov.preview = (not ov.preview) or nil end
    GloomsOverlays_ApplyAll()
end

-- A group's eye sets every member's at once.
function GloomsOverlays_SetEye(ov, on)
    if not ov then return end
    if ov == pick then pickShow = on and true or false else ov.preview = on and true or nil end
end

-- ★ A GROUP CAN BE SWITCHED OFF (2026-09-30, the owner: "create a group that is
-- an entire UI setup... and then just disable it to create/try out another one,
-- without having to screw around with profiles"). `g.enabled == false` does to
-- every member what an overlay's own Off does: never shown in play, settings
-- kept; while the windows are open the eyes still decide (Previewed), exactly
-- like a switched-off overlay. nil = on, so every existing group stays on.
function GloomsOverlays_GroupOff(ov)
    local g = ov and ov.group and GloomsOverlays_FindGroup(ov.group)
    return g ~= nil and g.enabled == false
end

-- an attached group set to show only with its frame
local function AnchorHides(ov)
    local g = ov.group and GloomsOverlays_FindGroup(ov.group)
    if not (g and g.attach and g.hideWithAnchor) then return false end
    local f = GloomsHub.AnchorFrame and GloomsHub:AnchorFrame(g.attach)
    return f ~= nil and not f:IsVisible()
end

-- ANY (the default) passes while one checked condition is true; ALL only while
-- every one is (`condMatch = "all"`, 2026-10-01, the owner). Always Visible is
-- simply true, so under All it asks nothing of the others. Used by an overlay
-- and by its group alike.
local function CondPass(c, all)
    for word in c:gmatch("[^,]+") do
        local met = word == "always"
            or (word == "combat"   and inCombat)
            or (word == "nocombat" and not inCombat)
            or (word == "target"   and hasTarget)
            or (word == "casting"  and isCasting)
        if met and not all then return true end
        if not met and all then return false end
    end
    return all
end

-- ★ WHAT THE GROUP ADDS (2026-10-05, the owner: a group's Visibility and a
-- member's can disagree, and nothing on the member said so). There are only
-- three states behind the conditions — combat, target, casting — so whether a
-- member can EVER show with its group is answered exactly, by trying all eight.
local COND_WORDS = { always = "Always Visible", combat = "In Combat", nocombat = "Out of Combat",
                     target = "Target Selected", casting = "While Casting" }
local function PassAt(c, all, st)
    for word in c:gmatch("[^,]+") do
        local met = word == "always" or (word == "combat" and st.combat) or (word == "nocombat" and not st.combat)
            or (word == "target" and st.target) or (word == "casting" and st.casting)
        if met and not all then return true end
        if not met and all then return false end
    end
    return all
end
-- a group's Visibility in words (nil = it limits nothing)
function GloomsOverlays_GroupRuleWords(g)
    if not (g and g.condition) then return nil end
    local all = g.condMatch == "all"
    local o = {}
    for word in g.condition:gmatch("[^,]+") do
        -- Always Visible limits nothing: under Any it lets everything through,
        -- under All it is simply true
        if word == "always" then if not all then return nil end
        else o[#o + 1] = COND_WORDS[word] or word end
    end
    if #o == 0 then return nil end
    return table.concat(o, all and " and " or " or ")
end
-- why an overlay can never show with its group's Visibility (nil = it can)
function GloomsOverlays_NeverShows(ov)
    local g = ov and ov.group and GloomsOverlays_FindGroup(ov.group)
    if not (g and g.condition) then return nil end
    local needTarget = ov.kind == "portrait" and ov.unit == "target"
    for _, combat in ipairs({ false, true }) do
        for _, target in ipairs({ false, true }) do
            for _, casting in ipairs({ false, true }) do
                local st = { combat = combat, target = target, casting = casting }
                if (target or not needTarget)
                    and PassAt(g.condition, g.condMatch == "all", st)
                    and PassAt(ov.condition or "always", ov.condMatch == "all", st) then return nil end
            end
        end
    end
    return "Never shows: its own Visibility and its group's can't both be true at once."
end

local function ShouldShow(ov)
    -- ★ While the windows are open the EYE decides, both ways (2026-09-29, the
    -- owner: "when the eye is off and the addon is open, the aura is NOT
    -- displayed" — Auras' rule, D:RefreshForced). The Overlays port of
    -- 2026-09-27 only ever ADDED, so an Always Visible overlay couldn't be
    -- hidden while placing others. Closing the windows hands back to the
    -- conditions below.
    if previewing then return GloomsOverlays_EyeOn(ov) end
    if AnchorHides(ov) then return false end
    -- Hide When Mounted (2026-10-04, the owner): wins over every condition below
    if ov.hideMounted and IsMounted and IsMounted() then return false end
    -- ★ THE GROUP'S VISIBILITY (2026-10-04, the owner): a gate IN FRONT of each
    -- member — it can only narrow, never widen (Auras' group load rule). A member
    -- shows only while its group's conditions AND its own both pass; either one
    -- hides it. A group that never set any (condition nil) gates nothing.
    local g = ov.group and GloomsOverlays_FindGroup(ov.group)
    if g then
        if g.hideMounted and IsMounted and IsMounted() then return false end
        if g.condition and not CondPass(g.condition, g.condMatch == "all") then return false end
    end
    return CondPass(ov.condition or "always", ov.condMatch == "all")
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

    f:SetSize(GloomsOverlays_BoxSize(ov))
    f:ClearAllPoints()
    do local rel, x, y = GloomsOverlays_Place(ov); f:SetPoint("CENTER", rel, "CENTER", x, y) end
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

local RefreshHandles   -- the drag handles (below)

function GloomsOverlays_ApplyAll()
    wipe(liveOverlays)

    local profile = VibeOverlayDB and GloomsOverlays_GetProfile()
    if not profile then
        ParkFramesFrom(1)
        if addon.PR then addon.PR.ParkFrom(1) end
        return
    end

    -- `n` walks the POOL, not the overlay list: switched-off overlays take no
    -- slot, so the enabled ones always occupy 1..n with no gaps. Portraits
    -- have their own pool (a model and a portrait frame each), walked by `pn`.
    -- ★ Keyed by the overlay's TABLE, not its name: two overlays may share a name.
    local n, pn = 0, 0
    for _, ov in ipairs(profile.overlays) do
        if (ov.enabled ~= false and not GloomsOverlays_GroupOff(ov)) or Previewed(ov) then
            if ov.kind == "portrait" then
                if addon.PR then
                    pn = pn + 1
                    liveOverlays[ov] = addon.PR.Build(ov, pn, ShouldShow(ov))
                end
            else
                n = n + 1
                local f, tex = BuildOverlayFrame(ov, n)
                liveOverlays[ov] = { frame=f, tex=tex, config=ov }
            end
        end
    end
    ParkFramesFrom(n + 1)
    if addon.PR then addon.PR.ParkFrom(pn + 1) end
    -- an attached group that hides with its frame hears the frame show / hide
    for _, g in ipairs(profile.groups or {}) do
        local f = g.attach and g.hideWithAnchor and GloomsHub.AnchorFrame and GloomsHub:AnchorFrame(g.attach)
        if f and not f.gloomsOverlaysHooked then
            f.gloomsOverlaysHooked = true
            f:HookScript("OnShow", function() if addon.UpdateVisibility then addon.UpdateVisibility() end end)
            f:HookScript("OnHide", function() if addon.UpdateVisibility then addon.UpdateVisibility() end end)
        end
    end
    RefreshHandles()
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
    local entry = liveOverlays[ov]
    if entry and entry.slot then
        addon.PR.Layout(entry.slot, ov)
    elseif entry and entry.frame then
        local f = entry.frame
        f:SetSize(GloomsOverlays_BoxSize(ov))
        f:ClearAllPoints()
        local rel, x, y = GloomsOverlays_Place(ov)
        f:SetPoint("CENTER", rel, "CENTER", x, y)
        f:SetFrameStrata(ov.strata or "HIGH")
        f:SetFrameLevel(ov.level or GloomsOverlays_GetDefaultLevel())
    end
    RefreshHandles()
end

-- A GROUP moved: re-place every member.
function GloomsOverlays_ApplyGroupLayout(g)
    for _, ov in ipairs(GloomsOverlays_GroupMembers(g)) do GloomsOverlays_ApplyLayout(ov) end
    RefreshHandles()
end

-- ============================================================
-- Update visibility on state changes
-- ============================================================

local function UpdateVisibility()
    for ov, entry in pairs(liveOverlays) do
        if entry.slot then
            addon.PR.Show(entry.slot, ShouldShow(ov))
        else
            entry.frame:SetShown(ShouldShow(ov))
        end
    end
end
addon.UpdateVisibility = UpdateVisibility

-- ============================================================
-- DRAG HANDLES (Gloom's UI, 2026-09-29 — Unit Frames' per-piece dragging).
-- While the windows are open, the SELECTED overlay wears a lime outline and
-- its group a green box around every member; drag the outline to move just
-- that overlay, the box to move the whole group. Letting go keeps the whole
-- units the drag landed on; nothing else changes. Closing the windows hides
-- both, and nothing on screen takes the mouse again.
-- ★ Moved from the SAVED numbers, never from what a frame reports — the rule
-- Unit Frames learned from a secret-geometry BugSack (Hub FINDINGS §21).
-- ============================================================

local editItem, editGroup     -- what the windows have selected (nil = locked)
local moveListeners = {}
function GloomsOverlays_OnMoved(fn) moveListeners[#moveListeners + 1] = fn end

local function Cursor()
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    return x / s, y / s
end

local function MakeHandle(r, g, b, level)
    local h = CreateFrame("Frame", nil, UIParent)
    h:SetFrameStrata("HIGH"); h:SetFrameLevel(level)
    h:EnableMouse(true); h:Hide()
    -- ★ CORNER BRACKETS, 10 px outside (2026-09-30, the owner: the box "is
    -- actually in the way" of precise positioning) — the Hub's UI.gBrackets. The
    -- handle keeps the item's own size, so the drag area is unchanged.
    GloomsHub.UI.gBrackets(h, r, g, b, 0.9)
    -- h.target() → the table whose x/y the drag writes; h.apply(t) re-places it
    local function finish(self)
        self:SetScript("OnUpdate", nil)
        if not self.moving then return end
        self.moving = false
        for _, fn in ipairs(moveListeners) do fn() end
        RefreshHandles()
    end
    h:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local t = self.target and self.target()
        if not t then return end
        local cx, cy = Cursor()
        local ox, oy = t.x or 0, t.y or 0
        self.moving = true
        self:SetScript("OnUpdate", function(me)
            if not IsMouseButtonDown("LeftButton") then finish(me); return end
            local x, y = Cursor()
            local k = me.scaleOf and me.scaleOf(t) or 1
            t.x = math.floor(ox + (x - cx) / k + 0.5)
            t.y = math.floor(oy + (y - cy) / k + 0.5)
            me.apply(t)
            for _, fn in ipairs(moveListeners) do fn(true) end
        end)
    end)
    h:SetScript("OnMouseUp", function(self) finish(self) end)
    return h
end

local itemHandle, groupHandle
local function InProfile(ov)
    if not (ov and VibeOverlayDB) then return false end
    for _, o in ipairs(GloomsOverlays_GetProfile().overlays) do if o == ov then return true end end
    return false
end

RefreshHandles = function()
    if not (itemHandle and groupHandle) then return end
    local ov = InProfile(editItem) and editItem or nil
    local g = editGroup and GloomsOverlays_FindGroup(editGroup.id) == editGroup and editGroup
        or (ov and ov.group and GloomsOverlays_FindGroup(ov.group)) or nil
    if ov then
        local w, h = GloomsOverlays_BoxSize(ov)
        local rel, x, y = GloomsOverlays_Place(ov)
        itemHandle:SetSize(w, h)
        itemHandle:ClearAllPoints()
        itemHandle:SetPoint("CENTER", rel, "CENTER", x, y)
        itemHandle:Show()
    elseif not itemHandle.moving then
        itemHandle:Hide()
    end
    if g then
        -- the box around every member (4 out), pinned where the group is pinned;
        -- an empty group is a 40 square at its anchor
        local rel = GloomsOverlays_GroupRel(g)
        local l, r, b, t
        for _, m in ipairs(GloomsOverlays_GroupMembers(g)) do
            local _, x, y = GloomsOverlays_Place(m)
            local w, h = GloomsOverlays_BoxSize(m)
            l = math.min(l or math.huge, x - w / 2); r = math.max(r or -math.huge, x + w / 2)
            b = math.min(b or math.huge, y - h / 2); t = math.max(t or -math.huge, y + h / 2)
        end
        local gx, gy = g.x or 0, g.y or 0
        if not l then l, r, b, t = gx - 20, gx + 20, gy - 20, gy + 20
        else l, r, b, t = l - 4, r + 4, b - 4, t + 4 end
        groupHandle:SetSize(r - l, t - b)
        groupHandle:ClearAllPoints()
        groupHandle:SetPoint("CENTER", rel, "CENTER", (l + r) / 2, (b + t) / 2)
        groupHandle.group = g
        groupHandle:Show()
    elseif not groupHandle.moving then
        groupHandle:Hide()
    end
end

-- ARROW-KEY NUDGES (the Hub's Undo.lua key frame, 2026-09-30): move a group,
-- or one overlay, by (dx, dy) SCREEN pixels. A member of a scaled group moves
-- 1/scale of its own offset units, so a press is one pixel on screen.
function GloomsOverlays_Nudge(t, dx, dy)
    if not t then return end
    if t.overlays == nil and t.id and t.name and GloomsOverlays_FindGroup(t.id) == t then
        t.x, t.y = (t.x or 0) + dx, (t.y or 0) + dy
        GloomsOverlays_ApplyGroupLayout(t)
    else
        local g = t.group and GloomsOverlays_FindGroup(t.group)
        local k = (g and g.scale) or 1
        t.x, t.y = (t.x or 0) + dx / k, (t.y or 0) + dy / k
        GloomsOverlays_ApplyLayout(t)
    end
    for _, fn in ipairs(moveListeners) do fn(true) end
end

-- The windows call this on every selection, and with nothing when they close.
function GloomsOverlays_SetEditing(ov, group)
    if not itemHandle then
        itemHandle = MakeHandle(0.44, 0.93, 0.25, 101)   -- lime, above the group's box
        itemHandle.target = function() return InProfile(editItem) and editItem or nil end
        itemHandle.scaleOf = function(ov2)
            local g2 = ov2.group and GloomsOverlays_FindGroup(ov2.group)
            return (g2 and g2.scale) or 1
        end
        itemHandle.apply = function(ov2) GloomsOverlays_ApplyLayout(ov2) end
        groupHandle = MakeHandle(0.2, 0.8, 0.4, 100)      -- green
        groupHandle.target = function() return groupHandle.group end
        groupHandle.apply = function(g) GloomsOverlays_ApplyGroupLayout(g) end
    end
    editItem, editGroup = ov, group
    RefreshHandles()
end

-- ============================================================
-- MAIN INIT
-- ============================================================

local mainFrame = CreateFrame("Frame", "GloomsOverlaysMain", UIParent)
mainFrame:RegisterEvent("PLAYER_LOGIN")
mainFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
mainFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
mainFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
mainFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")   -- mounting / dismounting (Hide When Mounted)
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
            print("|cff936bffGloom's UI|r: migrated overlays to Default profile.")
        end

        if not VibeOverlayDB.profiles then VibeOverlayDB.profiles = {} end
        if not VibeOverlayDB.profiles["Default"] then
            VibeOverlayDB.profiles["Default"] = { overlays = {} }
        end

        inCombat  = UnitAffectingCombat("player")
        hasTarget = UnitExists("target")
        isCasting = (UnitCastingInfo("player") ~= nil) or (UnitChannelInfo("player") ~= nil)
        GloomsOverlays_ApplyAll()
        print("|cff936bffGloom's UI|r loaded. |cffcccccc/gui|r opens it.")

    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        UpdateVisibility()

    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        UpdateVisibility()

    elseif event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
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
-- Gloom's UI (2026-09-29): /gui is its own; /go (Overlays) and /gp (Portraits,
-- folded in) keep working.
SLASH_GLOOMSOVERLAYS1 = "/gui"
SLASH_GLOOMSOVERLAYS2 = "/go"
SLASH_GLOOMSOVERLAYS3 = "/gp"
SlashCmdList["GLOOMSOVERLAYS"] = function(msg)
    msg = msg and msg:lower():match("^%s*(.-)%s*$") or ""

    if msg == "" or msg == "overlays" or msg == "o" or msg == "config" then
        GloomsHub:ToggleWindow("overlays")

    elseif msg == "preview" or msg == "p" then
        GloomsHub:Open("overlays")
        if GloomsOverlays_BrowseAssets then GloomsOverlays_BrowseAssets(false) end

    elseif msg == "plates" then
        if addon.PR then addon.PR.PlatesProbe() end

    elseif msg == "reload" then
        ReloadUI()

    elseif msg == "list" then
        local profile  = GloomsOverlays_GetProfile()
        local overlays = profile and profile.overlays or {}
        print("|cff936bffGloom's UI|r — profile: |cffcccccc" .. GloomsOverlays_GetActiveProfileName() .. "|r — " .. #overlays .. " overlay(s):")
        for i, ov in ipairs(overlays) do
            local state = (ov.enabled == false) and "|cffaaaaaa off|r"
                or GloomsOverlays_GroupOff(ov) and "|cffaaaaaa group off|r" or "|cff00ff00on|r"
            print(string.format("  %d. %s%s [%s]", i, ov.name or "?", ov.kind == "portrait" and " (portrait)" or "", state))
        end

    elseif msg == "debug" then
        local profile  = GloomsOverlays_GetProfile()
        local overlays = profile and profile.overlays or {}
        local liveCount = 0
        for _ in pairs(liveOverlays) do liveCount = liveCount + 1 end
        print("|cff9966ffGloomsOverlays DEBUG|r — profile: " .. GloomsOverlays_GetActiveProfileName() .. " — " .. #overlays .. " saved, " .. liveCount .. " live, combat=" .. tostring(inCombat))
        for ov, entry in pairs(liveOverlays) do
            local name  = ov.name or "?"
            local fr    = entry.frame or entry.slot.anchor
            local shown = fr:IsShown() and "|cff00ff00SHOWN|r" or "|cffff4444HIDDEN|r"
            local x, y  = fr:GetCenter()
            local w, h  = fr:GetSize()
            print(string.format("  [%s] %s  center=(%.0f,%.0f) size=%dx%d alpha=%.2f condition=%s",
                name, shown, x or -1, y or -1, w, h,
                entry.tex and entry.tex:GetAlpha() or (ov.alpha or 1), entry.config.condition or "always"))
        end
        if next(liveOverlays) == nil then
            print("  (no live frames)")
        end
        -- each overlay's frame scale, and Unit Frames' health display beside
        -- them: the size check for "the same number, the same size" (2026-09-27)
        for ov, entry in pairs(liveOverlays) do
            local fr = entry.frame or entry.slot.anchor
            print(string.format("  [%s] saved %sx%s, effective scale %.3f", ov.name or "?", tostring(entry.config.width), tostring(entry.config.height), fr:GetEffectiveScale()))
        end
        local GU = _G.GloomsUnitFrames
        local uf = GU and GU.Frame and GU:Frame("player")
        local r = uf and uf.rings and uf.rings.health
        if r then
            local w, h = r.holder:GetSize()
            local rc = GU:Config("player") and GU:Config("player").rings.health
            local bc = rc and rc.bar
            print(string.format("  GU player health: mode=%s shape=%s holder=%.1fx%.1f effective scale %.3f shapeW/H=%s/%s size=%s",
                tostring(rc and rc.mode), tostring(bc and bc.shape), w or -1, h or -1, r.holder:GetEffectiveScale(),
                tostring(bc and bc.shapeW), tostring(bc and bc.shapeH), tostring(bc and bc.size)))
        end

    else
        print("|cff936bffGloom's UI|r commands (/go and /gp work too):")
        print("  |cffcccccc/gui|r                         — open Gloom's UI")
        print("  |cffcccccc/gui preview|r   (or /gui p)   — open the texture browser")
        print("  |cffcccccc/gui list|r                    — list overlays in chat")
        print("  |cffcccccc/gui debug|r                   — print live frame info")
        print("  |cffcccccc/gui plates|r                  — what the target portrait's nameplate cache holds")
        print("  |cffcccccc/gui reload|r                  — reload the UI")
    end
end
