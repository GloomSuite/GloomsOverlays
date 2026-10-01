-- ============================================================
-- GloomsOverlays_Pages.lua — Gloom's UI (the folder keeps the old name)
-- ★ THE TWO-WINDOW DESIGN (2026-09-27). Overlays was never mocked: it is
-- built from the Auras and Unit Frames pages (the owner, 2026-09-27: "there's
-- already a lot of source material"), so it reads as the same family. The Hub
-- (Windows.lua) owns the windows: the SELECTOR (240 wide), the SETTINGS
-- window (400) with its TAB, the pop-outs, the headers, the scrolling and
-- Global Settings (this tool's profile lives there).
-- ★ GLOOM'S UI (2026-09-29, the owner, agreed in chat before it was built):
-- Overlays became "gloomUI"; a PORTRAIT is one more overlay type
-- (GloomsOverlays_Portraits.lua), and overlays can be GROUPED — a shared
-- anchor that moves every member (the engine, GloomsOverlays.lua). This file draws:
--   the selector's list — groups (Auras' look: the lime ▾ collapses it, the
--     row selects it, its eye sets every member's), their members, then
--     Ungrouped; each overlay with a small picture of what it is (its texture,
--     or the unit's portrait), its eye (while the windows are open it alone
--     decides: lit = on screen whatever its conditions, unlit = hidden — Auras' eye), the one being edited
--     violet 30%. New Texture · New Portrait · New Group · Browse Assets at the
--     foot. Drag an overlay onto a group (or out, onto Ungrouped) to file it;
--     right-click an overlay for Rename · Duplicate · Move to Group ·
--     Delete, a group for Rename · Delete; double-click renames;
--   the tab — "gloomUI:" and what's selected (click it to switch, right-click
--     for its menu);
--   the SECTIONS, by what's selected (the others are hidden, not dimmed):
--     a texture — Overlay & Texture · Size & Position · Rotation & Motion ·
--       Layer · Visibility;
--     a portrait — Portrait · Size & Position · 3D Camera · Layer · Visibility;
--     a group — Group (its name, its anchor, its members).
--   Switching between kinds opens the matching section (texture ↔ portrait,
--   size ↔ size, motion ↔ camera), so the place you were stays open.
-- Every number is a Unit Frames number: a labelled control is 31 tall (the
-- label's 11, 4, the 16-tall control), rows 41 apart, blocks 30 apart,
-- columns 170 at 0 / 190. Disabled = 30%, never hidden.
-- It is DRAWING only: every control writes the overlay's fields live. The
-- texture browser is the Hub's (GloomsHub:PickTexture, gloomMEDIA → Game
-- Textures) since 2026-09-29; GloomsOverlays_Preview.lua, the first design's
-- drawer, is out of the TOC — delete it once the owner approves. The previous tab (GloomsOverlays_Editor.lua) is
-- no longer loaded; delete it once the owner approves these windows.
-- ============================================================

local SKIN_NEEDS = 20   -- 20: UI.gBrackets (the drag handles); 19: gDial `fine` (position dials)
local Skin, skinMinor
if LibStub then Skin, skinMinor = LibStub("LibGloomSkin-1.0", true) end
if not Skin then return end
if (skinMinor or 0) < SKIN_NEEDS then
  print("|cffff7729Gloom's UI:|r its windows need Gloom's Hub with LibGloomSkin " .. SKIN_NEEDS .. " or newer — update Gloom's Hub. Your overlays keep rendering normally.")
  return
end

local UI, COLOR, FONT = Skin.UI, Skin.COLOR, Skin.FONT
local LIME, LILAC, VIOLET = COLOR.lime, COLOR.lilac, COLOR.violet
local DIM = UI.G_DIM or 0.3
local attachTip = UI.attachTip
local OFFON = { { false, "Off" }, { true, "On" } }

local P = { secs = {}, listOffset = 0 }
local selItem, selGroup   -- what's selected: an overlay, a group, or neither

local function Overlays()
  local profile = GloomsOverlays_GetProfile and VibeOverlayDB and GloomsOverlays_GetProfile()
  return (profile and profile.overlays) or {}
end
local function Groups() return VibeOverlayDB and GloomsOverlays_GetGroups() or {} end
local function IndexOf(ov) for i, o in ipairs(Overlays()) do if o == ov then return i end end end
local function HasGroup(g) for _, x in ipairs(Groups()) do if x == g then return true end end return false end
-- The selection, checked against the live profile (a delete or a profile
-- switch can leave either pointing at nothing).
local function CurrentOverlay()
  if selItem and not IndexOf(selItem) then selItem = nil end
  return selItem
end
local function CurrentGroup()
  if selGroup and not HasGroup(selGroup) then selGroup = nil end
  return selGroup
end
local function IsPortrait(ov) return ov ~= nil and ov.kind == "portrait" end
-- "texture" | "portrait" | "group" — what the settings window shows. Nothing
-- selected shows the texture sections, dimmed.
local function Kind()
  if CurrentGroup() then return "group" end
  return IsPortrait(CurrentOverlay()) and "portrait" or "texture"
end
local function GroupOf(ov) return ov and ov.group and GloomsOverlays_FindGroup(ov.group) or nil end
local function Relayout() if GloomsHub.RefreshWindows then GloomsHub:RefreshWindows("overlays") end end

-- ---------------------------------------------------------------------------
-- Live apply — write into the selected overlay and rebuild the live frames.
-- Where an overlay SITS (size, position, strata, level) re-applies without a
-- rebuild, which matters mid-drag.
-- ---------------------------------------------------------------------------
local function LiveApply(field, value)
  local ov = CurrentOverlay(); if not ov then return end
  ov[field] = value
  GloomsOverlays_ApplyAll()
end
local function LiveApplyMulti(tbl)
  local ov = CurrentOverlay(); if not ov then return end
  for k, v in pairs(tbl) do ov[k] = v end
  GloomsOverlays_ApplyAll()
end
local function LiveLayout(field, value)
  local ov = CurrentOverlay(); if not ov then return end
  ov[field] = value
  GloomsOverlays_ApplyLayout(ov)
end

-- The color picker's "where is this color used": every overlay's tint by NAME
-- (the Tint control reads only the selected one). Untinted overlays store
-- white and are skipped (CONTRACTS §4); portraits have no tint.
local function OverlayColorSources()
  local out = {}
  for i, ov in ipairs(Overlays()) do
    local r, g, b = ov.tintR or 1, ov.tintG or 1, ov.tintB or 1
    if not IsPortrait(ov) and not (r == 1 and g == 1 and b == 1) then
      out[#out + 1] = { color = { r, g, b }, label = "UI › " .. (ov.name or ("Overlay " .. i)) }
    end
  end
  return out
end
if UI.RegisterColorProvider then UI.RegisterColorProvider("GloomsOverlays", OverlayColorSources) end

local function NewOverlay(name, texture, sheet)
  return {
    name = name, texture = texture or "",
    x = 0, y = 0, width = 200, height = 200,
    rotation = 0, alpha = 1.0, blendMode = "BLEND", strata = "HIGH",
    flipH = false, flipV = false, spinSpeed = 0, spinDir = "cw",
    tintR = 1, tintG = 1, tintB = 1,
    enabled = true, condition = "always", sheet = sheet,
    autoSize = true,   -- still the default size: its first texture sets it (FitToImage)
  }
end

-- ★ A NEW OVERLAY STARTS AT ITS IMAGE'S SIZE (2026-09-30, the owner). The first
-- texture a new overlay gets — made from the browser, or chosen afterwards —
-- sets Width / Height to the image's pixel size (one frame's, for a
-- spritesheet), asked of the Hub (GloomsHub:TextureSize; a file's size can take
-- a moment to arrive). Only while it's untouched: `ov.autoSize` from NewOverlay,
-- and still 200 x 200 — sized by hand first, it's left alone. Once only.
local function FitToImage(ov)
  if not (ov and ov.autoSize) then return end
  if (ov.width or 200) ~= 200 or (ov.height or 200) ~= 200 then ov.autoSize = nil; return end
  if not GloomsHub.TextureSize or (ov.texture or "") == "" then return end
  local function apply(w, h)
    if not ov.autoSize or (ov.width or 200) ~= 200 or (ov.height or 200) ~= 200 then return end
    local sh = ov.sheet
    if sh and (sh.cols or 1) * (sh.rows or 1) > 1 then w, h = w / sh.cols, h / sh.rows end
    ov.width, ov.height = math.max(1, math.floor(w + 0.5)), math.max(1, math.floor(h + 0.5))
    ov.autoSize = nil
    GloomsOverlays_ApplyAll()
    if P.refreshAll then P.refreshAll() end
  end
  local w, h = GloomsHub:TextureSize(ov.texture, apply)
  if w then apply(w, h) end
end
-- A portrait starts as the player's 3D model at the old Portraits' size and
-- camera, on Medium (under most of the UI, as Portraits drew).
local function NewPortrait(name)
  return {
    kind = "portrait", name = name, unit = "player", mode = "3d",
    x = 0, y = 0, size = 350, alpha = 1.0, strata = "MEDIUM",
    facing = 0, zoom = 2.5, modelYOffset = 0, pitch = 0,
    enabled = true, condition = "always",
  }
end
local function CopyTable(v)
  if type(v) ~= "table" then return v end
  local t = {}; for k, x in pairs(v) do t[k] = CopyTable(x) end; return t
end

-- A spritesheet for a texture — the Hub's builder (GloomsHub:SheetFor, the
-- texture browser's home since 2026-09-29): nil for a still (1 x 1) texture.
function GloomsOverlays_SheetFor(texture, cols, rows, frames, fps)
  return GloomsHub:SheetFor(texture, cols, rows, frames, fps)
end

-- ---------------------------------------------------------------------------
-- Selection, refresh
-- ---------------------------------------------------------------------------
local tabs = {}
function P.refreshAll()
  for _, s in ipairs(P.secs) do if s.refresh then s.refresh() end end
  for _, t in ipairs(tabs) do t:refresh() end
  if P.renderList then P.renderList() end
  Relayout()
end

-- The section of one kind that stands for another's, so switching kinds keeps
-- the place you were (a texture's Size & Position ↔ a portrait's).
local TEX_SECS = { texture = true, size = true, motion = true, layer = true, visibility = true }
local POR_SECS = { portrait = true, psize = true, camera = true, layer = true, visibility = true }
local EQUIV = { texture = "portrait", size = "psize", motion = "camera", portrait = "texture", psize = "size", camera = "motion" }
local FIRST = { texture = "texture", portrait = "portrait", group = "group" }
local function ShownFor(kind, sid)
  if kind == "group" then return sid == "group" end
  return (kind == "portrait" and POR_SECS or TEX_SECS)[sid] == true
end

-- ★ THE LAST SELECTION, remembered (2026-09-30, the owner: /gui always opened
-- on the profile's first overlay). Per character, per profile, in
-- VibeOverlayDBChar — NOT in the profile, so selecting never counts as an undo
-- step. An overlay by its place in the list, a group by its id.
local function rememberPick()
  if not VibeOverlayDBChar then return end
  VibeOverlayDBChar.lastPick = VibeOverlayDBChar.lastPick or {}
  local key = GloomsOverlays_GetActiveProfileName()
  if selGroup then VibeOverlayDBChar.lastPick[key] = { group = selGroup.id }
  elseif selItem then VibeOverlayDBChar.lastPick[key] = { index = IndexOf(selItem) }
  else VibeOverlayDBChar.lastPick[key] = nil end
end
local function recallPick()
  local lp = VibeOverlayDBChar and VibeOverlayDBChar.lastPick and VibeOverlayDBChar.lastPick[GloomsOverlays_GetActiveProfileName()]
  if not lp then return nil, nil end
  if lp.group then return nil, GloomsOverlays_FindGroup(lp.group) end
  return lp.index and Overlays()[lp.index] or nil, nil
end

local function Select(ov, g)
  local d = GloomsHubDB and GloomsHubDB.win and GloomsHubDB.win.overlays
  local before, k0 = d and d.open, Kind()
  selItem = ov
  selGroup = (not ov) and g or nil
  rememberPick()
  -- the selected overlay shows at once, whatever its saved eye (the engine's
  -- GloomsOverlays_SetPick); the one left goes back to its own eye
  GloomsOverlays_SetPick(selItem)
  if P.windowsOpen then GloomsOverlays_SetEditing(selItem, selGroup) end
  P.refreshAll()
  local k1 = Kind()
  if P.windowsOpen and k0 ~= k1 then
    local want
    if k0 == "group" or k1 == "group" then want = FIRST[k1]
    elseif before then want = EQUIV[before] or before end
    if want and ShownFor(k1, want) and not (d and d.open == want) then GloomsHub:ShowPage("overlays", want) end
  end
end
local function SelectOverlay(index) local ov = index and Overlays()[index]; Select(ov, nil) end
P.Select, P.SelectOverlay = Select, SelectOverlay

-- A drag on screen moved something: the position dials follow it.
GloomsOverlays_OnMoved(function()
  for _, s in ipairs(P.secs) do if s.pos and s.refresh then s.refresh() end end
end)

-- ---------------------------------------------------------------------------
-- THE TEXTURE BROWSER — the Hub's (GloomsHub:PickTexture, 2026-09-29; it was
-- this addon's own docked drawer, GloomsOverlays_Preview.lua, now out of the
-- TOC). The Texture field's Browse hands the pick back to the overlay being
-- edited; Browse Assets also offers a new overlay from it.
-- ---------------------------------------------------------------------------
local function useTexture(t, sh) GloomsOverlays_SetTextureField(t, sh) end
local USE = { label = "Use This Texture", fn = function(t, sh) useTexture(t, sh) end,
  tip = "Puts this texture into the overlay you're editing — with the spritesheet settings above." }
local NEW = { label = "Save as New Overlay", fn = function(t, sh) GloomsOverlays_SaveFromPreview(t, sh) end,
  tip = "Makes a new texture overlay from this texture, spritesheet settings included, and selects it." }
function GloomsOverlays_BrowseAssets(forField)
  local ov = CurrentOverlay()
  local tex = ov and ov.kind ~= "portrait" and ov or nil
  local actions
  if forField then actions = { USE }
  elseif tex then actions = { USE, NEW }
  else actions = { NEW } end
  GloomsHub:PickTexture({ tool = "overlays", text = tex and tex.texture or "", sheet = tex and tex.sheet, actions = actions })
end

-- ---------------------------------------------------------------------------
-- CELLS — a labelled control (Unit Frames' shape): :refresh(), :setEnabled(on)
-- (the label dims with it).
-- ---------------------------------------------------------------------------
local function cell(parent, text, w, make)
  local c = CreateFrame("Frame", nil, parent); c:SetSize(w, 31)
  c.label = UI.gLabel(c, text or ""); c.label:SetPoint("TOPLEFT", 0, 0)
  c.control = make(c, w)
  c.control:SetPoint("TOPLEFT", 0, -15)
  function c:refresh() if self.control.refresh then self.control:refresh() end end
  function c:setEnabled(on)
    on = on and true or false
    if self.control.setEnabled then self.control:setEnabled(on) end
    self.label:SetAlpha(on and 1 or DIM)
  end
  return c
end
local function Switch(parent, text, w, choices, get, set)
  return cell(parent, text, w, function(c, cw) return UI.gSwitch(c, choices, get, set, { w = cw }) end)
end
local function Drop(parent, text, w, getLabel, getOptions, getCurrent, onPick)
  return cell(parent, text, w, function(c, cw) return UI.gDrop(c, cw, getLabel, getOptions, getCurrent, onPick) end)
end
local function Color(parent, text, w, opts)
  opts.w = w; opts.title = opts.title or text
  return cell(parent, text, w, function(c) return UI.gColor(c, opts) end)
end
local function Dial(parent, w, opts) opts.w = w; return UI.gDial(parent, opts) end
local function place(wd, x, y) wd:ClearAllPoints(); wd:SetPoint("TOPLEFT", x, -y); wd:Show() end
local function Note(parent, text, w)
  local n = UI.newText(parent, FONT.sa, 10, LILAC, "LEFT")
  n:SetWidth(w or 360); n:SetJustifyH("LEFT"); n:SetWordWrap(true); n:SetText(text)
  return n
end
local function NameField(parent, label, get, set, w)
  local f = cell(parent, label, w or 360, function(c, w)
    return UI.gField(c, w, {
      commit = function(text)
        text = (text or ""):match("^%s*(.-)%s*$")
        if text ~= "" and get() then set(text); P.refreshAll() end
      end,
      revert = function(self) local t = get(); self:SetText(t and t.name or "") end,
    })
  end)
  function f:refresh() if not self.control:HasFocus() then local t = get(); self.control:SetText(t and t.name or "") end end
  return f
end

-- A section's frame; its controls are `ctrls`, all dimmed while nothing of its
-- kind is selected (the tab says what to do). `pos` = it shows a position, so
-- a drag on screen refreshes it.
local function Section(parent, h, pos)
  local f = CreateFrame("Frame", nil, parent); f:SetSize(360, h)
  local s = { frame = f, ctrls = {}, pos = pos }
  P.secs[#P.secs + 1] = s
  f:HookScript("OnShow", function() if s.refresh then s.refresh() end end)
  function s:base(on)
    if on == nil then on = CurrentOverlay() ~= nil end
    for _, c in ipairs(self.ctrls) do if c.refresh then c:refresh() end; if c.setEnabled then c:setEnabled(on) end end
    return on
  end
  -- grow or shrink to the content (only when it changed: Windows.lua re-lays out)
  function s:fit(h2) if math.abs((f:GetHeight() or 0) - h2) > 0.5 then f:SetHeight(h2) end end
  return f, s
end

-- ===========================================================================
-- THE MENUS — an overlay's and a group's right-click menus, Move to Group,
-- and the switch list.
-- ===========================================================================
local function renameSelected()
  local ov, g = CurrentOverlay(), CurrentGroup()
  local t = ov or g; if not t then return end
  UI.nameDialog(g and "Rename Group" or (IsPortrait(ov) and "Rename Portrait" or "Rename Overlay"), t.name or "", function(nm)
    nm = nm and nm:match("^%s*(.-)%s*$")
    if not nm or nm == "" then return end
    t.name = nm
    GloomsOverlays_ApplyAll(); P.refreshAll()
  end)
end
local function duplicateSelected()
  local src = CurrentOverlay(); if not src then return end
  local copy = CopyTable(src)
  copy.name = (src.name or "Overlay") .. " copy"
  table.insert(Overlays(), IndexOf(src) + 1, copy)
  GloomsOverlays_ApplyAll()
  Select(copy)
end
local function deleteSelected()
  local ov = CurrentOverlay(); if not ov then return end
  local idx = IndexOf(ov)
  UI.confirm(("Delete %s \"%s\"?  This can't be undone."):format(IsPortrait(ov) and "the portrait" or "the overlay", ov.name or "?"), function()
    table.remove(Overlays(), idx)
    GloomsOverlays_ApplyAll()
    local n = #Overlays()
    SelectOverlay(n > 0 and math.min(idx, n) or nil)
  end)
end
local function deleteGroup()
  local g = CurrentGroup(); if not g then return end
  UI.confirm(("Delete the group \"%s\"?  Its overlays stay where they are, ungrouped."):format(g.name or "?"), function()
    GloomsOverlays_DeleteGroup(g)
    GloomsOverlays_ApplyAll()
    Select(nil, nil)
  end, "Delete")
end

-- Move to Group: every group, then New Group…, then No Group. The overlay
-- keeps its place on screen either way (its offset is re-based).
local function moveToGroup(ov)
  if not ov then return end
  local opts = {}
  for _, g in ipairs(Groups()) do opts[#opts + 1] = { value = g.id, label = g.name or "Group" } end
  opts[#opts + 1] = { value = "__new", label = "New Group…", divider = #opts > 0 }
  opts[#opts + 1] = { value = "__none", label = "No Group", disabled = ov.group == nil }
  UI.gList(nil, opts, ov.group, function(v)
    if v == "__new" then
      UI.nameDialog("New Group", "", function(nm)
        nm = nm and nm:match("^%s*(.-)%s*$")
        if not nm or nm == "" then return end
        local g = GloomsOverlays_NewGroup(nm)
        GloomsOverlays_SetGroup(ov, g.id)
        GloomsOverlays_ApplyAll(); Select(ov)
      end)
      return
    end
    GloomsOverlays_SetGroup(ov, v ~= "__none" and v or nil)
    GloomsOverlays_ApplyAll(); Select(ov)
  end, { cursor = true })
end

function P.overlayMenu(anchor)
  UI.gList(anchor, {
    { value = "rename", label = "Rename" },
    { value = "dupe", label = "Duplicate" },
    { value = "move", label = "Move to Group" },
    { value = "delete", label = "Delete", danger = true, divider = true },
  }, nil, function(v)
    if v == "rename" then renameSelected() elseif v == "dupe" then duplicateSelected()
    elseif v == "move" then moveToGroup(CurrentOverlay()) elseif v == "delete" then deleteSelected() end
  end, { cursor = true })
end
function P.groupMenu(anchor)
  UI.gList(anchor, {
    { value = "rename", label = "Rename" },
    { value = "delete", label = "Delete", danger = true, divider = true },
  }, nil, function(v)
    if v == "rename" then renameSelected() elseif v == "delete" then deleteGroup() end
  end, { cursor = true })
end
local function switchMenu(anchor)
  local list, cur = {}, nil
  for _, g in ipairs(Groups()) do
    list[#list + 1] = { value = "g" .. g.id, label = (g.name or "Group") .. "  (group)" }
    if g == CurrentGroup() then cur = "g" .. g.id end
  end
  for i, ov in ipairs(Overlays()) do
    list[#list + 1] = { value = i, label = ov.name or ("Overlay " .. i), divider = (i == 1 and #list > 0) or nil }
    if ov == CurrentOverlay() then cur = i end
  end
  if #list == 0 then return end
  UI.gList(anchor, list, cur, function(v)
    if type(v) == "string" then
      local id = tonumber(v:sub(2))
      Select(nil, GloomsOverlays_FindGroup(id))
    else
      SelectOverlay(v)
    end
  end)
end

-- New Texture / New Portrait: into the selected GROUP if one is selected (at
-- its anchor), otherwise loose at the screen's center.
local function addNew(ov)
  local g = CurrentGroup()
  if g then ov.group = g.id end
  local list = Overlays()
  list[#list + 1] = ov
  GloomsOverlays_ApplyAll()
  Select(ov)
end
local function createTexture() addNew(NewOverlay("New Texture " .. (#Overlays() + 1))) end
local function createPortrait() addNew(NewPortrait("New Portrait " .. (#Overlays() + 1))) end
local function createGroup()
  local g = GloomsOverlays_NewGroup("New Group " .. (#Groups() + 1))
  GloomsOverlays_ApplyAll()
  Select(nil, g)
end

-- ===========================================================================
-- THE SELECTOR — the list from y 52, 18 to a line (Auras' list): a group's
-- header in Sansation Bold 12 with the lime ▾ (click the ▾ to fold it), its
-- members, a gap; then Ungrouped the same way (with no groups, a flat list).
-- An overlay's line: its picture (12), its name in Sansation 10 (50% when
-- switched off), the eye at the right (lime = on screen now, white 40% = not);
-- the one being edited violet 30% across the whole window. The four buttons at
-- the foot, two to a row. It scrolls by whole lines.
-- ===========================================================================
local LIST_TOP, LIST_ROW_H, LIST_GAP, LIST_FOOT = 52, 18, 20, 80
local listRows = {}

-- The picture on an overlay's line: a portrait's unit (a question mark while
-- there is no target), a texture's own art — the first frame of a spritesheet.
local function rowPicture(t, ov)
  t:SetTexCoord(0, 1, 0, 1); t:SetVertexColor(1, 1, 1, 1)
  if IsPortrait(ov) then
    local unit = ov.unit == "target" and "target" or "player"
    if UnitExists(unit) then SetPortraitTexture(t, unit)
    else t:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark"); t:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    return
  end
  local sh = ov.sheet
  if sh and sh.fileID then
    t:SetTexture(sh.fileID)
    local cw = ((sh.uRight or 1) - (sh.uLeft or 0)) / (sh.cols or 1)
    local rh = ((sh.vBottom or 1) - (sh.vTop or 0)) / (sh.rows or 1)
    t:SetTexCoord(sh.uLeft or 0, (sh.uLeft or 0) + cw, sh.vTop or 0, (sh.vTop or 0) + rh)
  else
    local tx = ov.texture or ""
    local path = GloomsHub.ResolveAssetPath and GloomsHub:ResolveAssetPath(tx)
    if path then t:SetTexture(path)
    elseif tonumber(tx) then t:SetTexture(tonumber(tx))
    elseif tx ~= "" and C_Texture and C_Texture.GetAtlasInfo(tx) then t:SetAtlas(tx)
    elseif tx ~= "" then t:SetTexture(tx)
    else t:SetTexture(nil) end
  end
  t:SetVertexColor(ov.tintR or 1, ov.tintG or 1, ov.tintB or 1, 1)
end

local function groupEyeOn(g)
  for _, m in ipairs(GloomsOverlays_GroupMembers(g)) do if GloomsOverlays_EyeOn(m) then return true end end
  return false
end

local function listRow(i)
  local r = listRows[i]
  if r then return r end
  r = CreateFrame("Button", nil, P.listClip)
  r:SetSize(200, LIST_ROW_H)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r.hl = r:CreateTexture(nil, "BACKGROUND"); r.hl:SetPoint("TOPLEFT", -20, 1); r.hl:SetPoint("BOTTOMRIGHT", 20, -1)
  r.hl:Hide()
  -- the ▾ is its own button: it folds the group; the rest of the line selects it
  r.fold = CreateFrame("Button", nil, r); r.fold:SetSize(12, LIST_ROW_H); r.fold:SetPoint("LEFT", -2, 0)
  r.tri = r.fold:CreateTexture(nil, "ARTWORK"); r.tri:SetTexture(UI.G_TRI); r.tri:SetSize(7, 6)
  r.tri:SetPoint("CENTER", r, "LEFT", 4, 0)
  r.fold:SetScript("OnClick", function()
    local p = GloomsOverlays_GetProfile()
    if r.kind == "group" and r.group then r.group.collapsed = (not r.group.collapsed) or nil
    elseif r.kind == "ungrouped" then p.ungroupedCollapsed = (not p.ungroupedCollapsed) or nil end
    P.renderList()
  end)
  r.pic = r:CreateTexture(nil, "ARTWORK"); r.pic:SetSize(12, 12); r.pic:SetPoint("LEFT", 0, 0)
  r.name = UI.newText(r, FONT.sa, 10, COLOR.paper, "LEFT"); r.name:SetPoint("LEFT", 18, 0)
  r.name:SetWordWrap(false)
  r.eye = CreateFrame("Button", nil, r); r.eye:SetSize(14, 14); r.eye:SetPoint("RIGHT", 0, 0)
  r.eye.t = r.eye:CreateTexture(nil, "ARTWORK"); r.eye.t:SetSize(14, 8.5); r.eye.t:SetPoint("CENTER", 0, 0)
  r.eye.t:SetTexture(UI.G_EYE); r.eye.t:SetTexCoord(0, 56 / 64, 0, 34 / 64)
  r.eye:SetScript("OnClick", function()
    if r.kind == "item" and r.ov then
      GloomsOverlays_ToggleEye(r.ov)
    elseif r.kind == "group" and r.group then
      local on = not groupEyeOn(r.group)
      for _, m in ipairs(GloomsOverlays_GroupMembers(r.group)) do GloomsOverlays_SetEye(m, on) end
      GloomsOverlays_ApplyAll()
    end
    P.refreshAll()
  end)
  attachTip(r.eye, "Show on screen", function()
    if r.kind == "group" then return "While these windows are open, shows every overlay in this group on screen — or hides them all. It doesn't change when they show in play." end
    return "While these windows are open, only overlays with a lit eye are on screen — lit shows it whatever its Visibility says, unlit hides it, even if it's Always Visible — so you can place things without the rest in the way. The one you select shows while it's selected — click its eye to hide it for now; once you select another, it goes back to its own eye. Closing the windows hands everything back to its Visibility."
  end)
  r:SetScript("OnEnter", function(self)
    local sel = (self.kind == "item" and self.ov == CurrentOverlay()) or (self.kind == "group" and self.group == CurrentGroup())
    if (self.kind == "item" or self.kind == "group") and not sel then self.hl:SetColorTexture(VIOLET.r, VIOLET.g, VIOLET.b, 0.15); self.hl:Show() end
  end)
  r:SetScript("OnLeave", function(self)
    local sel = (self.kind == "item" and self.ov == CurrentOverlay()) or (self.kind == "group" and self.group == CurrentGroup())
    if not sel then self.hl:Hide() end
  end)
  r:SetScript("OnClick", function(self, button)
    if self.kind == "item" and self.ov then
      Select(self.ov)
      if button == "RightButton" then P.overlayMenu(self) end
    elseif self.kind == "group" and self.group then
      Select(nil, self.group)
      if button == "RightButton" then P.groupMenu(self) end
    elseif self.kind == "ungrouped" then
      self.fold:Click()
    end
  end)
  r:SetScript("OnDoubleClick", function(self)
    if self.kind == "item" and self.ov then Select(self.ov); renameSelected()
    elseif self.kind == "group" and self.group then Select(nil, self.group); renameSelected() end
  end)
  r:RegisterForDrag("LeftButton")
  r:SetScript("OnDragStart", function(self) if self.kind == "item" and self.ov then P.itemDragStart(self) end end)
  r:SetScript("OnDragStop", function() P.itemDragStop() end)
  listRows[i] = r
  return r
end

-- The list as typed lines: every group (header · "sub" · members · gap), then
-- Ungrouped the same way; with no groups at all, a flat list.
local function listEntries()
  local out, list = {}, Overlays()
  local groups = Groups()
  local inGroup = {}
  for _, g in ipairs(groups) do
    out[#out + 1] = { kind = "group", group = g }
    if not g.collapsed then
      local members = GloomsOverlays_GroupMembers(g)
      if #members > 0 then out[#out + 1] = { kind = "sub" } end
      for _, ov in ipairs(members) do out[#out + 1] = { kind = "item", ov = ov } end
    end
    for _, ov in ipairs(list) do if ov.group == g.id then inGroup[ov] = true end end
    out[#out + 1] = { kind = "gap" }
  end
  local loose = {}
  for _, ov in ipairs(list) do if not inGroup[ov] then loose[#loose + 1] = ov end end
  if #groups > 0 then
    -- the Ungrouped header stays even when empty: it's where a drag takes an
    -- overlay out of its group
    local p = GloomsOverlays_GetProfile()
    out[#out + 1] = { kind = "ungrouped" }
    if not p.ungroupedCollapsed and #loose > 0 then
      out[#out + 1] = { kind = "sub" }
      for _, ov in ipairs(loose) do out[#out + 1] = { kind = "item", ov = ov } end
    end
  else
    for _, ov in ipairs(loose) do out[#out + 1] = { kind = "item", ov = ov } end
  end
  return out
end
local function entryH(e) return (e.kind == "gap" and LIST_GAP) or (e.kind == "sub" and 6) or LIST_ROW_H end

function P.renderList()
  if not P.listClip then return end
  local entries = listEntries()
  local total = 0
  for _, e in ipairs(entries) do total = total + entryH(e) end
  local view = math.max(LIST_ROW_H, math.floor((P.listHost:GetHeight() or 0) - LIST_TOP - LIST_FOOT))
  local maxOff = 0
  do
    local h, n = total, 0
    while h > view and n < #entries do n = n + 1; h = h - entryH(entries[n]) end
    maxOff = n
  end
  P.listOffset = math.max(0, math.min(maxOff, P.listOffset or 0))
  local selOv, selG = CurrentOverlay(), CurrentGroup()
  local p = VibeOverlayDB and GloomsOverlays_GetProfile()
  local y, n = 0, 0
  for i = P.listOffset + 1, #entries do
    local e = entries[i]
    local h = entryH(e)
    if y + h > view then break end
    if e.kind ~= "gap" and e.kind ~= "sub" then
      n = n + 1
      local r = listRow(n)
      r.kind, r.ov, r.group = e.kind, e.ov, e.group
      r:ClearAllPoints(); r:SetPoint("TOPLEFT", P.listClip, "TOPLEFT", 0, -y)
      r.tri:Hide(); r.fold:Hide(); r.pic:Hide(); r.eye:Hide(); r.hl:Hide()
      r.name:ClearAllPoints(); r.name:SetPoint("LEFT", 18, 0); r.name:SetWidth(0)
      r.name:SetAlpha(1)
      if e.kind == "group" or e.kind == "ungrouped" then
        local collapsed = (e.kind == "group" and e.group.collapsed) or (e.kind == "ungrouped" and p and p.ungroupedCollapsed)
        r.fold:Show(); r.tri:Show(); r.tri:SetRotation(collapsed and (math.pi / 2) or 0); UI.tint(r.tri, LIME)
        UI.setFont(r.name, FONT.saB, 12)
        r.name:ClearAllPoints(); r.name:SetPoint("LEFT", 12, 0)
        r.name:SetText(e.kind == "group" and (e.group.name or "Group") or "Ungrouped"); r.name:SetTextColor(1, 1, 1)
        if e.kind == "group" and e.group.enabled == false then r.name:SetAlpha(0.5) end
        if e.kind == "group" then
          r.eye:Show()
          if groupEyeOn(e.group) then UI.tint(r.eye.t, LIME) else r.eye.t:SetVertexColor(1, 1, 1, 0.4) end
          if e.group == selG then r.hl:SetColorTexture(VIOLET.r, VIOLET.g, VIOLET.b, 0.3); r.hl:Show() end
        end
      else
        local ov = e.ov
        r.pic:Show(); rowPicture(r.pic, ov)
        UI.setFont(r.name, FONT.sa, 10)
        r.name:SetText(ov.name or "Overlay"); r.name:SetTextColor(1, 1, 1)
        -- a switched-off overlay greys; the eye is lime while it shows on screen
        r.name:SetAlpha((ov.enabled ~= false and not GloomsOverlays_GroupOff(ov)) and 1 or 0.5)
        r.eye:Show()
        if GloomsOverlays_EyeOn(ov) then UI.tint(r.eye.t, LIME) else r.eye.t:SetVertexColor(1, 1, 1, 0.4) end
        if ov == selOv then r.hl:SetColorTexture(VIOLET.r, VIOLET.g, VIOLET.b, 0.3); r.hl:Show() end
      end
      -- cap a name only when it is too long for its line
      local maxW = 200 - (e.kind == "item" and 18 or 12) - 20
      local w = math.ceil(r.name:GetStringWidth())
      if w > maxW then r.name:SetWidth(maxW) end
      r:Show()
    end
    y = y + h
  end
  for i = n + 1, #listRows do listRows[i]:Hide(); listRows[i].kind, listRows[i].ov, listRows[i].group = nil, nil, nil end
  P.empty:SetShown(#Overlays() == 0 and #Groups() == 0)
  local track, thumb = P.listTrack, P.listThumb
  if maxOff > 0 then
    track:Show()
    local th = math.max(24, math.floor(view * view / math.max(view, total) + 0.5))
    thumb:SetHeight(th)
    thumb:ClearAllPoints(); thumb:SetPoint("TOP", track, "TOP", 0, -math.floor((view - th) * (P.listOffset / maxOff) + 0.5))
  else
    track:Hide()
  end
  P.listMax = maxOff
end

-- ---------------------------------------------------------------------------
-- Dragging an overlay INTO a group (the owner, 2026-09-29: Auras' trigger
-- conditions already drag into their groups). A ghost of the line follows the
-- cursor; the group it would land in lights up — its header, or the header of
-- the group whose member it is over; over Ungrouped (its header or a loose
-- line) it would leave its group. Letting go files it there, keeping its place
-- on screen (GloomsOverlays_SetGroup); off the list, nothing changes.
-- ---------------------------------------------------------------------------
-- What the cursor is over: a group table, "none" (ungrouped), or nil (nothing).
local function dropTarget()
  for _, r in ipairs(listRows) do
    if r:IsShown() and r.kind and r:IsMouseOver() then
      if r.kind == "group" then return r.group, r end
      if r.kind == "ungrouped" then return "none", r end
      if r.kind == "item" and r.ov then
        local g = GroupOf(r.ov)
        if g then
          for _, h in ipairs(listRows) do if h:IsShown() and h.kind == "group" and h.group == g then return g, h end end
          return g, nil
        end
        for _, h in ipairs(listRows) do if h:IsShown() and h.kind == "ungrouped" then return "none", h end end
        return "none", nil
      end
    end
  end
end

function P.itemDragStart(row)
  local gh = P.ghost
  if not gh then
    gh = CreateFrame("Frame", nil, UIParent); gh:SetFrameStrata("TOOLTIP"); gh:SetSize(200, LIST_ROW_H)
    local b = gh:CreateTexture(nil, "BACKGROUND"); b:SetAllPoints(); b:SetColorTexture(VIOLET.r, VIOLET.g, VIOLET.b, 0.5)
    gh.text = UI.newText(gh, FONT.sa, 10, COLOR.paper, "LEFT"); gh.text:SetPoint("LEFT", 12, 0)
    P.ghost = gh
  end
  gh:SetScale(row:GetEffectiveScale() / UIParent:GetEffectiveScale())
  gh.text:SetText(row.ov.name or "Overlay")
  P.dragging = { ov = row.ov, row = row }
  row:SetAlpha(0.4)
  gh:SetScript("OnUpdate", function(self)
    local x, y = GetCursorPosition(); local sc = self:GetEffectiveScale()
    self:ClearAllPoints(); self:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x / sc + 8, y / sc)
    local _, head = dropTarget()
    if head ~= P.dropHead then
      if P.dropHead then P.renderList() end
      P.dropHead = head
      if head then head.hl:SetColorTexture(VIOLET.r, VIOLET.g, VIOLET.b, 0.4); head.hl:Show() end
    end
  end)
  gh:Show()
end

function P.itemDragStop()
  local d = P.dragging; P.dragging = nil
  if P.ghost then P.ghost:Hide(); P.ghost:SetScript("OnUpdate", nil) end
  P.dropHead = nil
  if not d then return end
  d.row:SetAlpha(1)
  local target = dropTarget()
  local ov = d.ov
  local now = GroupOf(ov)
  if target == "none" and now then
    GloomsOverlays_SetGroup(ov, nil)
  elseif type(target) == "table" and target ~= now then
    GloomsOverlays_SetGroup(ov, target.id)
  else
    P.renderList(); return      -- dropped where it already was, or off the list
  end
  GloomsOverlays_ApplyAll()
  Select(ov)
end

local function buildSelector(c, api)
  local clip = CreateFrame("Frame", nil, c)
  clip:SetPoint("TOPLEFT", 20, -LIST_TOP); clip:SetPoint("BOTTOMRIGHT", -20, LIST_FOOT)
  P.listClip, P.listHost = clip, (api and api.window) or c
  clip:EnableMouseWheel(true)
  clip:SetScript("OnMouseWheel", function(_, d)
    P.listOffset = math.max(0, math.min(P.listMax or 0, (P.listOffset or 0) - d)); P.renderList()
  end)
  P.listHost:HookScript("OnSizeChanged", function() P.renderList() end)
  P.empty = Note(clip, "Nothing in this profile yet. New Texture or New Portrait makes one; Browse Assets finds a texture first.", 200)
  P.empty:SetPoint("TOPLEFT", 0, 0)
  -- the scrollbar, in the window's right margin, only while the list overflows
  local track = CreateFrame("Frame", nil, c); track:SetWidth(3)
  track:SetPoint("TOPLEFT", c, "TOPLEFT", 230.5, -LIST_TOP); track:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 230.5, LIST_FOOT)
  local tt = track:CreateTexture(nil, "BACKGROUND"); tt:SetAllPoints(); tt:SetColorTexture(0, 0, 0, 0.5)
  local thumb = CreateFrame("Frame", nil, track); thumb:SetWidth(3)
  local th = thumb:CreateTexture(nil, "ARTWORK"); th:SetAllPoints(); th:SetColorTexture(VIOLET.r, VIOLET.g, VIOLET.b, 0.5)
  track:Hide()
  P.listTrack, P.listThumb = track, thumb

  -- the foot: two rows of two, 10 apart, 20 in from the sides and the bottom
  local function btn(label, x, y, onClick, tipTitle, tip)
    local b = UI.gButton(c, label, { w = 95 })
    if x == 0 then b:SetPoint("BOTTOMLEFT", 20, y) else b:SetPoint("BOTTOMRIGHT", -20, y) end
    b:SetScript("OnClick", onClick)
    attachTip(b, tipTitle, tip)
    return b
  end
  btn("New Texture", 0, 45, createTexture, "New texture",
    "Creates a blank texture overlay and opens it for editing. With a group selected, it goes into that group.")
  btn("New Portrait", 1, 45, createPortrait, "New portrait",
    "Creates a portrait — your character as a 3D model to start; switch it to your target or to a flat 2D portrait in its settings. With a group selected, it goes into that group.")
  btn("New Group", 0, 20, createGroup, "New group",
    "Creates an empty group. Drag overlays onto it in this list (or right-click one → Move to Group); drag the group's green box on screen to move them all together.")
  btn("Browse Assets", 1, 20, function()
    if GloomsHub:PickerShown() then GloomsHub:ClosePicker() else GloomsOverlays_BrowseAssets(false) end
  end, "Texture browser", "Preview textures, play spritesheets and keep favorites (they're in gloomMEDIA → Game Textures too). Pick one to drop it into the texture being edited, or save it as a new overlay.")
  P.renderList()
end

-- ===========================================================================
-- THE TAB — "gloomUI:" lime, what's selected white, Sansation 10. Click the
-- name for the list to switch to; right-click it for its menu.
-- ===========================================================================
local function buildTab(tab)
  local t = {}
  local lead = UI.newText(tab, FONT.sa, 10, LIME, "LEFT"); lead:SetPoint("TOPLEFT", 20, -9)
  lead:SetText("gloomUI: ")
  local name = UI.newText(tab, FONT.sa, 10, COLOR.paper, "LEFT"); name:SetPoint("LEFT", lead, "RIGHT", 0, 0)
  name:SetWordWrap(false)
  local hit = CreateFrame("Button", nil, tab); hit:SetHeight(16); hit:SetPoint("LEFT", name, "LEFT", 0, 0)
  hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  hit:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
      if CurrentOverlay() then P.overlayMenu(self) elseif CurrentGroup() then P.groupMenu(self) end
    elseif CurrentOverlay() or CurrentGroup() then
      switchMenu(self)
    end
  end)
  attachTip(hit, "What you're editing", "Click to switch to another overlay or group. Right-click for its menu.")
  function t:refresh()
    local ov, g = CurrentOverlay(), CurrentGroup()
    if ov then name:SetText(ov.name or "Overlay"); name:SetAlpha(1)
    elseif g then name:SetText((g.name or "Group") .. "  (group)"); name:SetAlpha(1)
    else name:SetText("Nothing yet — click New Texture or New Portrait"); name:SetAlpha(0.6) end
    local maxW = 360 - 20 - math.ceil(lead:GetStringWidth())
    local w = math.ceil(name:GetStringWidth())
    name:SetWidth(math.min(w, maxW))
    hit:SetWidth(math.max(10, math.min(w, maxW)))
  end
  tabs[#tabs + 1] = t
  t:refresh()
  return t
end

-- ===========================================================================
-- SECTION · OVERLAY & TEXTURE — the name; the texture and Browse; Opacity |
-- Blend Mode; Tint Color | Class Color.
-- ===========================================================================
local function buildTexture(parent)
  local f, s = Section(parent, 271)
  local nameF = NameField(f, "Overlay Name", CurrentOverlay, function(text) LiveApply("name", text) end)
  place(nameF, 0, 0)
  local texF = cell(f, "Texture", 294, function(c, w)
    return UI.gField(c, w, {
      placeholder = "A media name, atlas, file ID or path",
      commit = function(text)
        local ov = CurrentOverlay(); if not ov then return end
        local t = (text or ""):match("^%s*(.-)%s*$")
        -- a spritesheet keeps its grid, re-cut from the new file
        local sh = ov.sheet
        if sh then ov.sheet = GloomsOverlays_SheetFor(t, sh.cols, sh.rows, sh.frames, sh.fps) end
        LiveApply("texture", t); FitToImage(ov); P.renderList(); s.refresh()
      end,
      revert = function(self) local ov = CurrentOverlay(); self:SetText(ov and ov.texture or "") end,
    })
  end)
  function texF:refresh() if not self.control:HasFocus() then local ov = CurrentOverlay(); self.control:SetText(ov and ov.texture or "") end end
  place(texF, 0, 41)
  P.texField = texF.control
  local browse = UI.gButton(f, "Browse", { w = 60, h = 16, size = 10, onClick = function() GloomsOverlays_BrowseAssets(true) end })
  browse:SetPoint("TOPLEFT", 300, -56)
  attachTip(browse, "Texture browser", "Preview textures, play spritesheets and keep favorites. Use This Texture drops the one shown into this overlay, spritesheet settings and all.")
  attachTip(texF.control, "Texture", "A Suite media name (the Hub's Media catalog), an atlas name, a file ID, or an Interface\\ path. Enter or clicking away applies it.")
  local alpha = Dial(f, 170, { label = "Opacity", min = 0, max = 100, step = 1, unit = "%", dragPx = 400,
    get = function() local ov = CurrentOverlay(); return math.floor(((ov and ov.alpha) or 1) * 100 + 0.5) end,
    set = function(v) LiveApply("alpha", v / 100) end })
  place(alpha, 0, 102)
  local blend = Switch(f, "Blend Mode", 170, { { "BLEND", "Blend" }, { "ADD", "Add" }, { "MOD", "Multiply" } },
    function() local ov = CurrentOverlay(); return (ov and ov.blendMode) or "BLEND" end,
    function(v) LiveApply("blendMode", v) end)
  attachTip(blend.control, "Blend mode", "Blend: drawn as it is. Add: brightens what's behind it — glows and light. Multiply: darkens what's behind it — shadows.")
  place(blend, 190, 102)
  -- The tint: an empty color is white (no tint). Class color overrides it and
  -- dims it (the previous editor's rule); the two are one switch now.
  local tint = Color(f, "Tint Color", 170, {
    title = "Overlay Tint",
    get = function()
      local ov = CurrentOverlay(); if not ov then return nil end
      local r, g, b = ov.tintR or 1, ov.tintG or 1, ov.tintB or 1
      if r == 1 and g == 1 and b == 1 then return nil end
      return { r, g, b }
    end,
    set = function(c)
      if c then LiveApplyMulti({ tintR = c[1] or c.r, tintG = c[2] or c.g, tintB = c[3] or c.b })
      else LiveApplyMulti({ tintR = 1, tintG = 1, tintB = 1 }) end
      P.renderList()
    end,
  })
  place(tint, 0, 143)
  local function classOf(unit)
    local _, tag = UnitClass(unit)
    local cc = tag and RAID_CLASS_COLORS and RAID_CLASS_COLORS[tag]
    return cc and cc.r or 1, cc and cc.g or 1, cc and cc.b or 1
  end
  local cls = Switch(f, "Class Color", 170, { { "off", "Off" }, { "player", "Player" }, { "target", "Target" } },
    function()
      local ov = CurrentOverlay()
      if ov and ov.useClassColor then return "player" elseif ov and ov.useTargetColor then return "target" end
      return "off"
    end,
    function(v)
      if v == "off" then LiveApplyMulti({ useClassColor = false, useTargetColor = false })
      else
        local r, g, b = classOf(v)
        LiveApplyMulti({ useClassColor = (v == "player") or nil, useTargetColor = (v == "target") or nil, tintR = r, tintG = g, tintB = b })
      end
      s.refresh(); P.renderList()
    end)
  attachTip(cls.control, "Class color", "Tints the overlay with your class color, or your target's (it follows the target as it changes). While on, it replaces the Tint Color.")
  place(cls, 190, 143)
  -- SPRITESHEET: Columns | Rows, Frames | Speed. More than one column or row
  -- makes the texture a spritesheet; 1 x 1 is a still texture.
  local function sh() local ov = CurrentOverlay(); return ov and ov.sheet end
  local function setSheet(cols, rows, frames, fps)
    local ov = CurrentOverlay(); if not ov then return end
    local old = ov.sheet
    ov.sheet = GloomsOverlays_SheetFor(ov.texture, cols or (old and old.cols) or 1, rows or (old and old.rows) or 1,
      frames or (old and old.frames), fps or (old and old.fps) or 15)
    -- a new grid shows every cell unless Frames was the one moved
    if ov.sheet and not frames and (cols or rows) then ov.sheet.frames = ov.sheet.cols * ov.sheet.rows end
    GloomsOverlays_ApplyAll(); P.renderList(); s.refresh()
  end
  local head = UI.gLabel(f, "Spritesheet"); head:SetPoint("TOPLEFT", 0, -184)
  local colsD = Dial(f, 170, { label = "Columns", min = 1, max = 64, step = 1, dragPx = 400,
    get = function() local x = sh(); return x and x.cols or 1 end, set = function(v) setSheet(v, nil) end })
  local rowsD = Dial(f, 170, { label = "Rows", min = 1, max = 64, step = 1, dragPx = 400,
    get = function() local x = sh(); return x and x.rows or 1 end, set = function(v) setSheet(nil, v) end })
  local framesD = Dial(f, 170, { label = "Frames", min = 1, max = 4096, step = 1, dragPx = 800,
    get = function() local x = sh(); return x and x.frames or 1 end, set = function(v) setSheet(nil, nil, v) end })
  local fpsD = Dial(f, 170, { label = "Speed (frames per second)", min = 1, max = 60, step = 1, dragPx = 300,
    get = function() local x = sh(); return x and x.fps or 15 end, set = function(v) setSheet(nil, nil, nil, v) end })
  attachTip(colsD.strip, "Columns", "How many frames across the texture. More than one column or row plays the texture as an animation, frame by frame, left to right, then row by row. 1 x 1 = a still texture. The asset browser guesses these for an atlas.")
  attachTip(framesD.strip, "Frames", "How many of the cells to play — fewer than Columns x Rows when the last row isn't full.")
  place(colsD, 0, 199); place(rowsD, 190, 199); place(framesD, 0, 240); place(fpsD, 190, 240)
  s.ctrls = { nameF, texF, browse, alpha, blend, tint, cls, colsD, rowsD, framesD, fpsD }
  s.refresh = function()
    local on = s:base()
    local ov = CurrentOverlay()
    local locked = ov and (ov.useClassColor == true or ov.useTargetColor == true)
    tint:setEnabled(on and not locked)
    head:SetAlpha(on and 1 or DIM)
    local anim = on and ov.sheet ~= nil
    framesD:setEnabled(anim); fpsD:setEnabled(anim)
  end
  return f
end

-- ===========================================================================
-- SECTION · PORTRAIT — the name; Unit | Display Type; Opacity.
-- ===========================================================================
local function buildPortrait(parent)
  local f, s = Section(parent, 113)
  local nameF = NameField(f, "Portrait Name", CurrentOverlay, function(text) LiveApply("name", text) end)
  place(nameF, 0, 0)
  local unit = Switch(f, "Unit", 170, { { "player", "Player" }, { "target", "Target" } },
    function() local ov = CurrentOverlay(); return (ov and ov.unit) or "player" end,
    function(v)
      local ov = CurrentOverlay(); if not ov then return end
      local old = ov.unit or "player"
      -- a camera still facing the old unit's way turns to the new one's
      local PR = GloomsOverlays_PortraitDefaults
      if PR and (ov.facing or PR.facing(old)) == PR.facing(old) then ov.facing = PR.facing(v) end
      LiveApply("unit", v)
      P.refreshAll()
    end)
  attachTip(unit.control, "Unit", "Player: your character. Target: whatever you have targeted — nothing shows while you have no target.")
  place(unit, 0, 41)
  local mode = Switch(f, "Display Type", 170, { { "3d", "3D Model" }, { "2d", "2D Portrait" } },
    function() local ov = CurrentOverlay(); return (ov and ov.mode) or "3d" end,
    function(v) LiveApply("mode", v); P.refreshAll() end)
  attachTip(mode.control, "Display type", "3D Model: the full-body model, which turns, zooms and tilts (3D Camera). 2D Portrait: the unit's flat portrait, drawn as a circle. In an instance, when the game won't say who a hostile target is mid-fight, a 3D portrait shows the 2D one in its place until combat ends.")
  place(mode, 190, 41)
  local alpha = Dial(f, 170, { label = "Opacity", min = 0, max = 100, step = 1, unit = "%", dragPx = 400,
    get = function() local ov = CurrentOverlay(); return math.floor(((ov and ov.alpha) or 1) * 100 + 0.5) end,
    set = function(v) LiveLayout("alpha", v / 100) end })
  place(alpha, 0, 82)
  s.ctrls = { nameF, unit, mode, alpha }
  s.refresh = function() s:base() end
  return f
end

-- ===========================================================================
-- SECTION · SIZE & POSITION — Width | Horizontal, Height | Vertical (a
-- portrait: Size | Horizontal, Vertical under it). In a group, the position is
-- the offset from the group's anchor, and a note says so.
-- ===========================================================================
local function groupNote(f, s, y)
  local note = Note(f, "")
  note:SetPoint("TOPLEFT", 0, -y)
  return function(on)
    local g = GroupOf(CurrentOverlay())
    if g then
      local where = g.attach and GloomsHub:AnchorLabel(g.attach)
      note:SetText(("Position is relative to the group \"%s\"%s — drag its green box on screen to move the whole group.%s"):format(g.name or "Group",
        where and (", which is attached to the " .. where) or "",
        (g.scale and g.scale ~= 1) and (" The group's scale (%d%%%%) applies on top."):format(math.floor(g.scale * 100 + 0.5)) or ""))
      note:SetAlpha(on and 1 or DIM); note:Show()
      s:fit(y + math.ceil(note:GetStringHeight()))
    else
      note:Hide()
      s:fit(y - 10)
    end
  end
end

local function buildSize(parent)
  local f, s = Section(parent, 72, true)
  local function num(field, default) return function() local ov = CurrentOverlay(); return (ov and ov[field]) or default end end
  local function setL(field) return function(v) LiveLayout(field, v) end end
  -- Width and Height can be LINKED (the owner, 2026-09-27) — the lime bracket
  -- between their boxes, as in Auras and Unit Frames: lit, one moves the other
  -- at the proportions they had when it was lit (ov.aspect). Off by default.
  local w, h
  local function linked() local ov = CurrentOverlay(); return ov and ov.lockAspect == true end
  local function clampDim(n) return math.max(1, math.min(2000, math.floor(n + 0.5))) end
  w = Dial(f, 170, { label = "Width", min = 1, max = 2000, step = 1, unit = "px", dragPx = 1600, get = num("width", 200),
    set = function(v)
      local ov = CurrentOverlay(); if not ov then return end
      ov.width = v
      if linked() then ov.height = clampDim(v / (ov.aspect or 1)); if h then h:refresh() end end
      GloomsOverlays_ApplyLayout(ov)
    end })
  h = Dial(f, 170, { label = "Height", min = 1, max = 2000, step = 1, unit = "px", dragPx = 1600, get = num("height", 200),
    set = function(v)
      local ov = CurrentOverlay(); if not ov then return end
      ov.height = v
      if linked() then ov.width = clampDim(v * (ov.aspect or 1)); if w then w:refresh() end end
      GloomsOverlays_ApplyLayout(ov)
    end })
  -- the bracket, in the gap right of the two dials: its arms level with the
  -- middles of their number boxes (15 + 8 into each row, rows 41 apart)
  local link = CreateFrame("Button", nil, f); link:SetSize(10, 65)
  local function seg(x, y, sw, sh) local t = link:CreateTexture(nil, "ARTWORK"); t:SetPoint("TOPLEFT", x, -y); t:SetSize(sw, sh); return t end
  local segs = { seg(0, 23, 10, 1), seg(9, 23, 1, 42), seg(0, 64, 10, 1) }
  function link:refresh()
    local on = linked()
    for _, t in ipairs(segs) do
      if on then t:SetColorTexture(LIME.r, LIME.g, LIME.b, 1) else t:SetColorTexture(1, 1, 1, 0.4) end
    end
  end
  function link:setEnabled(on) self:SetEnabled(on and true or false); self:SetAlpha(on and 1 or DIM) end
  link:SetScript("OnClick", function(self)
    local ov = CurrentOverlay(); if not ov then return end
    -- ★ an if, not `x and nil or false` (false both ways — Unit Frames' bracket, 2026-09-27)
    if linked() then ov.lockAspect = nil
    else
      ov.lockAspect = true
      local ww, hh = ov.width or 200, ov.height or 200
      ov.aspect = (hh > 0) and (ww / hh) or 1
    end
    self:refresh()
  end)
  attachTip(link, "Keep proportions", "Lit: changing the width changes the height with it, and the other way round, keeping the proportions they had when you lit it. Unlit: they move apart. Click to switch.")
  link:SetPoint("TOPLEFT", 173, 0)
  local x = Dial(f, 170, { fine = true, label = "Horizontal Position", min = -1000, max = 1000, step = 1, unit = "px", dragPx = 1600, get = num("x", 0), set = setL("x") })
  local y = Dial(f, 170, { fine = true, label = "Vertical Position", min = -1000, max = 1000, step = 1, unit = "px", dragPx = 1600, get = num("y", 0), set = setL("y") })
  place(w, 0, 0); place(x, 190, 0); place(h, 0, 41); place(y, 190, 41)
  local note = groupNote(f, s, 82)
  s.ctrls = { w, h, x, y, link }
  s.refresh = function() note(s:base()) end
  return f
end

local function buildPortraitSize(parent)
  local f, s = Section(parent, 72, true)
  local function num(field, default) return function() local ov = CurrentOverlay(); return (ov and ov[field]) or default end end
  local function setL(field) return function(v) LiveLayout(field, v) end end
  local size = Dial(f, 170, { label = "Size", min = 20, max = 1000, step = 1, unit = "px", dragPx = 1200, get = num("size", 350), set = setL("size") })
  attachTip(size.strip, "Size", "A portrait is square: this is its width and its height.")
  local x = Dial(f, 170, { fine = true, label = "Horizontal Position", min = -1000, max = 1000, step = 1, unit = "px", dragPx = 1600, get = num("x", 0), set = setL("x") })
  local y = Dial(f, 170, { fine = true, label = "Vertical Position", min = -1000, max = 1000, step = 1, unit = "px", dragPx = 1600, get = num("y", 0), set = setL("y") })
  place(size, 0, 0); place(x, 190, 0); place(y, 190, 41)
  local note = groupNote(f, s, 82)
  s.ctrls = { size, x, y }
  s.refresh = function() note(s:base()) end
  return f
end

-- ===========================================================================
-- SECTION · ROTATION & MOTION — Rotation | Spin Speed, Flip | Spin Direction
-- (dims while the speed is 0).
-- ===========================================================================
local function buildMotion(parent)
  local f, s = Section(parent, 72)
  local rot = Dial(f, 170, { label = "Rotation", min = -360, max = 360, step = 1, unit = "°", dragPx = 1440,
    get = function() local ov = CurrentOverlay(); return (ov and ov.rotation) or 0 end,
    set = function(v) LiveApply("rotation", v) end })
  local spin = Dial(f, 170, { label = "Spin Speed", min = 0, max = 360, step = 1, unit = "°/s", dragPx = 720,
    get = function() local ov = CurrentOverlay(); return (ov and ov.spinSpeed) or 0 end,
    set = function(v) LiveApply("spinSpeed", v); s.refresh() end })
  attachTip(spin.strip, "Spin speed", "Degrees per second. 0 turns spinning off.")
  local flip = Switch(f, "Flip", 170, { { "none", "None" }, { "h", "Horiz" }, { "v", "Vert" }, { "hv", "Both" } },
    function()
      local ov = CurrentOverlay(); local h, v = ov and ov.flipH, ov and ov.flipV
      return (h and v and "hv") or (h and "h") or (v and "v") or "none"
    end,
    function(v) LiveApplyMulti({ flipH = (v == "h" or v == "hv"), flipV = (v == "v" or v == "hv") }) end)
  attachTip(flip.control, "Flip", "Mirror the texture left-to-right (Horiz), top-to-bottom (Vert), or both.")
  local dir = Switch(f, "Spin Direction", 170, { { "cw", "Clockwise" }, { "ccw", "Counterclockwise" } },
    function() local ov = CurrentOverlay(); return (ov and ov.spinDir) or "cw" end,
    function(v) LiveApply("spinDir", v) end)
  place(rot, 0, 0); place(spin, 190, 0); place(flip, 0, 41); place(dir, 190, 41)
  s.ctrls = { rot, spin, flip, dir }
  s.refresh = function()
    local on = s:base()
    local ov = CurrentOverlay()
    dir:setEnabled(on and ov and (ov.spinSpeed or 0) > 0)
  end
  return f
end

-- ===========================================================================
-- SECTION · 3D CAMERA — Facing | Zoom, Vertical Offset | Pitch (Portraits'
-- ranges). Dims for a 2D portrait.
-- ===========================================================================
local function is3D() local ov = CurrentOverlay(); return IsPortrait(ov) and (ov.mode or "3d") == "3d" end
local function buildCamera(parent)
  local f, s = Section(parent, 72)
  local function cam(key, default) return function() local ov = CurrentOverlay(); return (ov and ov[key]) or default end end
  local facing = Dial(f, 170, { label = "Facing", min = 0, max = 359, step = 1, unit = "°", dragPx = 720,
    get = function()
      local ov = CurrentOverlay(); if not ov then return 0 end
      local rad = ov.facing or (GloomsOverlays_PortraitDefaults and GloomsOverlays_PortraitDefaults.facing(ov.unit)) or 0
      return math.floor(math.deg(rad) + 0.5) % 360
    end,
    set = function(v) LiveApply("facing", math.rad(v)) end })
  local zoom = Dial(f, 170, { label = "Zoom", min = 0.5, max = 5, step = 0.05, dragPx = 900, get = cam("zoom", 2.5), set = function(v) LiveApply("zoom", v) end })
  local offset = Dial(f, 170, { label = "Vertical Offset", min = -400, max = 400, step = 1, dragPx = 1000, get = cam("modelYOffset", 0), set = function(v) LiveApply("modelYOffset", v) end })
  local pitch = Dial(f, 170, { label = "Pitch", min = -1.5, max = 1.5, step = 0.02, dragPx = 900, get = cam("pitch", 0), set = function(v) LiveApply("pitch", v) end })
  place(facing, 0, 0); place(zoom, 190, 0); place(offset, 0, 41); place(pitch, 190, 41)
  s.ctrls = { facing, zoom, offset, pitch }
  s.refresh = function() s:base(is3D()) end
  return f
end

-- ===========================================================================
-- SECTION · LAYER — Strata (all nine of WoW's) | Level, and how they combine.
-- ===========================================================================
local STRATA = {
  { "WORLD", "World" }, { "BACKGROUND", "Background" }, { "LOW", "Low" }, { "MEDIUM", "Medium" }, { "HIGH", "High" },
  { "DIALOG", "Dialog" }, { "FULLSCREEN", "Fullscreen" }, { "FULLSCREEN_DIALOG", "Fullscreen Dialog" }, { "TOOLTIP", "Tooltip" },
}
local STRATA_LABEL = {}
for _, x in ipairs(STRATA) do STRATA_LABEL[x[1]] = x[2] end

local function buildLayer(parent)
  local f, s = Section(parent, 72)
  local strata = Drop(f, "Strata", 170,
    function() local ov = CurrentOverlay(); return STRATA_LABEL[(ov and ov.strata) or "HIGH"] or "High" end,
    function() local o = {}; for _, x in ipairs(STRATA) do o[#o + 1] = { value = x[1], label = x[2] } end; return o end,
    function() local ov = CurrentOverlay(); return (ov and ov.strata) or "HIGH" end,
    function(v) LiveLayout("strata", v) end)
  attachTip(strata.control, "Strata", "World sits under everything · High above most of the UI · Tooltip above all of it.")
  local level = Dial(f, 170, { label = "Level", min = 0, max = 1000, step = 1, dragPx = 1500,
    get = function() local ov = CurrentOverlay(); return (ov and ov.level) or GloomsOverlays_GetDefaultLevel() end,
    set = function(v) LiveLayout("level", v) end })
  attachTip(level.strip, "Level", function() return "Higher draws in front, within the same strata. The default is " .. GloomsOverlays_GetDefaultLevel() .. "." end)
  place(strata, 0, 0); place(level, 190, 0)
  local note = Note(f, "Strata always wins: a Medium overlay at level 999 still sits under anything on High. Point at a Blizzard frame with /fstack to read the strata and level it uses.")
  note:SetPoint("TOPLEFT", 0, -41)
  s.ctrls = { strata, level }
  s.refresh = function()
    local on = s:base()
    note:SetAlpha(on and 1 or DIM)
    s:fit(41 + math.ceil(note:GetStringHeight()))
  end
  return f
end

-- ===========================================================================
-- SECTION · VISIBILITY — the overlay's on/off, then the conditions as
-- checkboxes, two columns 26 apart: it shows while ANY checked one is true. A
-- target portrait also needs a target.
-- ===========================================================================
local COND = {
  { "always", "Always Visible" }, { "combat", "In Combat" }, { "nocombat", "Out of Combat" },
  { "target", "Target Selected" }, { "casting", "While Casting" },
}
local function buildVisibility(parent)
  local f, s = Section(parent, 140)
  local onOff = Switch(f, "Overlay", 170, { { false, "Off" }, { true, "On" } },
    function() local ov = CurrentOverlay(); return (ov and ov.enabled ~= false) and true or false end,
    function(v) LiveApply("enabled", v and true or false); P.refreshAll() end)
  attachTip(onOff.control, "On / off", "Off: it never shows in play, whatever the conditions below say; its settings are kept. (While these windows are open, the list's eyes decide what's on screen instead.)")
  place(onOff, 0, 0)
  local note = Note(f, "Shows while ANY checked condition is true.")
  note:SetPoint("TOPLEFT", 0, -46)
  local function conditionSet()
    local ov = CurrentOverlay()
    local set = {}
    for word in ((ov and ov.condition) or "always"):gmatch("[^,]+") do set[word] = true end
    return set
  end
  local checks = {}
  for i, c in ipairs(COND) do
    local key = c[1]
    local chk = UI.gCheck(f, c[2], function() return conditionSet()[key] == true end, function(v)
      local set = conditionSet()
      set[key] = v or nil
      local parts = {}
      for _, cc in ipairs(COND) do if set[cc[1]] then parts[#parts + 1] = cc[1] end end
      LiveApply("condition", #parts > 0 and table.concat(parts, ",") or "always")
      s.refresh()
    end)
    local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
    chk:SetPoint("TOPLEFT", col * 190, -(66 + row * 26))
    checks[i] = chk
  end
  s.ctrls = { onOff }
  for _, chk in ipairs(checks) do s.ctrls[#s.ctrls + 1] = chk end
  s.refresh = function()
    local on = s:base()
    local ov = CurrentOverlay()
    onOff.label:SetText(IsPortrait(ov) and "Portrait" or "Overlay")
    local live = on and ov.enabled ~= false
    for _, chk in ipairs(checks) do chk:setEnabled(live) end
    local target = IsPortrait(ov) and ov.unit == "target"
    note:SetText(target and "Shows while ANY checked condition is true — and only while you have a target." or "Shows while ANY checked condition is true.")
    note:SetAlpha(live and 1 or DIM)
  end
  return f
end

-- ===========================================================================
-- SECTION · GROUP — the name; Attach To | Hide With Its Frame (2026-09-30);
-- the anchor's Horizontal | Vertical (from the screen's centre, or the attached
-- frame's); Scale; the members (click one to select it).
-- ===========================================================================
local function buildGroup(parent)
  local f, s = Section(parent, 160, true)
  local nameF = NameField(f, "Group Name", CurrentGroup, function(text) local g = CurrentGroup(); if g then g.name = text end end, 170)
  place(nameF, 0, 0)
  -- the whole group on / off (2026-09-30) — a set-up kept whole while another is tried.
  -- Switching it also sets the members' eyes, so the windows show the change at once.
  local onOff = Switch(f, "Group", 170, OFFON,
    function() local g = CurrentGroup(); return (g and g.enabled ~= false) and true or false end,
    function(v)
      local g = CurrentGroup(); if not g then return end
      if v then g.enabled = nil else g.enabled = false end   -- (not `(not v) and false or nil` — that is always nil)
      for _, m in ipairs(GloomsOverlays_GroupMembers(g)) do GloomsOverlays_SetEye(m, v) end
      GloomsOverlays_ApplyAll(); P.refreshAll()
    end)
  attachTip(onOff.control, "Group on / off", "Off: nothing in this group shows in play, whatever each overlay's own settings say — they're all kept, ready to switch back on. Handy for keeping a whole set-up while you try another. (While these windows are open, the list's eyes decide what's on screen; switching this sets them too.)")
  place(onOff, 190, 0)
  local function gnum(field) return function() local g = CurrentGroup(); return (g and g[field]) or 0 end end
  local function gset(field) return function(v)
    local g = CurrentGroup(); if not g then return end
    g[field] = v
    GloomsOverlays_ApplyGroupLayout(g)
  end end
  -- ATTACH: the screen, or a frame another tool offers (the Hub's anchors)
  local attach = Drop(f, "Attach To", 170,
    function() local g = CurrentGroup(); return (g and g.attach and GloomsHub:AnchorLabel(g.attach)) or "Screen" end,
    function()
      local o = { { value = "__screen", label = "Screen" } }
      for _, a in ipairs(GloomsHub.Anchors and GloomsHub:Anchors() or {}) do o[#o + 1] = { value = a.id, label = a.label } end
      return o
    end,
    function() local g = CurrentGroup(); return (g and g.attach) or "__screen" end,
    function(v)
      local g = CurrentGroup(); if not g then return end
      GloomsOverlays_SetAttach(g, v ~= "__screen" and v or nil)
      GloomsOverlays_ApplyAll(); P.refreshAll()
    end)
  attachTip(attach.control, "Attach to", "Screen: the group's position is measured from the middle of the screen. A unit frame: it's measured from that frame's center, and the group moves with the frame — drag the frame in Unit Frames and everything here follows. The group keeps its own layer, and you can still drag or nudge it on its own.")
  local hideW = Switch(f, "Hide With Its Frame", 170, OFFON,
    function() local g = CurrentGroup(); return (g and g.hideWithAnchor) and true or false end,
    function(v) local g = CurrentGroup(); if g then g.hideWithAnchor = v or nil; GloomsOverlays_ApplyAll() end end)
  attachTip(hideW.control, "Hide with its frame", "On: the group shows only while the frame it's attached to does — target decorations disappear with the target frame. (While these windows are open, the list's eyes decide instead.)")
  place(attach, 0, 41); place(hideW, 190, 41)
  local x = Dial(f, 170, { fine = true, label = "Horizontal Position", min = -1500, max = 1500, step = 1, unit = "px", dragPx = 1600, get = gnum("x"), set = gset("x") })
  local y = Dial(f, 170, { fine = true, label = "Vertical Position", min = -1500, max = 1500, step = 1, unit = "px", dragPx = 1600, get = gnum("y"), set = gset("y") })
  attachTip(x.strip, "The group's anchor", "Moves every overlay in the group together — from the middle of the screen, or from the attached frame's center. Each overlay's own position is measured from here. The arrow keys nudge it 1 pixel (Shift: 10) while this section is open.")
  place(x, 0, 82); place(y, 190, 82)
  local scale = Dial(f, 170, { label = "Scale", min = 10, max = 400, step = 1, unit = "%", dragPx = 800,
    get = function() local g = CurrentGroup(); return math.floor(((g and g.scale) or 1) * 100 + 0.5) end,
    set = function(v)
      local g = CurrentGroup(); if not g then return end
      g.scale = (v ~= 100) and (v / 100) or nil
      GloomsOverlays_ApplyAll(); P.refreshAll()
    end })
  attachTip(scale.strip, "Scale", "Makes every overlay in the group bigger or smaller together — their sizes and the spaces between them — around the group's anchor. Each keeps its own size setting; this multiplies it.")
  place(scale, 0, 123)
  local head = UI.gLabel(f, "Members"); head:SetPoint("TOPLEFT", 0, -164)
  local empty = Note(f, "No overlays in this group yet. Drag one onto the group in the list, or select this group and click New Texture or New Portrait.")
  empty:SetPoint("TOPLEFT", 0, -179)
  local rows = {}
  local function memberRow(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, f); r:SetSize(360, LIST_ROW_H)
    r.pic = r:CreateTexture(nil, "ARTWORK"); r.pic:SetSize(12, 12); r.pic:SetPoint("LEFT", 0, 0)
    r.name = UI.newText(r, FONT.sa, 10, COLOR.paper, "LEFT"); r.name:SetPoint("LEFT", 18, 0)
    r.hl = r:CreateTexture(nil, "BACKGROUND"); r.hl:SetPoint("TOPLEFT", -4, 1); r.hl:SetPoint("BOTTOMRIGHT", 4, -1)
    r.hl:SetColorTexture(VIOLET.r, VIOLET.g, VIOLET.b, 0.15); r.hl:Hide()
    r:SetScript("OnEnter", function(self) self.hl:Show() end)
    r:SetScript("OnLeave", function(self) self.hl:Hide() end)
    r:SetScript("OnClick", function(self) if self.ov then Select(self.ov) end end)
    attachTip(r, "Member", "Click to select it.")
    rows[i] = r
    return r
  end
  s.ctrls = { nameF, onOff, attach, hideW, x, y, scale }
  s.refresh = function()
    local g = CurrentGroup()
    local on = s:base(g ~= nil)
    head:SetAlpha(on and 1 or DIM)
    local members = g and GloomsOverlays_GroupMembers(g) or {}
    for i, ov in ipairs(members) do
      local r = memberRow(i)
      r.ov = ov
      rowPicture(r.pic, ov)
      r.name:SetText(ov.name or "Overlay")
      r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -(179 + (i - 1) * LIST_ROW_H)); r:Show()
    end
    for i = #members + 1, #rows do rows[i]:Hide(); rows[i].ov = nil end
    empty:SetShown(#members == 0); empty:SetAlpha(on and 1 or DIM)
    hideW:setEnabled(on and g.attach ~= nil)
    s:fit(179 + ((#members > 0) and (#members * LIST_ROW_H) or math.ceil(empty:GetStringHeight())))
  end
  return f
end

-- ===========================================================================
-- Mount the windows (CONTRACTS §2, the two-window block).
-- ===========================================================================
local PROFILE_API = {
  noun   = "profile",
  names  = function() return GloomsOverlays_GetProfileNames() end,
  active = function() return GloomsOverlays_GetActiveProfileName() end,
  switch = function(name) GloomsOverlays_SetActiveProfile(name) end,
  create = function(name)
    local ok, err = GloomsOverlays_NewProfile(name)
    if ok then GloomsOverlays_SetActiveProfile(name) end
    return ok, err
  end,
  copy = function(name)
    local ok, err = GloomsOverlays_NewProfile(name, GloomsOverlays_GetActiveProfileName())
    if ok then GloomsOverlays_SetActiveProfile(name) end
    return ok, err
  end,
  rename = function(name) return GloomsOverlays_RenameProfile(GloomsOverlays_GetActiveProfileName(), name) end,
  delete = function() return GloomsOverlays_DeleteProfile(GloomsOverlays_GetActiveProfileName()) end,
  -- the selection belongs to the OUTGOING profile: start on the new one's first
  onChange = function()
    GloomsOverlays_ApplyAll()
    P.listOffset = 0
    local ov, g = recallPick()
    Select(ov, g)
  end,
  tips = {
    dropdown = "The active profile for this character. Each character remembers its own; the profile library is shared account-wide.",
    new      = "Creates an empty profile and switches to it. To start from THESE overlays instead, use Copy.",
    copy     = "Duplicates this profile — every overlay, portrait and group — and switches to the copy.",
    rename   = "Renames this profile. Characters using it follow the new name. Default can't be renamed.",
    delete   = "Deletes this profile (you'll be asked to confirm). Characters using it fall back to Default, which can't be deleted.",
  },
}

local function noOverlay() return CurrentOverlay() == nil end
local function notKind(k) return function() return Kind() ~= k end end
local function hideUnless(...)
  local set = {}; for _, k in ipairs({ ... }) do set[k] = true end
  return function() return not set[Kind()] end
end

GloomsHub:RegisterTab{
  id       = "overlays",   -- kept: the Hub's saved window places are filed under it
  title    = "UI",
  order    = 50,
  wordmark = "UI",
  product  = "GloomUI",
  windows  = true,
  profile  = PROFILE_API,
  selector = { build = buildSelector },
  tab      = { w = 360, build = buildTab },
  sections = {
    { id = "texture",    title = "Overlay & Texture",  build = buildTexture,      hidden = notKind("texture"),  dim = noOverlay },
    { id = "portrait",   title = "Portrait",           build = buildPortrait,     hidden = notKind("portrait") },
    { id = "size",       title = "Size & Position",    build = buildSize,         hidden = notKind("texture"),  dim = noOverlay },
    { id = "psize",      title = "Size & Position",    build = buildPortraitSize, hidden = notKind("portrait") },
    { id = "motion",     title = "Rotation & Motion",  build = buildMotion,       hidden = notKind("texture"),  dim = noOverlay },
    { id = "camera",     title = "3D Camera",          build = buildCamera,       hidden = notKind("portrait"), dim = function() return not is3D() end },
    { id = "layer",      title = "Layer",              build = buildLayer,        hidden = hideUnless("texture", "portrait"), dim = noOverlay },
    { id = "visibility", title = "Visibility",         build = buildVisibility,   hidden = hideUnless("texture", "portrait"), dim = noOverlay },
    { id = "group",      title = "Group",              build = buildGroup,        hidden = notKind("group") },
  },
  onOpen   = function()
    -- the last thing selected on this character and profile (nothing, if it's gone)
    if not CurrentOverlay() and not CurrentGroup() then selItem, selGroup = recallPick() end
    P.windowsOpen = true
    GloomsOverlays_SetPick(CurrentOverlay())
    GloomsOverlays_SetPreview(true)
    GloomsOverlays_SetEditing(CurrentOverlay(), CurrentGroup())
    P.refreshAll()
  end,
  onClose  = function()
    P.windowsOpen = false
    GloomsHub:ClosePicker()
    GloomsOverlays_SetEditing(nil, nil)
    if GloomsOverlays_SetPreview then GloomsOverlays_SetPreview(false) end
  end,
  refresh  = function() P.refreshAll() end,
  -- UNDO (the Hub's Undo.lua, 2026-09-30): the active profile — every overlay,
  -- portrait and group
  -- ARROW KEYS (the Hub, 2026-09-30): the selected group while its Group
  -- section is open; the selected overlay while its Size & Position is
  nudge    = function(dx, dy, isOpen)
    local g, ov = CurrentGroup(), CurrentOverlay()
    if g and isOpen("group") then GloomsOverlays_Nudge(g, dx, dy); return true end
    if ov and (isOpen("size") or isOpen("psize")) then GloomsOverlays_Nudge(ov, dx, dy); return true end
    return false
  end,
  undo     = {
    snapshot = function() return VibeOverlayDB and CopyTable(GloomsOverlays_GetProfile()) or {} end,
    restore  = function(snap)
      GloomsHub:UndoPatch(GloomsOverlays_GetProfile(), snap)
      GloomsOverlays_ApplyAll()
      if P.windowsOpen then GloomsOverlays_SetEditing(CurrentOverlay(), CurrentGroup()) end
      P.refreshAll()
    end,
    token    = function() return GloomsOverlays_GetActiveProfileName() end,
  },
}

-- The Hub's harness (tools/harness/sweep-v3.lua) drives these.
P.createTexture, P.createPortrait, P.createGroup = createTexture, createPortrait, createGroup
P.current, P.currentGroup = CurrentOverlay, CurrentGroup
GloomsOverlays_Windows = P

-- ---------------------------------------------------------------------------
-- Cross-file entry points (the asset browser and the slash router use these)
-- ---------------------------------------------------------------------------
-- Drop a texture name into the Texture field and apply it live (a texture
-- overlay only — a portrait has no texture).
function GloomsOverlays_SetTextureField(text, sheet)
  local ov = CurrentOverlay()
  if not ov or IsPortrait(ov) then return false end
  ov.sheet = sheet   -- the browser's grid (nil = a still texture)
  LiveApply("texture", (text or ""):match("^%s*(.-)%s*$"))
  FitToImage(ov)
  P.refreshAll()
  if P.texField then P.texField:SetText(text or "") end
  P.renderList()
  return true
end

function GloomsOverlays_HasSelection() local ov = CurrentOverlay(); return ov ~= nil and not IsPortrait(ov) end

-- The asset browser's "+ Save as New Overlay".
function GloomsOverlays_SaveFromPreview(textureInput, sheetData)
  if not VibeOverlayDB then error("VibeOverlayDB not initialised") end
  local list = Overlays()
  local ov = NewOverlay("New Texture " .. (#list + 1), textureInput, sheetData)
  list[#list + 1] = ov
  FitToImage(ov)
  GloomsOverlays_ApplyAll()
  GloomsHub:Open("overlays")
  Select(ov)
end

-- The old "open the manager window" entry point — now the tool's windows.
function GloomsOverlays_OpenManager() GloomsHub:ToggleWindow("overlays") end

-- Keep a target-class-colored overlay following the current target, and the
-- list's portrait pictures current.
local targetColorFrame = CreateFrame("Frame")
targetColorFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
targetColorFrame:SetScript("OnEvent", function()
  if not (GloomsOverlays_GetProfile and VibeOverlayDB) then return end
  if P.windowsOpen then P.renderList() end
  local touched = false
  for _, ov in ipairs(Overlays()) do
    if ov.useTargetColor then
      local _, classTag = UnitClass("target")
      local cc = classTag and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classTag]
      ov.tintR, ov.tintG, ov.tintB = cc and cc.r or 1, cc and cc.g or 1, cc and cc.b or 1
      touched = true
    end
  end
  if not touched then return end
  GloomsOverlays_ApplyAll()
  local ov = CurrentOverlay()
  if ov and ov.useTargetColor then for _, s in ipairs(P.secs) do if s.refresh then s.refresh() end end end
end)
