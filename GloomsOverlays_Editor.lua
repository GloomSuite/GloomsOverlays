-- ============================================================
-- GloomsOverlays_Editor.lua
-- The OVERLAYS tab of the Suite window (Phase E gate B).
--
-- The two old floating windows (GloomsOverlaysManager 400x520 and
-- GloomsOverlaysEditor 460x560) are GONE. Their contents mount as ONE tab
-- inside GloomsHub's shell, laid out the way Gloom's Bars lays out its tab
-- (the owner 2026-07-24 — GB is the reference, not GA):
--   • LEFT RAIL  — the GO mark, the shared profile block, and the overlay list.
--     The profile decides what everything else edits, so it is never hidden.
--   • RIGHT PANE — the selected overlay's settings, scrolling.
--   • FOOTER     — Save & Apply + status, in-tab (CONTRACTS §2).
-- Every widget comes from LibGloomSkin-1.0; the file-local MakeButton /
-- MakeCheck / MakeEditBox / MakeSlider helpers (which WERE the native Blizzard
-- chrome) are deleted. Window chrome, Escape and dragging belong to the shell.
-- ============================================================

-- --------------------------------------------------------------------------
-- Toolkit + tokens — CONSUMED from LibGloomSkin-1.0 (shipped by GloomsHub,
-- our hard dependency, so it is always loaded first). Surface pinned in
-- GloomsHub/docs/CONTRACTS.md §4.
-- --------------------------------------------------------------------------
-- --------------------------------------------------------------------------
-- ★ SHARED-TOOLKIT VERSION GATE — see GloomsHub/docs/CONTRACTS.md §6.
-- LibGloomSkin lives in GloomsHub and GROWS: each MINOR adds widgets this file
-- may call. WoW's "## Dependencies: GloomsHub" only checks that the Hub is
-- PRESENT, never that it is NEW ENOUGH — so a Hub a release or two behind would
-- let this file load and then die on the first nil widget, spraying Lua errors
-- at someone who has no idea what a MINOR is. Check first, and fail with ONE
-- actionable sentence instead.
-- ★ BUMP SKIN_NEEDS IN THE SAME COMMIT that first calls a newer widget.
-- --------------------------------------------------------------------------
-- Stays 4 on purpose. This file's one MINOR-6 call, UI.RegisterColorProvider,
-- is guarded by `if UI.RegisterColorProvider then` — against an older Hub the
-- picker just doesn't list overlay tints, which is cosmetic. Declaring 6 would
-- disable the whole EDITOR over that, and the gate exists to state what a file
-- genuinely NEEDS. Drop the guard and this must become 6 in the same commit.
local SKIN_MAJOR, SKIN_NEEDS = "LibGloomSkin-1.0", 4

local Skin, skinMinor = LibStub(SKIN_MAJOR, true)
if not Skin or (skinMinor or 0) < SKIN_NEEDS then
  local found = Skin and ("v" .. tostring(skinMinor or 0)) or "none"
  local warn = CreateFrame("Frame")
  warn:RegisterEvent("PLAYER_LOGIN")
  warn:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    print("|cffff7729Gloom's Overlays:|r please update |cff936bffGloom's Hub|r. This version of "
      .. "Overlays needs a newer Hub toolkit (needs v" .. SKIN_NEEDS .. ", found " .. found
      .. "), so the OVERLAYS tab is unavailable. Your overlays keep rendering normally.")
  end)
  return   -- chunk-level return: the tab is never registered; overlay RENDERING is untouched
end
local UI = Skin.UI
local COLOR, FONT = Skin.COLOR, Skin.FONT
local TEXT, MUTE = COLOR.text, COLOR.mute

local newText, flatButton, flatEditBox = UI.newText, UI.flatButton, UI.flatEditBox
local makeToggle, sliderRow, colorSwatch = UI.makeToggle, UI.sliderRow, UI.colorSwatch
local makeScrollbar, attachTip, hLine = UI.makeScrollbar, UI.attachTip, UI.hLine

-- Every (Hub font, size) pair this tab draws BEYOND the Hub's own warm list — a
-- cold (font file, size) pair renders BLANK on its first draw each session
-- (CONTRACTS §4). Queued now; warmed with the Hub's batch at PLAYER_ENTERING_WORLD.
-- Audited with the contract's own check (grep -ohE 'FONT\.\w+, [0-9.]+' *.lua):
-- this tab draws title 16/17 · head 12/13 · body 10.5/11/12 · label 11, plus
-- bodyM 11/12/13 indirectly (flatButton/attachTip) and body 12 (flatEditBox,
-- dropdown rows). The Hub's base list covers title 17 · head 12 · body
-- 10.5/11/12/13 · bodyM 11/12/13 — so only these three are missing.
UI.RegisterWarmPairs({
  { FONT.title, 16 },   -- the asset browser drawer's title
  { FONT.head, 13 },    -- editor section headers
  { FONT.label, 11 },   -- sliderRow value labels (Rotation, Alpha)
})

-- --------------------------------------------------------------------------
-- Layout constants. The shell hands us a container of AT LEAST 860x626
-- (CONTRACTS §2, PINNED). The old windows were 400 + 460 = exactly 860 with
-- zero gutter, so their numbers are rebalanced rather than ported.
-- --------------------------------------------------------------------------
local RAIL_W    = 240     -- left rail: mark + profile + overlay list
local FOOTER_H  = 44      -- the tab's own footer row
local PAD       = 18      -- editor content inset
-- 11 rows × 26 = 286px of list, leaving a gap above the Duplicate/Delete row
-- pinned to the rail's bottom (rail is 582 tall: 626 content − the 44 footer).
-- Matches the old manager window's capacity (400×520 fitted ~11).
local LIST_ROWS = 11
local LIST_ROW_H = 26
-- Tall enough for the last Visibility toggle at -1004 plus its 20px height.
-- (Grew by 50 when Size & position and Spin speed became slider rows — a slider
-- is two lines where a typed box was one — and by another 80 when Layer gained
-- the Level row and two more stratas.)
local CONTENT_H = 1040    -- editor scroll-child height

local container, rail, editorScroll, editorChild, editorBody, emptyNote
local listScroll, listContent, statusText, countText
local profileBlock
local rowPool = {}
local currentEditIndex

-- Editor widgets hang on E rather than becoming file locals: this chunk would
-- otherwise crowd Lua's 200-locals-per-function cap (the trap GA hit).
local E = {}

local RefreshList, SelectOverlay

-- --------------------------------------------------------------------------
-- Docked drawers (the asset browser lives in GloomsOverlays_Preview.lua).
-- Parented to the CONTAINER so a drawer hides with the tab AND the window,
-- and flipped to the left if docking right would run off-screen.
-- --------------------------------------------------------------------------
local drawers = {}

function GloomsOverlays_RegisterDrawer(f)
  drawers[#drawers + 1] = f
end

function GloomsOverlays_CloseDrawers(keep)
  for _, f in ipairs(drawers) do
    if f ~= keep and f:IsShown() then f:Hide() end
  end
end

function GloomsOverlays_DockDrawer(f)
  if not container then return end
  f:SetParent(container)
  f:SetMovable(false)
  f:SetClampedToScreen(false)
  f:ClearAllPoints()
  local pr, sw, fw = container:GetRight(), UIParent:GetRight(), (f:GetWidth() or 0)
  if pr and sw and (pr + fw + 2) > sw then
    f:SetPoint("TOPRIGHT", container, "TOPLEFT", 1, 0)     -- flip: dock on the left
  else
    f:SetPoint("TOPLEFT", container, "TOPRIGHT", -1, 0)    -- dock on the right (flush)
  end
end

-- --------------------------------------------------------------------------
-- Live-apply helpers — write into profile.overlays[currentEditIndex] and
-- rebuild the live frames, exactly as the old editor did.
-- --------------------------------------------------------------------------
local function CurrentOverlay()
  if not currentEditIndex then return nil end
  local profile = GloomsOverlays_GetProfile and GloomsOverlays_GetProfile()
  return profile and profile.overlays and profile.overlays[currentEditIndex]
end

-- Every overlay's tint, by name — what the Hub's color picker lists as "where is
-- this in use". A walk rather than a per-control getter: the Tint swatch above
-- re-points at the selected overlay, so it could only ever report that one.
-- An UNTINTED overlay is stored as white, and reporting every one of those would
-- bury the row in a color nobody chose — so plain white is skipped.
local function OverlayColorSources()
  local out = {}
  local profile = GloomsOverlays_GetProfile and GloomsOverlays_GetProfile()
  for i, ov in ipairs(profile and profile.overlays or {}) do
    local r, g, b = ov.tintR or 1, ov.tintG or 1, ov.tintB or 1
    if not (r > 0.99 and g > 0.99 and b > 0.99) then
      out[#out + 1] = { color = { r, g, b },
        label = ("Overlays › Tint (%s)"):format(ov.name or ("Overlay " .. i)) }
    end
  end
  return out
end
if UI.RegisterColorProvider then UI.RegisterColorProvider("GloomsOverlays", OverlayColorSources) end

local function LiveApply(field, value)
  local ov = CurrentOverlay()
  if not ov then return end
  ov[field] = value
  GloomsOverlays_ApplyAll()
end

local function LiveApplyMulti(tbl)
  local ov = CurrentOverlay()
  if not ov then return end
  for k, v in pairs(tbl) do ov[k] = v end
  GloomsOverlays_ApplyAll()
end

local function SetStatus(text)
  if statusText then statusText:SetText(text or "") end
end

-- --------------------------------------------------------------------------
-- Small local widget shapes built on the lib
-- --------------------------------------------------------------------------
local function label(parent, text, x, y, size, cc)
  local fs = newText(parent, FONT.body, size or 12, cc or TEXT, "LEFT")
  fs:SetPoint("TOPLEFT", x, y); fs:SetText(text)
  return fs
end

local function sectionHead(parent, text, y)
  local fs = newText(parent, FONT.head, 13, COLOR.purple, "LEFT")
  fs:SetPoint("TOPLEFT", PAD, y); fs:SetText(text:upper())
  local div = hLine(parent)
  div:SetPoint("TOPLEFT", PAD, y - 18); div:SetPoint("TOPRIGHT", -PAD, y - 18)
  return fs
end

local function box(parent, w, h, x, y, onCommit)
  local e = flatEditBox(parent, w, h or 22)
  e:SetPoint("TOPLEFT", x, y)
  e:SetMaxLetters(256)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus(); onCommit(self) end)
  e:HookScript("OnEditFocusLost", function(self) onCommit(self) end)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  return e
end

-- A number row: UI.sliderRow for dragging, plus a small edit box in the row's
-- top-right corner so exact values stay TYPEABLE (suite to-do 2 — the family
-- answer is both, not one or the other). Rotation and Alpha keep the plain
-- read-only rows; these are the fields you type precise numbers into.
--
-- ★ `fmt` returns "" on purpose. sliderRow parks its own read-only value text
-- at TOPRIGHT -18 — exactly where the edit box goes — so blanking it hands that
-- slot over. The box IS the readout as well as the input.
--
-- The slider spans its PARENT (18px insets, fixed in the lib), so a caller that
-- wants a narrower row gives it a slot frame rather than an x/width.
-- `apply(v)` receives an integer already clamped to [minV, maxV].
-- Returns { refresh, box }.
local function numRow(parent, yTop, labelText, minV, maxV, get, apply, sub)
  local h = {}

  local ebox = flatEditBox(parent, 56, 18)
  ebox:SetPoint("TOPRIGHT", -18, yTop + 3)   -- bottom lands on the slider's top edge
  ebox:SetMaxLetters(6)
  ebox:SetJustifyH("CENTER")
  h.box = ebox

  local row = sliderRow(parent, yTop, labelText, minV, maxV, 1, get,
    function(v)
      v = math.floor(v + 0.5)
      apply(v)
      ebox:SetText(tostring(v))
    end,
    function() return "" end,
    sub)

  function h:refresh()
    row:refresh()                       -- `applying` guards this: no apply() call
    ebox:SetText(tostring(get() or minV))
  end

  -- Typed entry commits on Enter or focus loss, like every other box in the
  -- tab. Out-of-range numbers are clamped rather than kept, so the slider and
  -- the box can never disagree about what the overlay is set to.
  local function commit(self)
    local v = tonumber(self:GetText())
    if v then apply(math.max(minV, math.min(maxV, math.floor(v + 0.5)))) end
    h:refresh()
  end
  ebox:SetScript("OnEnterPressed", function(self) self:ClearFocus(); commit(self) end)
  ebox:HookScript("OnEditFocusLost", commit)
  -- Restore BEFORE dropping focus: ClearFocus fires OnEditFocusLost, and a
  -- commit of the half-typed text would defeat the escape.
  ebox:SetScript("OnEscapePressed", function(self) h:refresh(); self:ClearFocus() end)

  return h
end

-- A caret-art arrow button. The bundled Khand/GeneralSans faces have no
-- ▲▼◄► glyphs (they render as tofu), so the nudge arrows use the family's
-- caret PNG rotated, exactly like the accordion carets.
local ROT = { right = 0, down = UI.CARET_DOWN, left = math.pi, up = math.pi / 2 }
local function caretButton(parent, w, h, dir, x, y)
  local b = flatButton(parent, w, h, COLOR.heroic, "", 11)
  b:SetBase(0.2); b:SetPoint("TOPLEFT", x, y)
  local t = b:CreateTexture(nil, "ARTWORK")
  t:SetTexture(UI.CARET)
  t:SetVertexColor(COLOR.orange.r, COLOR.orange.g, COLOR.orange.b)
  t:SetSize(8, 8); t:SetPoint("CENTER"); t:SetRotation(ROT[dir])
  return b
end

-- A labelled sliding switch (the lib toggle + its caption).
local function toggleRow(parent, text, x, y, get, set)
  local t = makeToggle(parent, get, set)
  t:SetPoint("TOPLEFT", x, y)
  local fs = newText(parent, FONT.body, 12, TEXT, "LEFT")
  fs:SetPoint("LEFT", t, "RIGHT", 10, 0); fs:SetText(text)
  return t
end

-- A row of mutually-exclusive choices (blend mode, strata, spin direction):
-- flatButtons where the selected one is ORANGE (flatButton:SetActive).
local function choiceRow(parent, choices, bw, bh, x, y, gap, onPick)
  local btns, cx = {}, x
  for _, c in ipairs(choices) do
    local value, text = c[1], c[2] or c[1]
    local b = flatButton(parent, bw, bh, COLOR.heroic, text, 11)
    b:SetBase(0.2); b:SetPoint("TOPLEFT", cx, y)
    b:SetScript("OnClick", function()
      onPick(value)
      for _, e in ipairs(btns) do e.b:SetActive(e.v == value) end
    end)
    btns[#btns + 1] = { b = b, v = value }
    cx = cx + bw + (gap or 4)
  end
  return {
    sync = function(value)
      for _, e in ipairs(btns) do e.b:SetActive(e.v == value) end
    end,
  }
end

-- --------------------------------------------------------------------------
-- LEFT RAIL — mark, profile block, overlay list
-- --------------------------------------------------------------------------
local function BuildRail(c)
  rail = CreateFrame("Frame", nil, c)
  rail:SetPoint("TOPLEFT", 0, 0)
  rail:SetPoint("BOTTOMLEFT", 0, FOOTER_H)
  rail:SetWidth(RAIL_W)

  local X, W = 14, RAIL_W - 28

  -- The GO mark + wordmark. This tab BUILT this header inline first; the owner
  -- liked it enough to want it on every tab, so the geometry was promoted into
  -- the shared UI.tabHeader (LibGloomSkin MINOR 4) and this is now a CONSUMER
  -- of it. Do not re-inline it here — that is how the four tabs drift apart.
  UI.tabHeader(rail, {
    texture = "Interface\\AddOns\\GloomsOverlays\\Media\\ui\\logo.png",
    label   = "GLOOM'S OVERLAYS",
    x       = X,
  })

  -- The shared profile mechanism (LibGloomSkin MINOR 3) — the SAME control
  -- Gloom's Bars and Gloom's Auras use. Delete routes through the confirm modal.
  profileBlock = UI.profileBlock(rail, W, {
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
    rename = function(name)
      return GloomsOverlays_RenameProfile(GloomsOverlays_GetActiveProfileName(), name)
    end,
    delete = function()
      return GloomsOverlays_DeleteProfile(GloomsOverlays_GetActiveProfileName())
    end,
    -- Overlay indexes belong to the OUTGOING profile — drop the selection.
    onChange = function()
      GloomsOverlays_ApplyAll()
      SelectOverlay(nil)
      RefreshList()
    end,
  })
  profileBlock.frame:SetPoint("TOPLEFT", X, -62)

  local d2 = hLine(rail); d2:SetPoint("TOPLEFT", X, -184); d2:SetPoint("TOPRIGHT", -X, -184)

  -- OVERLAYS block.
  local oh = newText(rail, FONT.head, 12, MUTE, "LEFT")
  oh:SetPoint("TOPLEFT", X, -194); oh:SetText("OVERLAYS")
  countText = newText(rail, FONT.body, 10.5, MUTE, "RIGHT")
  countText:SetPoint("TOPRIGHT", -X, -194)

  local newBtn = flatButton(rail, W, 22, COLOR.purple, "+ New Overlay", 11)
  newBtn:SetBase(0.35)
  newBtn:SetPoint("TOPLEFT", X, -212)
  newBtn:SetScript("OnClick", function()
    local profile = GloomsOverlays_GetProfile()
    local overlays = profile.overlays
    local newIndex = #overlays + 1
    overlays[newIndex] = {
      name      = "New Overlay " .. newIndex,
      texture   = "",
      x = 0, y = 0, width = 200, height = 200,
      rotation  = 0,
      alpha     = 1.0,
      blendMode = "BLEND",
      strata    = "HIGH",
      flipH     = false,
      flipV     = false,
      spinSpeed = 0,
      spinDir   = "cw",
      tintR     = 1, tintG = 1, tintB = 1,
      enabled   = true,
      condition = "always",
    }
    GloomsOverlays_ApplyAll()
    RefreshList()
    SelectOverlay(newIndex)
  end)
  attachTip(newBtn, "New overlay", "Creates a blank overlay in this profile and opens it for editing.")

  -- Scrolling overlay list.
  listScroll = CreateFrame("ScrollFrame", nil, rail)
  listScroll:SetPoint("TOPLEFT", X, -242)
  listScroll:SetSize(W - 8, LIST_ROWS * LIST_ROW_H)
  listScroll:EnableMouseWheel(true)
  listScroll:SetScript("OnMouseWheel", function(self, delta)
    local range = self:GetVerticalScrollRange()
    self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * LIST_ROW_H)))
  end)
  listContent = CreateFrame("Frame", nil, listScroll)
  listContent:SetSize(W - 8, 1)
  listScroll:SetScrollChild(listContent)
  -- Anchor the TOP only and give it an explicit height: a BOTTOMRIGHT point is
  -- measured from the RAIL's bottom, which ran the track off the end of the tab.
  makeScrollbar(rail, listScroll, function(b)
    b:SetPoint("TOPRIGHT", -X, -242)
    b:SetHeight(LIST_ROWS * LIST_ROW_H)
  end)

  -- Duplicate / Delete act on the SELECTED overlay (the old per-row buttons
  -- don't fit a 240 rail, and Edit is just clicking the row now).
  local bw = (W - 4) / 2
  E.dupeBtn = flatButton(rail, bw, 22, COLOR.heroic, "Duplicate", 11)
  E.dupeBtn:SetBase(0.2); E.dupeBtn:SetPoint("BOTTOMLEFT", X, 6)
  E.delBtn = flatButton(rail, bw, 22, COLOR.heroic, "Delete", 11)
  E.delBtn:SetBase(0.2); E.delBtn:SetPoint("BOTTOMLEFT", X + bw + 4, 6)

  E.dupeBtn:SetScript("OnClick", function()
    local profile = GloomsOverlays_GetProfile()
    local overlays = profile and profile.overlays
    local src = overlays and currentEditIndex and overlays[currentEditIndex]
    if not src then return end
    local copy = {}
    for k, v in pairs(src) do
      if type(v) == "table" then
        local t2 = {}
        for k2, v2 in pairs(v) do t2[k2] = v2 end
        copy[k] = t2
      else
        copy[k] = v
      end
    end
    copy.name = (src.name or "Overlay") .. " copy"
    table.insert(overlays, currentEditIndex + 1, copy)
    GloomsOverlays_ApplyAll()
    RefreshList()
    SelectOverlay(currentEditIndex + 1)
  end)

  E.delBtn:SetScript("OnClick", function()
    local profile = GloomsOverlays_GetProfile()
    local overlays = profile and profile.overlays
    local ov = overlays and currentEditIndex and overlays[currentEditIndex]
    if not ov then return end
    local idx = currentEditIndex
    UI.confirm(("Delete the overlay \"%s\"?  This can't be undone."):format(ov.name or "?"), function()
      table.remove(overlays, idx)
      GloomsOverlays_ApplyAll()
      SelectOverlay(nil)
      RefreshList()
    end)
  end)

  attachTip(E.dupeBtn, "Duplicate", "Copies the selected overlay, settings and all.")
  attachTip(E.delBtn, "Delete", "Deletes the selected overlay. Asks you to confirm first.")
end

local function GetOrCreateRow(index)
  local row = rowPool[index]
  if row then return row end

  row = CreateFrame("Button", nil, listContent)
  row:SetSize(RAIL_W - 36, LIST_ROW_H)

  row.sel = row:CreateTexture(nil, "BACKGROUND"); row.sel:SetAllPoints()
  row.sel:SetColorTexture(COLOR.purple.r, COLOR.purple.g, COLOR.purple.b, 0.28); row.sel:Hide()
  local hl = row:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.07)

  -- The switch is its own Button, so clicking it toggles WITHOUT selecting.
  row.toggle = makeToggle(row,
    function()
      local profile = GloomsOverlays_GetProfile()
      local ov = profile and profile.overlays and profile.overlays[row.index]
      return ov and ov.enabled ~= false
    end,
    function(v)
      local profile = GloomsOverlays_GetProfile()
      local ov = profile and profile.overlays and profile.overlays[row.index]
      if not ov then return end
      ov.enabled = v and true or false
      GloomsOverlays_ApplyAll()
    end)
  row.toggle:SetPoint("LEFT", 2, 0)

  row.text = newText(row, FONT.body, 12, TEXT, "LEFT")
  row.text:SetPoint("LEFT", row.toggle, "RIGHT", 8, 0)
  row.text:SetPoint("RIGHT", -4, 0)
  row.text:SetWordWrap(false)

  row:SetScript("OnClick", function(self)
    if self.index then SelectOverlay(self.index) end
  end)

  rowPool[index] = row
  return row
end

RefreshList = function()
  if not listContent then return end
  local profile = GloomsOverlays_GetProfile and GloomsOverlays_GetProfile()
  local overlays = (profile and profile.overlays) or {}

  local y = 0
  for i, ov in ipairs(overlays) do
    local row = GetOrCreateRow(i)
    row.index = i
    row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -y)
    row.text:SetText(ov.name or ("Overlay " .. i))
    row.toggle:refresh()
    row.sel:SetShown(i == currentEditIndex)
    row:Show()
    y = y + LIST_ROW_H
  end
  for i = #overlays + 1, #rowPool do
    rowPool[i].index = nil
    rowPool[i]:Hide()
  end
  listContent:SetHeight(math.max(1, y))

  if countText then countText:SetText(#overlays .. (#overlays == 1 and " overlay" or " overlays")) end
  if profileBlock then profileBlock:refresh() end

  local has = currentEditIndex ~= nil
  if E.dupeBtn then E.dupeBtn:SetEnabled(has) end
  if E.delBtn then E.delBtn:SetEnabled(has) end
end

-- --------------------------------------------------------------------------
-- RIGHT PANE — the selected overlay's settings
-- --------------------------------------------------------------------------
local function BuildEditor(p)
  -- ── Name ──────────────────────────────────────────────────
  label(p, "Name", PAD, -14)
  -- Nominal width; the TOPRIGHT anchor below is what actually sizes these two.
  E.nameBox = box(p, 300, 24, PAD, -32, function(self)
    LiveApply("name", self:GetText():match("^%s*(.-)%s*$"))
    RefreshList()
  end)
  E.nameBox:SetPoint("TOPRIGHT", -PAD, -32)

  -- ── Texture ───────────────────────────────────────────────
  label(p, "Texture", PAD, -66)
  E.browseBtn = flatButton(p, 92, 24, COLOR.purple, "Browse…", 11)
  E.browseBtn:SetBase(0.35)
  E.browseBtn:SetPoint("TOPRIGHT", -PAD, -84)
  E.texBox = box(p, 300, 24, PAD, -84, function(self)
    LiveApply("texture", self:GetText():match("^%s*(.-)%s*$"))
  end)
  E.texBox:SetPoint("TOPRIGHT", E.browseBtn, "TOPLEFT", -6, 0)
  label(p, "Suite media name, atlas name, file ID, or Interface\\ path.", PAD, -112, 10.5, MUTE)
  E.browseBtn:SetScript("OnClick", function()
    if GloomsOverlays_OpenAssetBrowser then
      GloomsOverlays_OpenAssetBrowser(E.texBox:GetText())
    end
  end)
  attachTip(E.browseBtn, "Asset browser", "Opens the browser to preview textures, play spritesheets and keep favorites. Picking one drops it into this field.")

  -- ── Size & position ───────────────────────────────────────
  -- TWO COLUMNS (the owner 2026-07-25: the pane is wide, stop stacking) —
  -- SIZE on the left, POSITION on the right with the nudge arrows under it.
  -- The columns are frames rather than x offsets because UI.sliderRow always
  -- spans its PARENT (18px insets, fixed in the lib), so a half-width slider
  -- means a half-width parent. Both are anchored to the pane's TOP edge, so
  -- they split whatever width the shell hands us (CONTRACTS §2 lets it grow).
  -- They start at PAD-18 = 0 so the lib's own inset lands their labels on the
  -- same PAD gutter as every other row in this pane.
  sectionHead(p, "Size & position", -142)

  local COL_TOP, COL_GAP = -170, 8
  local sizeCol = CreateFrame("Frame", nil, p)
  sizeCol:SetPoint("TOPLEFT", PAD - 18, COL_TOP)
  sizeCol:SetPoint("TOPRIGHT", p, "TOP", -COL_GAP / 2, COL_TOP)
  sizeCol:SetHeight(130)

  local posCol = CreateFrame("Frame", nil, p)
  posCol:SetPoint("TOPLEFT", p, "TOP", COL_GAP / 2, COL_TOP)
  posCol:SetPoint("TOPRIGHT", -(PAD - 18), COL_TOP)
  posCol:SetHeight(130)

  -- Ranges cover the owner's live profiles with headroom (his widest overlay is
  -- 1500, his tallest 700, and nothing sits further than 550 from centre) and
  -- stop where a screen overlay stops being one. The typed box is the answer
  -- for precision, the arrows for the last pixel.
  local function ovNum(field, default)
    return function() local ov = CurrentOverlay(); return ov and ov[field] or default end
  end
  -- Where an overlay SITS (size, position, strata, level) is what the engine can
  -- re-apply without rebuilding every overlay frame — which matters when a drag
  -- fires this on every frame.
  local function setLayout(field)
    return function(v)
      local ov = CurrentOverlay()
      if not ov then return end
      ov[field] = v
      GloomsOverlays_ApplyLayout(ov)
    end
  end
  E.setLayout = setLayout

  E.wRow = numRow(sizeCol,  -2, "Width",  1, 2000, ovNum("width", 200),  setLayout("width"))
  E.hRow = numRow(sizeCol, -48, "Height", 1, 2000, ovNum("height", 200), setLayout("height"))
  E.xRow = numRow(posCol,   -2, "X", -1000, 1000, ovNum("x", 0), setLayout("x"))
  E.yRow = numRow(posCol,  -48, "Y", -1000, 1000, ovNum("y", 0), setLayout("y"))

  -- Nudge: an increment plus four caret arrows that move the live overlay.
  -- Kept (the owner explicitly wants them) and parked under the POSITION
  -- sliders, which are the only thing they act on.
  label(posCol, "Nudge", 18, -96)
  E.nudgeBox = flatEditBox(posCol, 40, 22)
  E.nudgeBox:SetPoint("TOPLEFT", 66, -98)
  E.nudgeBox:SetText("1"); E.nudgeBox:SetMaxLetters(5)
  E.nudgeBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  E.nudgeBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  label(posCol, "px", 112, -96, 10.5, MUTE)

  local function nudge(field, mult)
    local ov = CurrentOverlay()
    if not ov then return end
    local step = (tonumber(E.nudgeBox:GetText()) or 1) * mult
    ov[field] = (ov[field] or 0) + step
    GloomsOverlays_ApplyLayout(ov)
    local row = (field == "x") and E.xRow or E.yRow
    row:refresh()
  end
  caretButton(posCol, 26, 22, "up",    136, -98):SetScript("OnClick", function() nudge("y",  1) end)
  caretButton(posCol, 26, 22, "down",  166, -98):SetScript("OnClick", function() nudge("y", -1) end)
  caretButton(posCol, 26, 22, "left",  196, -98):SetScript("OnClick", function() nudge("x", -1) end)
  caretButton(posCol, 26, 22, "right", 226, -98):SetScript("OnClick", function() nudge("x",  1) end)

  -- ── Transform ─────────────────────────────────────────────
  sectionHead(p, "Transform", -306)
  E.rotRow = sliderRow(p, -334, "Rotation", -360, 360, 1,
    function() local ov = CurrentOverlay(); return ov and ov.rotation or 0 end,
    function(v) LiveApply("rotation", math.floor(v + 0.5)) end,
    function(v) return string.format("%d°", math.floor(v + 0.5)) end)

  -- Degree ticks under the slider (the old editor's -360/-180/0/180/360 scale).
  local ticks = CreateFrame("Frame", nil, p)
  ticks:SetPoint("TOPLEFT", PAD, -368); ticks:SetPoint("TOPRIGHT", -PAD, -368)
  ticks:SetHeight(12)
  local TICK_LABELS = { "-360°", "-180°", "0°", "180°", "360°" }
  local TICK_FRACS = { 0, 0.25, 0.5, 0.75, 1 }
  local tickText = {}
  for i = 1, #TICK_FRACS do
    tickText[i] = newText(ticks, FONT.body, 10.5, MUTE, "CENTER")
    tickText[i]:SetText(TICK_LABELS[i])
  end
  -- Placed against the row's LIVE width so they stay under the slider if the
  -- shell ever grows the content area (CONTRACTS §2 allows it to).
  ticks:SetScript("OnSizeChanged", function(self, w)
    if not w or w <= 0 then return end
    for i, frac in ipairs(TICK_FRACS) do
      tickText[i]:ClearAllPoints()
      tickText[i]:SetPoint("TOP", self, "TOPLEFT", frac * w, 0)
    end
  end)

  E.rotReset = flatButton(p, 100, 20, COLOR.heroic, "Reset rotation", 11)
  E.rotReset:SetBase(0.2); E.rotReset:SetPoint("TOPLEFT", PAD, -388)
  E.rotReset:SetScript("OnClick", function()
    LiveApply("rotation", 0)
    E.rotRow:refresh()
  end)

  E.flipH = toggleRow(p, "Flip horizontal", PAD + 130, -388,
    function() local ov = CurrentOverlay(); return ov and ov.flipH or false end,
    function(v) LiveApply("flipH", v and true or false) end)
  E.flipV = toggleRow(p, "Flip vertical", PAD + 320, -388,
    function() local ov = CurrentOverlay(); return ov and ov.flipV or false end,
    function(v) LiveApply("flipV", v and true or false) end)

  -- Spin speed — a slider like the rest, with CW/CCW BESIDE it rather than
  -- underneath (the owner 2026-07-25). Same slot-frame trick as the columns
  -- above: the slider fills its parent, so the parent stops where the buttons
  -- begin, and the buttons hang off the slot's right edge so the pair still
  -- lines up if the shell ever widens the pane.
  local SPIN_Y, DIR_W = -430, 56 * 2 + 6
  local spinSlot = CreateFrame("Frame", nil, p)
  spinSlot:SetPoint("TOPLEFT", PAD - 18, SPIN_Y)
  spinSlot:SetPoint("TOPRIGHT", -(DIR_W + 14), SPIN_Y)
  spinSlot:SetHeight(60)
  E.spinRow = numRow(spinSlot, 0, "Spin speed", 0, 360,
    function() local ov = CurrentOverlay(); return ov and ov.spinSpeed or 0 end,
    function(v) LiveApply("spinSpeed", v) end,
    "°/sec — 0 turns spinning off")

  local dirSlot = CreateFrame("Frame", nil, p)
  dirSlot:SetPoint("TOPLEFT", spinSlot, "TOPRIGHT", -4, 0)   -- -4: 14px gap less the slot's own 18px inset
  dirSlot:SetSize(DIR_W, 60)
  -- -27 centres the buttons on the slider, which the sub-label pushes to -30.
  E.spinDir = choiceRow(dirSlot, { { "cw", "CW" }, { "ccw", "CCW" } }, 56, 22, 0, -27, 6,
    function(v) LiveApply("spinDir", v) end)

  -- ── Appearance ────────────────────────────────────────────
  sectionHead(p, "Appearance", -504)
  E.alphaRow = sliderRow(p, -532, "Alpha", 0, 100, 1,
    function() local ov = CurrentOverlay(); return math.floor((ov and ov.alpha or 1) * 100 + 0.5) end,
    function(v) LiveApply("alpha", math.floor(v + 0.5) / 100) end,
    function(v) return string.format("%d%%", math.floor(v + 0.5)) end)

  label(p, "Tint", PAD, -576)
  E.tint = colorSwatch(p,
    function()
      local ov = CurrentOverlay()
      return { ov and ov.tintR or 1, ov and ov.tintG or 1, ov and ov.tintB or 1 }
    end,
    -- No label: this swatch reads the SELECTED overlay, so it could only ever
    -- report one. OverlayColorSources below walks every overlay by name.
    function(c) LiveApplyMulti({ tintR = c[1], tintG = c[2], tintB = c[3] }) end)
  E.tint.swatch:SetPoint("TOPLEFT", PAD + 62, -576)

  E.tintReset = flatButton(p, 60, 20, COLOR.heroic, "Reset", 11)
  E.tintReset:SetBase(0.2); E.tintReset:SetPoint("TOPLEFT", PAD + 100, -576)
  E.tintReset:SetScript("OnClick", function()
    LiveApplyMulti({ tintR = 1, tintG = 1, tintB = 1 })
    E.tint:refresh()
  end)

  -- Class coloring overrides the manual tint; the two are mutually exclusive
  -- and lock the swatch while on (as the old editor did).
  local function SetClassColor(which, on)
    local ov = CurrentOverlay()
    if not ov then return end
    if on then
      local unit = (which == "target") and "target" or "player"
      local _, classTag = UnitClass(unit)
      local cc = classTag and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classTag]
      LiveApplyMulti({
        useClassColor  = (which == "player") or nil,
        useTargetColor = (which == "target") or nil,
        tintR = cc and cc.r or 1, tintG = cc and cc.g or 1, tintB = cc and cc.b or 1,
      })
    else
      LiveApply(which == "target" and "useTargetColor" or "useClassColor", false)
    end
    E.syncTint()
  end

  E.classPlayer = toggleRow(p, "Player class color", PAD, -608,
    function() local ov = CurrentOverlay(); return ov and ov.useClassColor == true end,
    function(v) if v then SetClassColor("target", false) end; SetClassColor("player", v) end)
  E.classTarget = toggleRow(p, "Target class color", PAD + 280, -608,
    function() local ov = CurrentOverlay(); return ov and ov.useTargetColor == true end,
    function(v) if v then SetClassColor("player", false) end; SetClassColor("target", v) end)

  function E.syncTint()
    local ov = CurrentOverlay()
    local locked = ov and (ov.useClassColor == true or ov.useTargetColor == true)
    E.tint:refresh()
    E.tint.swatch:SetEnabled(not locked)
    E.tint.swatch:SetAlpha(locked and 0.35 or 1)
    E.tintReset:SetEnabled(not locked)
    E.classPlayer:refresh()
    E.classTarget:refresh()
  end

  label(p, "Blend mode", PAD, -644)
  E.blend = choiceRow(p, { { "BLEND" }, { "ADD" }, { "MOD" } }, 62, 20, PAD + 200, -644, 6,
    function(v) LiveApply("blendMode", v) end)

  -- ── Layer ─────────────────────────────────────────────────
  sectionHead(p, "Layer (z-order)", -680)
  label(p, "WORLD sits under everything · HIGH above most of the UI · TOOLTIP above all of it.",
    PAD, -708, 10.5, MUTE)

  -- All NINE of WoW's stratas. The list is Blizzard's and cannot be extended;
  -- WORLD and FULLSCREEN_DIALOG were missing here, and FULLSCREEN_DIALOG in
  -- particular is one of the most used in the wild (the client's other addons
  -- reference it 5× more often than FULLSCREEN).
  local STRATA = {
    { "WORLD" }, { "BACKGROUND" }, { "LOW" }, { "MEDIUM" }, { "HIGH" },
    { "DIALOG" }, { "FULLSCREEN" }, { "FULLSCREEN_DIALOG", "FS DIALOG" }, { "TOOLTIP" },
  }
  local PER_ROW, SB_W = 5, 88
  local strataBtns = {}
  for i, s in ipairs(STRATA) do
    local value, text = s[1], s[2] or s[1]
    local col, rowN = (i - 1) % PER_ROW, math.floor((i - 1) / PER_ROW)
    local b = flatButton(p, SB_W, 20, COLOR.heroic, text, 11)
    b:SetBase(0.2)
    b:SetPoint("TOPLEFT", PAD + col * (SB_W + 4), -730 - rowN * 24)
    b:SetScript("OnClick", function()
      E.setLayout("strata")(value)
      for _, e in ipairs(strataBtns) do e.b:SetActive(e.v == value) end
    end)
    strataBtns[#strataBtns + 1] = { b = b, v = value }
  end
  attachTip(strataBtns[8].b, "FULLSCREEN_DIALOG",
    "Blizzard's strata between FULLSCREEN and TOOLTIP. Abbreviated here to fit the button.")
  E.strata = { sync = function(value)
    for _, e in ipairs(strataBtns) do e.b:SetActive(e.v == value) end
  end }

  -- Level — the numeric z-index INSIDE a strata (the owner 2026-07-25: seven
  -- stratas is limiting once overlays have to interleave with Blizzard's UI).
  -- Every overlay used to draw at the same level, so strata was the only
  -- separation there was; this is the fine control under that coarse one.
  -- 0–1000 covers everything in practice: Blizzard's own frames sit in the tens.
  E.levelRow = numRow(p, -798, "Level", 0, 1000,
    function()
      local ov = CurrentOverlay()
      return (ov and ov.level) or GloomsOverlays_GetDefaultLevel()
    end,
    E.setLayout("level"),
    -- Kept short on purpose: a sliderRow sub-label is a single unwrapped line,
    -- so anything much past ~80 characters runs off the pane and gets clipped.
    "Higher draws in front, within the same strata · default "
      .. GloomsOverlays_GetDefaultLevel())
  label(p, "Strata always wins: a MEDIUM overlay at level 999 still sits under any HIGH frame.",
    PAD, -850, 10.5, MUTE)
  label(p, "Point at a Blizzard frame with /fstack to read the strata and level it uses.",
    PAD, -864, 10.5, MUTE)

  -- ── Visibility ────────────────────────────────────────────
  sectionHead(p, "Visibility", -892)
  label(p, "The overlay shows while ANY switched-on condition is true.", PAD, -920, 10.5, MUTE)

  local COND = {
    { "always",   "Always visible" },
    { "combat",   "In combat" },
    { "nocombat", "Out of combat" },
    { "target",   "Target selected" },
    { "casting",  "While casting" },
  }
  local function conditionSet()
    local ov = CurrentOverlay()
    local set = {}
    for word in ((ov and ov.condition) or "always"):gmatch("[^,]+") do set[word] = true end
    return set
  end
  E.cond = {}
  for i, c in ipairs(COND) do
    local key = c[1]
    local col, rowN = (i - 1) % 2, math.floor((i - 1) / 2)
    E.cond[i] = toggleRow(p, c[2], PAD + col * 280, -944 - rowN * 30,
      function() return conditionSet()[key] == true end,
      function(v)
        local set = conditionSet()
        set[key] = v or nil
        local parts = {}
        for _, cc in ipairs(COND) do
          if set[cc[1]] then parts[#parts + 1] = cc[1] end
        end
        LiveApply("condition", #parts > 0 and table.concat(parts, ",") or "always")
        for _, t in ipairs(E.cond) do t:refresh() end
      end)
  end
end

-- Populate every control from the overlay at `index` (nil clears the pane).
SelectOverlay = function(index)
  local profile = GloomsOverlays_GetProfile and GloomsOverlays_GetProfile()
  local ov = index and profile and profile.overlays and profile.overlays[index]
  currentEditIndex = ov and index or nil

  if not ov then
    if editorBody then editorBody:Hide() end
    if E.editorBar then E.editorBar:Hide() end
    if emptyNote then emptyNote:Show() end
    RefreshList()
    SetStatus("")
    return
  end

  if emptyNote then emptyNote:Hide() end
  if editorBody then editorBody:Show() end
  if E.editorBar then E.editorBar:Show() end

  E.nameBox:SetText(ov.name or "")
  E.texBox:SetText(ov.texture or "")

  -- Each numRow drives its own slider AND its typed box from the overlay.
  E.wRow:refresh()
  E.hRow:refresh()
  E.xRow:refresh()
  E.yRow:refresh()
  E.spinRow:refresh()
  E.levelRow:refresh()

  E.rotRow:refresh()
  E.alphaRow:refresh()
  E.flipH:refresh()
  E.flipV:refresh()
  E.spinDir.sync(ov.spinDir or "cw")
  E.blend.sync(ov.blendMode or "BLEND")
  E.strata.sync(ov.strata or "HIGH")
  E.syncTint()
  for _, t in ipairs(E.cond) do t:refresh() end

  if editorScroll then editorScroll:SetVerticalScroll(0) end
  RefreshList()
  SetStatus("")
end

-- --------------------------------------------------------------------------
-- The tab
-- --------------------------------------------------------------------------
local function BuildTab(c)
  container = c

  BuildRail(c)

  -- Seam between the rail and the editor pane.
  local vdiv = c:CreateTexture(nil, "ARTWORK")
  vdiv:SetColorTexture(COLOR.rim.r, COLOR.rim.g, COLOR.rim.b, COLOR.rim.a or 0.1)
  vdiv:SetWidth(1)
  vdiv:SetPoint("TOPLEFT", RAIL_W, 0); vdiv:SetPoint("BOTTOMLEFT", RAIL_W, FOOTER_H)

  -- Editor pane: a scroll frame holding the settings column.
  editorScroll = CreateFrame("ScrollFrame", nil, c)
  editorScroll:SetPoint("TOPLEFT", RAIL_W + 1, -1)
  editorScroll:SetPoint("BOTTOMRIGHT", -10, FOOTER_H + 1)
  editorScroll:EnableMouseWheel(true)
  editorScroll:SetScript("OnMouseWheel", function(self, delta)
    local range = self:GetVerticalScrollRange()
    self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 42)))
  end)
  editorChild = CreateFrame("Frame", nil, editorScroll)
  editorChild:SetSize(math.max(10, editorScroll:GetWidth()), CONTENT_H)
  editorScroll:SetScrollChild(editorChild)
  editorScroll:SetScript("OnSizeChanged", function(_, w)
    if w and w > 0 then editorChild:SetWidth(w) end
  end)
  -- Hidden along with the editor body: an empty pane has nothing to scroll.
  E.editorBar = makeScrollbar(c, editorScroll, function(b)
    b:SetPoint("TOPRIGHT", -4, -2); b:SetPoint("BOTTOMRIGHT", -4, FOOTER_H + 2)
  end)

  -- Everything the editor draws lives on `editorBody` so the whole pane can be
  -- hidden at once when nothing is selected.
  editorBody = CreateFrame("Frame", nil, editorChild)
  editorBody:SetAllPoints()
  BuildEditor(editorBody)
  editorBody:Hide()

  emptyNote = newText(c, FONT.body, 12, MUTE, "CENTER")
  emptyNote:SetPoint("CENTER", editorScroll, "CENTER", 0, 0)
  emptyNote:SetText("Select an overlay on the left to edit it,\nor create one with + New Overlay.")

  -- ── The tab's own footer row (CONTRACTS §2) ───────────────
  local fdiv = hLine(c)
  fdiv:SetPoint("BOTTOMLEFT", 0, FOOTER_H); fdiv:SetPoint("BOTTOMRIGHT", 0, FOOTER_H)

  local saveBtn = flatButton(c, 130, 26, COLOR.purple, "Save & Apply", 12)
  saveBtn:SetBase(0.35)
  saveBtn:SetPoint("BOTTOMLEFT", RAIL_W + PAD, 9)
  saveBtn:SetScript("OnClick", function()
    local ov = CurrentOverlay()
    if not ov then return end
    ov.name    = E.nameBox:GetText():match("^%s*(.-)%s*$")
    ov.texture = E.texBox:GetText():match("^%s*(.-)%s*$")
    ov.width   = tonumber(E.wRow.box:GetText()) or 200
    ov.height  = tonumber(E.hRow.box:GetText()) or 200
    ov.x       = tonumber(E.xRow.box:GetText()) or 0
    ov.y       = tonumber(E.yRow.box:GetText()) or 0
    GloomsOverlays_ApplyAll()
    RefreshList()
    SetStatus("|cff20ba56Saved.|r")
  end)
  attachTip(saveBtn, "Save & Apply", "Commits the typed fields (name, texture, size, position). Everything else applies the moment you change it.")

  statusText = newText(c, FONT.body, 11, MUTE, "LEFT")
  statusText:SetPoint("LEFT", saveBtn, "RIGHT", 12, 0)
  statusText:SetWidth(280)

  -- OnShow/OnHide live on the CONTAINER: they fire as the tab gains/loses
  -- visibility — window open/close AND tab switches (CONTRACTS §2).
  c:HookScript("OnShow", function()
    RefreshList()
    if profileBlock then profileBlock:refresh(); profileBlock:note("") end
  end)
  c:HookScript("OnHide", function()
    GloomsOverlays_CloseDrawers()
  end)

  SelectOverlay(nil)
end

-- --------------------------------------------------------------------------
-- Cross-file entry points (the asset browser + the slash router use these)
-- --------------------------------------------------------------------------

-- Drop a texture name into the editor's Texture field and apply it live.
function GloomsOverlays_SetTextureField(text)
  if not (E.texBox and currentEditIndex) then return false end
  E.texBox:SetText(text or "")
  LiveApply("texture", (text or ""):match("^%s*(.-)%s*$"))
  return true
end

function GloomsOverlays_HasSelection()
  return currentEditIndex ~= nil
end

-- Called by the asset browser's "+ Save as New Overlay".
function GloomsOverlays_SaveFromPreview(textureInput, sheetData)
  if not VibeOverlayDB then
    error("VibeOverlayDB not initialised")
  end
  local profile = GloomsOverlays_GetProfile()
  local overlays = profile.overlays
  local newIndex = #overlays + 1
  overlays[newIndex] = {
    name      = "New Overlay " .. newIndex,
    texture   = textureInput or "",
    x = 0, y = 0, width = 200, height = 200,
    rotation  = 0,
    alpha     = 1.0,
    blendMode = "BLEND",
    strata    = "HIGH",
    flipH     = false,
    flipV     = false,
    spinSpeed = 0,
    spinDir   = "cw",
    tintR     = 1, tintG = 1, tintB = 1,
    enabled   = true,
    condition = "always",
    sheet     = sheetData,
  }
  GloomsOverlays_ApplyAll()
  GloomsHub:Open("overlays")
  RefreshList()
  SelectOverlay(newIndex)
end

-- The old "open the manager window" entry point — now a tab focus.
function GloomsOverlays_OpenManager()
  GloomsHub:ToggleWindow("overlays")
end

-- Keep a target-class-colored overlay following the current target.
local targetColorFrame = CreateFrame("Frame")
targetColorFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
targetColorFrame:SetScript("OnEvent", function()
  local profile = GloomsOverlays_GetProfile and GloomsOverlays_GetProfile()
  if not profile or not profile.overlays then return end
  local touched = false
  for _, ov in ipairs(profile.overlays) do
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
  if ov and ov.useTargetColor and E.syncTint then E.syncTint() end
end)

-- --------------------------------------------------------------------------
-- Mount the OVERLAYS tab (CONTRACTS §2; id reserved, order 30). Registration
-- is cheap and immediate; BuildTab runs ONCE, lazily, on first show. No
-- `refresh` handler — the container's OnShow hook re-syncs on every focus.
-- --------------------------------------------------------------------------
GloomsHub:RegisterTab{
  id    = "overlays",
  title = "OVERLAYS",
  order = 30,
  build = BuildTab,
}
