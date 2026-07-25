-- ============================================================
-- GloomsOverlays_Preview.lua
-- The asset browser: preview a texture, play it as a spritesheet, keep
-- favorites, and drop the result into the editor.
--
-- Phase E gate B: the old 780x560 floating window is GONE. This is now a
-- DRAWER docked flush against the Suite window's edge (flipping to the other
-- side if it would run off-screen), parented to the Overlays tab container so
-- it hides with the tab AND the window. Opened from the editor's Texture field
-- ("Browse…") or with /go preview.
-- Favorites still live in VibeOverlayDB.favorites — the SavedVariables globals
-- are deliberately unchanged (see the TOC's warning).
-- ============================================================

local Skin = LibStub("LibGloomSkin-1.0")
local UI = Skin.UI
local COLOR, FONT = Skin.COLOR, Skin.FONT
local TEXT, MUTE = COLOR.text, COLOR.mute

local newText, flatButton, flatEditBox = UI.newText, UI.flatButton, UI.flatEditBox
local makeScrollbar, attachTip, hLine = UI.makeScrollbar, UI.attachTip, UI.hLine

local DRAWER_W   = 360
local DRAWER_H   = 626      -- matches the shell's pinned content height (CONTRACTS §2)
local PREVIEW_SZ = 220
local FAV_ROWS   = 4
local FAV_ROW_H  = 36
local SPRITE_DEFAULT = 4

local drawer, inputBox, statusLine, previewTex, texPanel
local colsBox, rowsBox, fpsBox, framesBox, animateBtn, stopBtn
local favScroll, favContent
local favRowPool = {}
local RefreshFavorites, TryLoadTexture

local spriteAnim = {
  running = false, elapsed = 0, frame = 0,
  cols = SPRITE_DEFAULT, rows = SPRITE_DEFAULT, fps = 15,
  uLeft = 0, uRight = 1, vTop = 0, vBottom = 1, fileID = nil,
}

local function GetFavs()
  if not VibeOverlayDB then return {} end
  if not VibeOverlayDB.favorites then VibeOverlayDB.favorites = {} end
  return VibeOverlayDB.favorites
end

local function status(text) if statusLine then statusLine:SetText(text or "") end end

-- ------------------------------------------------------------
-- Spritesheet animation
-- ------------------------------------------------------------

local function StopSpriteAnim()
  spriteAnim.running = false
  if texPanel then texPanel:SetScript("OnUpdate", nil) end
  if stopBtn then stopBtn:SetEnabled(false) end
  if animateBtn then animateBtn:SetEnabled(true) end
  if previewTex then
    previewTex:SetTexCoord(spriteAnim.uLeft, spriteAnim.uRight, spriteAnim.vTop, spriteAnim.vBottom)
  end
end

local function StartSpriteAnim()
  spriteAnim.cols    = tonumber(colsBox:GetText()) or SPRITE_DEFAULT
  spriteAnim.rows    = tonumber(rowsBox:GetText()) or SPRITE_DEFAULT
  spriteAnim.fps     = tonumber(fpsBox:GetText()) or 15
  spriteAnim.elapsed = 0
  spriteAnim.frame   = 0
  spriteAnim.running = true

  local total = tonumber(framesBox:GetText()) or (spriteAnim.cols * spriteAnim.rows)
  total = math.max(1, math.min(total, spriteAnim.cols * spriteAnim.rows))
  local frameDur = 1 / math.max(1, spriteAnim.fps)
  local cw = (spriteAnim.uRight - spriteAnim.uLeft) / spriteAnim.cols
  local rh = (spriteAnim.vBottom - spriteAnim.vTop) / spriteAnim.rows

  animateBtn:SetEnabled(false)
  stopBtn:SetEnabled(true)
  texPanel:SetScript("OnUpdate", function(_, dt)
    if not spriteAnim.running then return end
    spriteAnim.elapsed = spriteAnim.elapsed + dt
    if spriteAnim.elapsed >= frameDur then
      spriteAnim.elapsed = spriteAnim.elapsed - frameDur
      spriteAnim.frame = (spriteAnim.frame + 1) % total
      local col = spriteAnim.frame % spriteAnim.cols
      local rowN = math.floor(spriteAnim.frame / spriteAnim.cols)
      previewTex:SetTexCoord(
        spriteAnim.uLeft + col * cw, spriteAnim.uLeft + (col + 1) * cw,
        spriteAnim.vTop + rowN * rh, spriteAnim.vTop + (rowN + 1) * rh)
    end
  end)
end

-- ------------------------------------------------------------
-- Texture loading (unchanged logic; family-colored messages)
-- ------------------------------------------------------------

TryLoadTexture = function(input)
  StopSpriteAnim()
  previewTex:SetTexCoord(0, 1, 0, 1)

  if not input or input == "" then
    status("|cffc41e3aEnter a texture first.|r")
    return
  end

  -- A Suite media name resolves through the Hub (Phase E gate A moved this off
  -- StoneTweaks) — the same lookup the live overlay does.
  local mediaPath = GloomsHub and GloomsHub.ResolveAssetPath and GloomsHub:ResolveAssetPath(input)
  if mediaPath then
    previewTex:SetTexture(mediaPath)
    previewTex:SetTexCoord(0, 1, 0, 1)
    previewTex:SetSize(PREVIEW_SZ - 16, PREVIEW_SZ - 16)
    spriteAnim.uLeft, spriteAnim.uRight = 0, 1
    spriteAnim.vTop, spriteAnim.vBottom = 0, 1
    spriteAnim.fileID = nil
    status(("|cff20ba56Suite media '%s' loaded.|r"):format(input))
    return
  end

  local numID = tonumber(input)
  if numID then
    previewTex:SetTexture(numID)
    previewTex:SetTexCoord(0, 1, 0, 1)
    previewTex:SetSize(PREVIEW_SZ - 16, PREVIEW_SZ - 16)
    spriteAnim.uLeft, spriteAnim.uRight = 0, 1
    spriteAnim.vTop, spriteAnim.vBottom = 0, 1
    spriteAnim.fileID = numID
    colsBox:SetText(tostring(SPRITE_DEFAULT))
    rowsBox:SetText(tostring(SPRITE_DEFAULT))
    framesBox:SetText(tostring(SPRITE_DEFAULT * SPRITE_DEFAULT))
    status(("|cff20ba56File ID %d loaded.|r"):format(numID))
    return
  end

  local info = C_Texture.GetAtlasInfo(input)
  if info then
    previewTex:SetTexture(info.file)
    spriteAnim.uLeft   = info.leftTexCoord
    spriteAnim.uRight  = info.rightTexCoord
    spriteAnim.vTop    = info.topTexCoord
    spriteAnim.vBottom = info.bottomTexCoord
    spriteAnim.fileID  = info.file
    previewTex:SetTexCoord(info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord)

    local uSpan = info.rightTexCoord - info.leftTexCoord
    local vSpan = info.bottomTexCoord - info.topTexCoord
    local cols, rowsN = 1, 1
    if uSpan > 0 and vSpan > 0 then
      cols  = math.max(1, math.floor((info.width / uSpan) / info.width + 0.5))
      rowsN = math.max(1, math.floor((info.height / vSpan) / info.height + 0.5))
    end
    colsBox:SetText(tostring(cols))
    rowsBox:SetText(tostring(rowsN))
    framesBox:SetText(tostring(cols * rowsN))

    local w = math.min(info.width, PREVIEW_SZ - 16)
    local h = math.min(info.height, PREVIEW_SZ - 16)
    local aspect = info.width / math.max(1, info.height)
    if aspect >= 1 then previewTex:SetSize(w, w / aspect)
    else previewTex:SetSize(h * aspect, h) end

    local grid = (cols > 1 or rowsN > 1)
      and ("  |cffff7729Spritesheet %dx%d (%d frames)|r"):format(cols, rowsN, cols * rowsN)
      or "  |cff8f929bsingle frame|r"
    status(("|cff20ba56'%s' — %dx%d px|r%s"):format(input, info.width, info.height, grid))
    return
  end

  previewTex:SetTexture(input)
  status(("|cffff7729'%s' is not an atlas — trying it as a path.|r"):format(input))
end

-- ------------------------------------------------------------
-- Favorites list
-- ------------------------------------------------------------

local function GetOrCreateFavRow(i)
  local row = favRowPool[i]
  if row then return row end

  row = CreateFrame("Frame", nil, favContent)
  row:SetSize(DRAWER_W - 36, FAV_ROW_H)

  -- Zebra striping: each row carries a name, a meta line AND its own Load/Del
  -- pair, so without banding it's guesswork which buttons belong to which entry
  -- (the owner, gate B QA).
  if i % 2 == 0 then
    local band = row:CreateTexture(nil, "BACKGROUND")
    band:SetAllPoints(); band:SetColorTexture(1, 1, 1, 0.045)
  end

  -- Anchored off the row's CENTRE (±7), not its top: a TOPLEFT anchor jammed the
  -- pair against the top edge and pooled the slack underneath (the owner, gate B QA).
  row.nameText = newText(row, FONT.body, 11, TEXT, "LEFT")
  row.nameText:SetPoint("LEFT", 0, 7)
  row.nameText:SetWidth(DRAWER_W - 124)
  row.nameText:SetWordWrap(false)

  row.metaText = newText(row, FONT.body, 10.5, MUTE, "LEFT")
  row.metaText:SetPoint("LEFT", 0, -7)
  row.metaText:SetWidth(DRAWER_W - 124)

  row.loadBtn = flatButton(row, 38, 16, COLOR.heroic, "Load", 11)
  row.loadBtn:SetBase(0.2); row.loadBtn:SetPoint("RIGHT", 0, 9)

  row.delBtn = flatButton(row, 38, 16, COLOR.heroic, "Del", 11)
  row.delBtn:SetBase(0.2); row.delBtn:SetPoint("RIGHT", 0, -9)

  favRowPool[i] = row
  return row
end

RefreshFavorites = function()
  if not favContent then return end
  local favs = GetFavs()
  local y = 0
  for i, fav in ipairs(favs) do
    local row = GetOrCreateFavRow(i)
    row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -y)
    row:Show()

    local display = fav.name or "?"
    if #display > 34 then display = "…" .. display:sub(-31) end
    row.nameText:SetText(display)

    local total = (fav.cols or 1) * (fav.rows or 1)
    local frameNote = (fav.frames and fav.frames ~= total)
      and ("  |cffff7729%d frames|r"):format(fav.frames) or ""
    row.metaText:SetText(("cols %d · rows %d · fps %d%s")
      :format(fav.cols or 1, fav.rows or 1, fav.fps or 15, frameNote))

    row.loadBtn:SetScript("OnClick", function()
      inputBox:SetText(fav.texture or fav.name)
      TryLoadTexture(fav.texture or fav.name)
      colsBox:SetText(tostring(fav.cols or 1))
      rowsBox:SetText(tostring(fav.rows or 1))
      fpsBox:SetText(tostring(fav.fps or 15))
      framesBox:SetText(tostring(fav.frames or ((fav.cols or 1) * (fav.rows or 1))))
      if fav.uLeft then spriteAnim.uLeft = fav.uLeft end
      if fav.uRight then spriteAnim.uRight = fav.uRight end
      if fav.vTop then spriteAnim.vTop = fav.vTop end
      if fav.vBottom then spriteAnim.vBottom = fav.vBottom end
      if fav.fileID then spriteAnim.fileID = fav.fileID end
    end)

    row.delBtn:SetScript("OnClick", function()
      table.remove(favs, i)
      RefreshFavorites()
    end)

    y = y + FAV_ROW_H
  end
  for i = #favs + 1, #favRowPool do favRowPool[i]:Hide() end
  favContent:SetHeight(math.max(1, y))
end

-- ------------------------------------------------------------
-- The drawer
-- ------------------------------------------------------------

local function BuildDrawer()
  local X, W = 14, DRAWER_W - 28

  local f = CreateFrame("Frame", "GloomsOverlaysAssetBrowser", UIParent)
  f:SetSize(DRAWER_W, DRAWER_H)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:EnableMouse(true)
  UI.skinPlate(f)
  UI.addEdges(f, COLOR.rim, 1)

  local title = newText(f, FONT.title, 16, COLOR.purple, "LEFT")
  title:SetPoint("TOPLEFT", X, -14); title:SetText("ASSET BROWSER")
  local close = flatButton(f, 22, 20, COLOR.heroic, "X", 12)
  close:SetPoint("TOPRIGHT", -8, -12)
  close:SetScript("OnClick", function() f:Hide() end)
  local tdiv = hLine(f); tdiv:SetPoint("TOPLEFT", X, -38); tdiv:SetPoint("TOPRIGHT", -X, -38)

  -- Input + Go
  local goBtn = flatButton(f, 44, 24, COLOR.purple, "Go", 11)
  goBtn:SetBase(0.35); goBtn:SetPoint("TOPRIGHT", -X, -50)
  inputBox = flatEditBox(f, W - 50, 24)
  inputBox:SetPoint("TOPLEFT", X, -50)
  inputBox:SetMaxLetters(256)
  local function onGo() TryLoadTexture(inputBox:GetText():match("^%s*(.-)%s*$")) end
  goBtn:SetScript("OnClick", onGo)
  inputBox:SetScript("OnEnterPressed", function(self) self:ClearFocus(); onGo() end)
  inputBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

  statusLine = newText(f, FONT.body, 10.5, MUTE, "LEFT")
  statusLine:SetPoint("TOPLEFT", X, -80); statusLine:SetWidth(W)

  -- Preview square
  local previewBg = CreateFrame("Frame", nil, f)
  previewBg:SetSize(PREVIEW_SZ, PREVIEW_SZ)
  previewBg:SetPoint("TOPLEFT", (DRAWER_W - PREVIEW_SZ) / 2, -96)
  local bg = previewBg:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.45)
  UI.addEdges(previewBg, COLOR.rim, 1)

  texPanel = CreateFrame("Frame", nil, previewBg)
  texPanel:SetAllPoints()
  previewTex = texPanel:CreateTexture(nil, "ARTWORK")
  previewTex:SetPoint("CENTER")
  previewTex:SetSize(PREVIEW_SZ - 16, PREVIEW_SZ - 16)

  -- Spritesheet controls
  local function numBox(x, y, w, initial, maxLetters)
    local e = flatEditBox(f, w, 20)
    e:SetPoint("TOPLEFT", x, y)
    e:SetText(initial); e:SetMaxLetters(maxLetters)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return e
  end
  local function tinyLabel(text, x, y)
    local fs = newText(f, FONT.body, 10.5, MUTE, "LEFT")
    fs:SetPoint("TOPLEFT", x, y); fs:SetText(text)
    return fs
  end

  local SY = -324
  tinyLabel("Cols", X, SY + 2)
  colsBox   = numBox(X + 30, SY, 34, tostring(SPRITE_DEFAULT), 3)
  tinyLabel("Rows", X + 72, SY + 2)
  rowsBox   = numBox(X + 106, SY, 34, tostring(SPRITE_DEFAULT), 3)
  tinyLabel("FPS", X + 148, SY + 2)
  fpsBox    = numBox(X + 176, SY, 34, "15", 3)
  tinyLabel("Frames", X + 218, SY + 2)
  framesBox = numBox(X + 262, SY, 42, tostring(SPRITE_DEFAULT * SPRITE_DEFAULT), 4)

  animateBtn = flatButton(f, 90, 22, COLOR.heroic, "Animate", 11)
  animateBtn:SetBase(0.2); animateBtn:SetPoint("TOPLEFT", X, -352)
  stopBtn = flatButton(f, 70, 22, COLOR.heroic, "Stop", 11)
  stopBtn:SetBase(0.2); stopBtn:SetPoint("TOPLEFT", X + 96, -352)
  stopBtn:SetEnabled(false)
  animateBtn:SetScript("OnClick", StartSpriteAnim)
  stopBtn:SetScript("OnClick", StopSpriteAnim)
  attachTip(animateBtn, "Animate", "Plays the texture as a spritesheet using the cols/rows/fps above. Save those numbers with the overlay or a favorite.")

  -- Actions
  local useBtn = flatButton(f, 162, 24, COLOR.purple, "Use This Texture", 11)
  useBtn:SetBase(0.35); useBtn:SetPoint("TOPLEFT", X, -384)
  useBtn:SetScript("OnClick", function()
    local input = inputBox:GetText():match("^%s*(.-)%s*$")
    if not input or input == "" then
      status("|cffc41e3aLoad a texture first.|r"); return
    end
    if not (GloomsOverlays_HasSelection and GloomsOverlays_HasSelection()) then
      status("|cffc41e3aSelect an overlay to edit first.|r"); return
    end
    GloomsOverlays_SetTextureField(input)
    f:Hide()
  end)
  attachTip(useBtn, "Use this texture", "Drops this texture into the overlay you're editing and closes the browser.")

  local saveBtn = flatButton(f, 162, 24, COLOR.heroic, "+ Save as New Overlay", 11)
  saveBtn:SetBase(0.2); saveBtn:SetPoint("TOPLEFT", X + 170, -384)
  saveBtn:SetScript("OnClick", function()
    local input = inputBox:GetText():match("^%s*(.-)%s*$")
    if not input or input == "" then
      status("|cffc41e3aLoad a texture first, then save.|r"); return
    end
    if not GloomsOverlays_SaveFromPreview then
      status("|cffc41e3aEditor not loaded yet — try again after login.|r"); return
    end
    local cols  = tonumber(colsBox:GetText()) or 1
    local rowsN = tonumber(rowsBox:GetText()) or 1
    local sheetData
    if cols > 1 or rowsN > 1 then
      sheetData = {
        cols    = cols,
        rows    = rowsN,
        fps     = tonumber(fpsBox:GetText()) or 15,
        frames  = tonumber(framesBox:GetText()) or (cols * rowsN),
        uLeft   = spriteAnim.uLeft or 0,
        uRight  = spriteAnim.uRight or 1,
        vTop    = spriteAnim.vTop or 0,
        vBottom = spriteAnim.vBottom or 1,
        fileID  = spriteAnim.fileID,
      }
    end
    local ok, err = pcall(GloomsOverlays_SaveFromPreview, input, sheetData)
    if ok then
      status("|cff20ba56Saved — it's selected in the list, ready to position.|r")
    else
      status("|cffc41e3aSave failed: " .. tostring(err) .. "|r")
    end
  end)

  local favAddBtn = flatButton(f, W, 22, COLOR.heroic, "Add to Favorites", 11)
  favAddBtn:SetBase(0.2); favAddBtn:SetPoint("TOPLEFT", X, -416)
  favAddBtn:SetScript("OnClick", function()
    local input = inputBox:GetText():match("^%s*(.-)%s*$")
    if not input or input == "" then
      status("|cffc41e3aLoad a texture first.|r"); return
    end
    if not VibeOverlayDB then
      status("|cffc41e3aNot ready — wait for login.|r"); return
    end
    local favs   = GetFavs()
    local cols   = tonumber(colsBox:GetText()) or 1
    local rowsN  = tonumber(rowsBox:GetText()) or 1
    local fps    = tonumber(fpsBox:GetText()) or 15
    local frames = tonumber(framesBox:GetText()) or (cols * rowsN)
    for _, fav in ipairs(favs) do
      if fav.name == input and fav.cols == cols and fav.rows == rowsN and fav.frames == frames then
        status("|cffff7729Already a favorite with those settings.|r"); return
      end
    end
    table.insert(favs, {
      name = input, texture = input,
      cols = cols, rows = rowsN, fps = fps, frames = frames,
      uLeft = spriteAnim.uLeft, uRight = spriteAnim.uRight,
      vTop = spriteAnim.vTop, vBottom = spriteAnim.vBottom,
      fileID = spriteAnim.fileID,
    })
    RefreshFavorites()
    status("|cff20ba56Added to favorites.|r")
  end)

  -- Favorites
  local favHead = newText(f, FONT.head, 12, MUTE, "LEFT")
  favHead:SetPoint("TOPLEFT", X, -452); favHead:SetText("FAVORITES")
  local clearBtn = flatButton(f, 66, 18, COLOR.heroic, "Clear all", 11)
  clearBtn:SetBase(0.2); clearBtn:SetPoint("TOPRIGHT", -X, -452)
  clearBtn:SetScript("OnClick", function()
    if not next(GetFavs()) then return end
    UI.confirm("Clear every favorite?  This can't be undone.", function()
      if VibeOverlayDB then VibeOverlayDB.favorites = {} end
      RefreshFavorites()
      status("|cff20ba56Favorites cleared.|r")
    end, "Clear")
  end)

  favScroll = CreateFrame("ScrollFrame", nil, f)
  favScroll:SetPoint("TOPLEFT", X, -476)
  favScroll:SetSize(W - 8, FAV_ROWS * FAV_ROW_H)
  favScroll:EnableMouseWheel(true)
  favScroll:SetScript("OnMouseWheel", function(self, delta)
    local range = self:GetVerticalScrollRange()
    self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * FAV_ROW_H)))
  end)
  favContent = CreateFrame("Frame", nil, favScroll)
  favContent:SetSize(W - 8, 1)
  favScroll:SetScrollChild(favContent)
  makeScrollbar(f, favScroll, function(b)
    b:SetPoint("TOPRIGHT", -X, -476)
    b:SetPoint("BOTTOMRIGHT", -X, DRAWER_H - 476 - FAV_ROWS * FAV_ROW_H)
  end)

  f:SetScript("OnShow", function() RefreshFavorites() end)
  f:SetScript("OnHide", function() StopSpriteAnim() end)
  f:Hide()

  drawer = f
  if GloomsOverlays_RegisterDrawer then GloomsOverlays_RegisterDrawer(f) end
  return f
end

-- ------------------------------------------------------------
-- Entry point — opened from the editor's Texture field or /go preview
-- ------------------------------------------------------------

function GloomsOverlays_OpenAssetBrowser(prefill)
  GloomsHub:Open("overlays")        -- the drawer parents to the tab container
  if not drawer then
    local ok, err = pcall(BuildDrawer)
    if not ok then
      print("|cff936bffGloom's Overlays|r: asset browser failed to build — " .. tostring(err))
      return
    end
  end
  if GloomsOverlays_CloseDrawers then GloomsOverlays_CloseDrawers(drawer) end
  GloomsOverlays_DockDrawer(drawer)
  drawer:Show(); drawer:Raise()
  RefreshFavorites()
  if prefill and prefill ~= "" then
    inputBox:SetText(prefill)
    TryLoadTexture(prefill)
  else
    status("Enter a Suite media name, atlas name, file ID or Interface\\ path.")
  end
end

function GloomsOverlays_ToggleAssetBrowser(prefill)
  if drawer and drawer:IsShown() then
    drawer:Hide()
  else
    GloomsOverlays_OpenAssetBrowser(prefill)
  end
end
