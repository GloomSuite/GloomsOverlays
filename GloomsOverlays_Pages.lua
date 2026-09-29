-- ============================================================
-- GloomsOverlays_Pages.lua — Gloom's Overlays
-- ★ THE TWO-WINDOW DESIGN (2026-09-27). Overlays was never mocked: it is
-- built from the Auras and Unit Frames pages (the owner, 2026-09-27: "there's
-- already a lot of source material"), so it reads as the same family. The Hub
-- (Windows.lua) owns the windows: the SELECTOR (240 wide), the SETTINGS
-- window (400) with its TAB, the pop-outs, the headers, the scrolling and
-- Global Settings (this tool's profile lives there). This file draws:
--   the selector's list — every overlay in the profile, its eye (lit = shown
--     on screen while the windows are open, whatever its conditions — Auras'
--     eye; the selected one shows until another is selected), the one being edited violet
--     30% (Auras' list without groups); New Overlay
--     and Browse Assets at the foot. Right-click an overlay for Rename ·
--     Duplicate · Delete; double-click renames;
--   the tab — "gloomOVERLAYS:" and the overlay's name (click it to switch
--     overlays, right-click for its menu);
--   five SECTIONS — Overlay & Texture · Size & Position · Rotation & Motion ·
--     Layer · Visibility.
-- Every number is a Unit Frames number: a labelled control is 31 tall (the
-- label's 11, 4, the 16-tall control), rows 41 apart, blocks 30 apart,
-- columns 170 at 0 / 190. Disabled = 30%, never hidden.
-- It is DRAWING only: every control writes the same overlay fields the engine
-- (GloomsOverlays.lua) always read, live. The asset browser
-- (GloomsOverlays_Preview.lua) still wears the first design's kit — the
-- pickers are waiting on the owner's mocks (Hub BACKLOG 16) — and now docks
-- beside the settings window. The previous tab (GloomsOverlays_Editor.lua) is
-- no longer loaded; delete it once the owner approves these windows.
-- ============================================================

local SKIN_NEEDS = 17
local Skin, skinMinor
if LibStub then Skin, skinMinor = LibStub("LibGloomSkin-1.0", true) end
if not Skin then return end
if (skinMinor or 0) < SKIN_NEEDS then
  print("|cffff7729Gloom's Overlays:|r the Overlays windows need Gloom's Hub with LibGloomSkin " .. SKIN_NEEDS .. " or newer — update Gloom's Hub. Your overlays keep rendering normally.")
  return
end

local UI, COLOR, FONT = Skin.UI, Skin.COLOR, Skin.FONT
local LIME, LILAC, VIOLET = COLOR.lime, COLOR.lilac, COLOR.violet
local DIM = UI.G_DIM or 0.3
local attachTip = UI.attachTip

local P = { secs = {}, listOffset = 0 }
local currentEditIndex

local function Overlays()
  local profile = GloomsOverlays_GetProfile and VibeOverlayDB and GloomsOverlays_GetProfile()
  return (profile and profile.overlays) or {}
end
local function CurrentOverlay()
  return currentEditIndex and Overlays()[currentEditIndex] or nil
end
local function Relayout() if GloomsHub.RefreshWindows then GloomsHub:RefreshWindows("overlays") end end

-- ---------------------------------------------------------------------------
-- Live apply — write into the selected overlay and rebuild the live frames,
-- exactly as the previous editor did. Where an overlay SITS (size, position,
-- strata, level) re-applies without a rebuild, which matters mid-drag.
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
-- white and are skipped (CONTRACTS §4).
local function OverlayColorSources()
  local out = {}
  for i, ov in ipairs(Overlays()) do
    local r, g, b = ov.tintR or 1, ov.tintG or 1, ov.tintB or 1
    if not (r == 1 and g == 1 and b == 1) then
      out[#out + 1] = { color = { r, g, b }, label = "Overlays › " .. (ov.name or ("Overlay " .. i)) }
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
  }
end
local function CopyTable(v)
  if type(v) ~= "table" then return v end
  local t = {}; for k, x in pairs(v) do t[k] = CopyTable(x) end; return t
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
local function SelectOverlay(index)
  local ov = index and Overlays()[index]
  currentEditIndex = ov and index or nil
  -- the selected overlay shows at once, whatever its saved eye (the engine's
  -- GloomsOverlays_SetPick); the one left goes back to its own eye
  GloomsOverlays_SetPick(ov)
  P.refreshAll()
end
P.SelectOverlay = SelectOverlay

-- ---------------------------------------------------------------------------
-- Docked drawers (the asset browser lives in GloomsOverlays_Preview.lua). A
-- drawer hangs from the Suite's root — it scales and closes with the windows —
-- and sits 20 beside the settings window, flipping to the selector's far side
-- if it would run off the screen.
-- ---------------------------------------------------------------------------
local drawers = {}
function GloomsOverlays_RegisterDrawer(f) drawers[#drawers + 1] = f end
function GloomsOverlays_CloseDrawers(keep)
  for _, f in ipairs(drawers) do if f ~= keep and f:IsShown() then f:Hide() end end
end
function GloomsOverlays_DockDrawer(f)
  local root = GloomsHub.SuiteRoot and GloomsHub:SuiteRoot()
  local set = GloomsHub.SuiteWindow and GloomsHub:SuiteWindow("overlays", "set")
  if not (root and set) then return end
  f:SetParent(root)
  f:SetMovable(false); f:SetClampedToScreen(false)
  f:ClearAllPoints()
  local right, sw = set:GetRight(), root:GetRight()
  if right and sw and (right + 20 + (f:GetWidth() or 0)) > sw then
    local sel = GloomsHub:SuiteWindow("overlays", "sel")
    f:SetPoint("TOPRIGHT", sel or set, "TOPLEFT", -20, 0)
  else
    f:SetPoint("TOPLEFT", set, "TOPRIGHT", 20, 0)
  end
  if GloomsHub.SuiteManage then GloomsHub:SuiteManage(f) end
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

-- A section's frame; its controls are `ctrls`, all dimmed while no overlay is
-- selected (the tab says what to do).
local function Section(parent, h)
  local f = CreateFrame("Frame", nil, parent); f:SetSize(360, h)
  local s = { frame = f, ctrls = {} }
  P.secs[#P.secs + 1] = s
  f:HookScript("OnShow", function() if s.refresh then s.refresh() end end)
  function s:base()
    local on = CurrentOverlay() ~= nil
    for _, c in ipairs(self.ctrls) do if c.refresh then c:refresh() end; if c.setEnabled then c:setEnabled(on) end end
    return on
  end
  return f, s
end

-- ===========================================================================
-- THE MENUS — an overlay's right-click menu, and the switch list.
-- ===========================================================================
local function renameSelected()
  local ov = CurrentOverlay(); if not ov then return end
  UI.nameDialog("Rename Overlay", ov.name or "", function(nm)
    nm = nm and nm:match("^%s*(.-)%s*$")
    if not nm or nm == "" then return end
    LiveApply("name", nm); P.refreshAll()
  end)
end
local function duplicateSelected()
  local src = CurrentOverlay(); if not src then return end
  local copy = CopyTable(src)
  copy.name = (src.name or "Overlay") .. " copy"
  table.insert(Overlays(), currentEditIndex + 1, copy)
  GloomsOverlays_ApplyAll()
  SelectOverlay(currentEditIndex + 1)
end
local function deleteSelected()
  local ov = CurrentOverlay(); if not ov then return end
  local idx = currentEditIndex
  UI.confirm(("Delete the overlay \"%s\"?  This can't be undone."):format(ov.name or "?"), function()
    table.remove(Overlays(), idx)
    GloomsOverlays_ApplyAll()
    local n = #Overlays()
    SelectOverlay(n > 0 and math.min(idx, n) or nil)
  end)
end
function P.overlayMenu(anchor)
  UI.gList(anchor, {
    { value = "rename", label = "Rename" },
    { value = "dupe", label = "Duplicate" },
    { value = "delete", label = "Delete", danger = true, divider = true },
  }, nil, function(v)
    if v == "rename" then renameSelected() elseif v == "dupe" then duplicateSelected() elseif v == "delete" then deleteSelected() end
  end, { cursor = true })
end
local function switchMenu(anchor)
  local list = {}
  for i, ov in ipairs(Overlays()) do list[#list + 1] = { value = i, label = ov.name or ("Overlay " .. i) } end
  if #list == 0 then return end
  UI.gList(anchor, list, currentEditIndex, function(i) SelectOverlay(i) end)
end
local function createOverlay()
  local list = Overlays()
  local n = #list + 1
  list[n] = NewOverlay("New Overlay " .. n)
  GloomsOverlays_ApplyAll()
  SelectOverlay(n)
end

-- ===========================================================================
-- THE SELECTOR — the overlay list from y 52, 18 to a line (Auras' list): the
-- name in Sansation 10 at x 0 (50% when switched off), the eye at the right
-- (lime = on screen now, white 40% = not); the one being edited violet 30% across the whole window. New Overlay
-- and Browse Assets at the foot, 20 in from the sides and the bottom. It
-- scrolls by whole lines when the window is too short for it.
-- ===========================================================================
local LIST_TOP, LIST_ROW_H, LIST_FOOT = 52, 18, 55
local listRows = {}

local function listRow(i)
  local r = listRows[i]
  if r then return r end
  r = CreateFrame("Button", nil, P.listClip)
  r:SetSize(200, LIST_ROW_H)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r.hl = r:CreateTexture(nil, "BACKGROUND"); r.hl:SetPoint("TOPLEFT", -20, 1); r.hl:SetPoint("BOTTOMRIGHT", 20, -1)
  r.hl:Hide()
  r.name = UI.newText(r, FONT.sa, 10, COLOR.paper, "LEFT"); r.name:SetPoint("LEFT", 0, 0)
  r.name:SetWidth(176); r.name:SetWordWrap(false)
  r.eye = CreateFrame("Button", nil, r); r.eye:SetSize(14, 14); r.eye:SetPoint("RIGHT", 0, 0)
  r.eye.t = r.eye:CreateTexture(nil, "ARTWORK"); r.eye.t:SetSize(14, 8.5); r.eye.t:SetPoint("CENTER", 0, 0)
  r.eye.t:SetTexture(UI.G_EYE); r.eye.t:SetTexCoord(0, 56 / 64, 0, 34 / 64)
  r.eye:SetScript("OnClick", function()
    local ov = r.index and Overlays()[r.index]; if not ov then return end
    GloomsOverlays_ToggleEye(ov)
    P.refreshAll()
  end)
  attachTip(r.eye, "Show on screen", "Shows this overlay on screen while these windows are open — in or out of combat, whatever its Visibility says — so you can place it. The overlay you select shows while it's selected — click its eye to hide it for now; once you select another, it goes back to its own eye. It doesn't change when the overlay shows in play.")
  r:SetScript("OnEnter", function(self)
    if self.index ~= currentEditIndex then self.hl:SetColorTexture(VIOLET.r, VIOLET.g, VIOLET.b, 0.15); self.hl:Show() end
  end)
  r:SetScript("OnLeave", function(self) if self.index ~= currentEditIndex then self.hl:Hide() end end)
  r:SetScript("OnClick", function(self, button)
    if not self.index then return end
    SelectOverlay(self.index)
    if button == "RightButton" then P.overlayMenu(self) end
  end)
  r:SetScript("OnDoubleClick", function(self) if self.index then SelectOverlay(self.index); renameSelected() end end)
  listRows[i] = r
  return r
end

function P.renderList()
  if not P.listClip then return end
  local list = Overlays()
  local view = math.max(LIST_ROW_H, math.floor((P.listHost:GetHeight() or 0) - LIST_TOP - LIST_FOOT))
  local fits = math.max(1, math.floor(view / LIST_ROW_H))
  local maxOff = math.max(0, #list - fits)
  P.listOffset = math.max(0, math.min(maxOff, P.listOffset or 0))
  local n = 0
  for i = P.listOffset + 1, math.min(#list, P.listOffset + fits) do
    n = n + 1
    local r, ov = listRow(n), list[i]
    r.index = i
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", P.listClip, "TOPLEFT", 0, -(n - 1) * LIST_ROW_H)
    r.name:SetText(ov.name or ("Overlay " .. i))
    -- a switched-off overlay greys; the eye is lime while it shows on screen
    r.name:SetAlpha(ov.enabled ~= false and 1 or 0.5)
    if GloomsOverlays_EyeOn(ov) then UI.tint(r.eye.t, LIME) else r.eye.t:SetVertexColor(1, 1, 1, 0.4) end
    if i == currentEditIndex then r.hl:SetColorTexture(VIOLET.r, VIOLET.g, VIOLET.b, 0.3); r.hl:Show() else r.hl:Hide() end
    r:Show()
  end
  for i = n + 1, #listRows do listRows[i]:Hide(); listRows[i].index = nil end
  P.empty:SetShown(#list == 0)
  local track, thumb = P.listTrack, P.listThumb
  if maxOff > 0 then
    track:Show()
    local th = math.max(24, math.floor(view * fits / #list + 0.5))
    thumb:SetHeight(th)
    thumb:ClearAllPoints(); thumb:SetPoint("TOP", track, "TOP", 0, -math.floor((view - th) * (P.listOffset / maxOff) + 0.5))
  else
    track:Hide()
  end
  P.listMax = maxOff
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
  P.empty = Note(clip, "No overlays in this profile yet. New Overlay makes a blank one; Browse Assets finds a texture first.", 200)
  P.empty:SetPoint("TOPLEFT", 0, 0)
  -- the scrollbar, in the window's right margin, only while the list overflows
  local track = CreateFrame("Frame", nil, c); track:SetWidth(3)
  track:SetPoint("TOPLEFT", c, "TOPLEFT", 230.5, -LIST_TOP); track:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 230.5, LIST_FOOT)
  local tt = track:CreateTexture(nil, "BACKGROUND"); tt:SetAllPoints(); tt:SetColorTexture(0, 0, 0, 0.5)
  local thumb = CreateFrame("Frame", nil, track); thumb:SetWidth(3)
  local th = thumb:CreateTexture(nil, "ARTWORK"); th:SetAllPoints(); th:SetColorTexture(VIOLET.r, VIOLET.g, VIOLET.b, 0.5)
  track:Hide()
  P.listTrack, P.listThumb = track, thumb

  local newO = UI.gButton(c, "New Overlay")
  newO:SetPoint("BOTTOMLEFT", 20, 20)
  newO:SetScript("OnClick", createOverlay)
  attachTip(newO, "New overlay", "Creates a blank overlay in this profile and opens it for editing.")
  local browse = UI.gButton(c, "Browse Assets")
  browse:SetPoint("BOTTOMRIGHT", -20, 20)
  browse:SetScript("OnClick", function()
    if GloomsOverlays_ToggleAssetBrowser then
      local ov = CurrentOverlay()
      GloomsOverlays_ToggleAssetBrowser(ov and ov.texture or nil)
    end
  end)
  attachTip(browse, "Asset browser", "Preview textures, play spritesheets and keep favorites. Pick one to drop it into the overlay being edited, or save it as a new overlay.")
  P.renderList()
end

-- ===========================================================================
-- THE TAB — "gloomOVERLAYS:" lime, the overlay's name white, Sansation 10.
-- Click the name for the list of overlays; right-click it for its menu.
-- ===========================================================================
local function buildTab(tab)
  local t = {}
  local lead = UI.newText(tab, FONT.sa, 10, LIME, "LEFT"); lead:SetPoint("TOPLEFT", 20, -9)
  lead:SetText("gloomOVERLAYS: ")
  local name = UI.newText(tab, FONT.sa, 10, COLOR.paper, "LEFT"); name:SetPoint("LEFT", lead, "RIGHT", 0, 0)
  name:SetWordWrap(false)
  local hit = CreateFrame("Button", nil, tab); hit:SetHeight(16); hit:SetPoint("LEFT", name, "LEFT", 0, 0)
  hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  hit:SetScript("OnClick", function(self, button)
    if not CurrentOverlay() then return end
    if button == "RightButton" then P.overlayMenu(self) else switchMenu(self) end
  end)
  attachTip(hit, "The overlay you're editing", "Click to switch to another overlay. Right-click to rename, duplicate or delete this one.")
  function t:refresh()
    local ov = CurrentOverlay()
    if ov then name:SetText(ov.name or "Overlay"); name:SetAlpha(1)
    else name:SetText("No overlay yet — click New Overlay"); name:SetAlpha(0.6) end
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
  local f, s = Section(parent, 174)
  local nameF = cell(f, "Overlay Name", 360, function(c, w)
    return UI.gField(c, w, {
      commit = function(text)
        text = (text or ""):match("^%s*(.-)%s*$")
        if text ~= "" and CurrentOverlay() then LiveApply("name", text); P.refreshAll() end
      end,
      revert = function(self) local ov = CurrentOverlay(); self:SetText(ov and ov.name or "") end,
    })
  end)
  function nameF:refresh() if not self.control:HasFocus() then local ov = CurrentOverlay(); self.control:SetText(ov and ov.name or "") end end
  place(nameF, 0, 0)
  local texF = cell(f, "Texture", 294, function(c, w)
    return UI.gField(c, w, {
      placeholder = "A media name, atlas, file ID or path",
      commit = function(text) if CurrentOverlay() then LiveApply("texture", (text or ""):match("^%s*(.-)%s*$")) end end,
      revert = function(self) local ov = CurrentOverlay(); self:SetText(ov and ov.texture or "") end,
    })
  end)
  function texF:refresh() if not self.control:HasFocus() then local ov = CurrentOverlay(); self.control:SetText(ov and ov.texture or "") end end
  place(texF, 0, 41)
  P.texField = texF.control
  local browse = UI.gButton(f, "Browse", { w = 60, h = 16, size = 10, onClick = function()
    if GloomsOverlays_OpenAssetBrowser then GloomsOverlays_OpenAssetBrowser(P.texField:GetText()) end
  end })
  browse:SetPoint("TOPLEFT", 300, -56)
  attachTip(browse, "Asset browser", "Preview textures, play spritesheets and keep favorites. Picking one drops it into this field.")
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
      s.refresh()
    end)
  attachTip(cls.control, "Class color", "Tints the overlay with your class color, or your target's (it follows the target as it changes). While on, it replaces the Tint Color.")
  place(cls, 190, 143)
  s.ctrls = { nameF, texF, browse, alpha, blend, tint, cls }
  s.refresh = function()
    local on = s:base()
    local ov = CurrentOverlay()
    local locked = ov and (ov.useClassColor == true or ov.useTargetColor == true)
    tint:setEnabled(on and not locked)
  end
  return f
end

-- ===========================================================================
-- SECTION · SIZE & POSITION — Width | Horizontal, Height | Vertical. Ranges
-- cover the owner's live profiles with headroom (the previous editor's).
-- ===========================================================================
local function buildSize(parent)
  local f, s = Section(parent, 72)
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
  local x = Dial(f, 170, { label = "Horizontal Position", min = -1000, max = 1000, step = 1, unit = "px", dragPx = 1600, get = num("x", 0), set = setL("x") })
  local y = Dial(f, 170, { label = "Vertical Position", min = -1000, max = 1000, step = 1, unit = "px", dragPx = 1600, get = num("y", 0), set = setL("y") })
  place(w, 0, 0); place(x, 190, 0); place(h, 0, 41); place(y, 190, 41)
  s.ctrls = { w, h, x, y, link }
  s.refresh = function() s:base() end
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
    local h = 41 + math.ceil(note:GetStringHeight())
    if math.abs((f:GetHeight() or 0) - h) > 0.5 then f:SetHeight(h) end
  end
  return f
end

-- ===========================================================================
-- SECTION · VISIBILITY — the overlay's on/off (the list's eye), then the
-- conditions as checkboxes, two columns 26 apart: it shows while ANY checked
-- one is true.
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
  attachTip(onOff.control, "Overlay on / off", "Off: the overlay never shows in play, whatever the conditions below say; its settings are kept. (While these windows are open, any with a lit eye still show, so you can place them.)")
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
    local live = on and CurrentOverlay().enabled ~= false
    for _, chk in ipairs(checks) do chk:setEnabled(live) end
    note:SetAlpha(live and 1 or DIM)
  end
  return f
end

-- ===========================================================================
-- Mount the Overlays windows (CONTRACTS §2, the two-window block).
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
  -- overlay indexes belong to the OUTGOING profile: start on the new one's first
  onChange = function()
    GloomsOverlays_ApplyAll()
    P.listOffset = 0
    SelectOverlay(#Overlays() > 0 and 1 or nil)
  end,
  tips = {
    dropdown = "The active profile for this character. Each character remembers its own; the profile library is shared account-wide.",
    new      = "Creates an empty profile and switches to it. To start from THESE overlays instead, use Copy.",
    copy     = "Duplicates this profile — every overlay — and switches to the copy.",
    rename   = "Renames this profile. Characters using it follow the new name. Default can't be renamed.",
    delete   = "Deletes this profile (you'll be asked to confirm). Characters using it fall back to Default, which can't be deleted.",
  },
}

local function noOverlay() return CurrentOverlay() == nil end

GloomsHub:RegisterTab{
  id       = "overlays",
  title    = "Overlays",
  order    = 50,
  wordmark = "OVERLAYS",
  product  = "GloomOverlays",
  windows  = true,
  profile  = PROFILE_API,
  selector = { build = buildSelector },
  tab      = { w = 360, build = buildTab },
  sections = {
    { id = "texture",    title = "Overlay & Texture",  build = buildTexture,    dim = noOverlay },
    { id = "size",       title = "Size & Position",    build = buildSize,       dim = noOverlay },
    { id = "motion",     title = "Rotation & Motion",  build = buildMotion,     dim = noOverlay },
    { id = "layer",      title = "Layer",              build = buildLayer,      dim = noOverlay },
    { id = "visibility", title = "Visibility",         build = buildVisibility, dim = noOverlay },
  },
  onOpen   = function()
    if not CurrentOverlay() and #Overlays() > 0 then currentEditIndex = 1 end
    P.windowsOpen = true
    GloomsOverlays_SetPick(CurrentOverlay())
    GloomsOverlays_SetPreview(true)
    P.refreshAll()
  end,
  onClose  = function()
    P.windowsOpen = false
    GloomsOverlays_CloseDrawers()
    if GloomsOverlays_SetPreview then GloomsOverlays_SetPreview(false) end
  end,
  refresh  = function() P.refreshAll() end,
}

-- ---------------------------------------------------------------------------
-- Cross-file entry points (the asset browser and the slash router use these)
-- ---------------------------------------------------------------------------
-- Drop a texture name into the Texture field and apply it live.
function GloomsOverlays_SetTextureField(text)
  if not CurrentOverlay() then return false end
  LiveApply("texture", (text or ""):match("^%s*(.-)%s*$"))
  if P.texField then P.texField:SetText(text or "") end
  return true
end

function GloomsOverlays_HasSelection() return CurrentOverlay() ~= nil end

-- The asset browser's "+ Save as New Overlay".
function GloomsOverlays_SaveFromPreview(textureInput, sheetData)
  if not VibeOverlayDB then error("VibeOverlayDB not initialised") end
  local list = Overlays()
  local n = #list + 1
  list[n] = NewOverlay("New Overlay " .. n, textureInput, sheetData)
  GloomsOverlays_ApplyAll()
  GloomsHub:Open("overlays")
  SelectOverlay(n)
end

-- The old "open the manager window" entry point — now the tool's windows.
function GloomsOverlays_OpenManager() GloomsHub:ToggleWindow("overlays") end

-- Keep a target-class-colored overlay following the current target.
local targetColorFrame = CreateFrame("Frame")
targetColorFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
targetColorFrame:SetScript("OnEvent", function()
  if not (GloomsOverlays_GetProfile and VibeOverlayDB) then return end
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
