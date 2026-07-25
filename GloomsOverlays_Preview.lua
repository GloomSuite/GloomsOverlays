-- ============================================================
-- GloomsOverlays_Preview.lua
-- Asset browser with favorites list.
-- /go preview  (or /go p)  to open.
-- ============================================================

local PANEL_W       = 780          -- wider to fit favorites pane
local PANEL_H       = 560
local PREVIEW_SIZE  = 300
local FAV_W         = 240          -- width of the favorites pane
local SPRITE_DEFAULT = 4

-- ============================================================
-- Favorites DB helpers
-- Stored in VibeOverlayDB.favorites = { {name, cols, rows, fps,
--   uLeft, uRight, vTop, vBottom, fileID, texture}, ... }
-- ============================================================

local function GetFavs()
    if not VibeOverlayDB then return {} end
    if not VibeOverlayDB.favorites then VibeOverlayDB.favorites = {} end
    return VibeOverlayDB.favorites
end

-- ============================================================
-- Main window
-- ============================================================

local f = CreateFrame("Frame", "GloomsOverlaysPreview", UIParent, "BackdropTemplate")
f:SetSize(PANEL_W, PANEL_H)
f:SetPoint("CENTER")
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop",  f.StopMovingOrSizing)
f:SetFrameStrata("DIALOG")
f:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile=true, tileSize=32, edgeSize=32,
    insets={ left=8, right=8, top=8, bottom=8 },
})
f:SetBackdropColor(0, 0, 0, 1)
f:Hide()

-- Title / close
local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -14)
title:SetText("|cff936bffGloom's Overlays|r Preview")

local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", -4, -4)
closeBtn:SetScript("OnClick", function() f:Hide() end)

-- ============================================================
-- LEFT COLUMN: input + preview + sheet controls
-- ============================================================

local LEFT_X = 16
local LEFT_W  = PANEL_W - FAV_W - 40   -- ~504px

-- Divider line between left and right columns
local divider = f:CreateTexture(nil, "BACKGROUND")
divider:SetSize(1, PANEL_H - 40)
divider:SetPoint("TOPLEFT", LEFT_W + LEFT_X + 8, -28)
divider:SetColorTexture(0.3, 0.3, 0.3, 1)

-- Input label + box + Go button
local inputLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
inputLabel:SetPoint("TOPLEFT", LEFT_X, -44)
inputLabel:SetText("Enter atlas name, file ID, or Interface\\ path:")

local inputBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
inputBox:SetSize(LEFT_W - 50, 22)
inputBox:SetPoint("TOPLEFT", LEFT_X, -64)
inputBox:SetAutoFocus(false)
inputBox:SetMaxLetters(256)

local goBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
goBtn:SetSize(40, 22)
goBtn:SetPoint("LEFT", inputBox, "RIGHT", 4, 0)
goBtn:SetText("Go")

-- Status line
local statusLine = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
statusLine:SetPoint("TOPLEFT", LEFT_X, -92)
statusLine:SetWidth(LEFT_W)
statusLine:SetJustifyH("LEFT")
statusLine:SetText(" ")

-- Preview background square
local previewBg = CreateFrame("Frame", nil, f, "BackdropTemplate")
previewBg:SetSize(PREVIEW_SIZE, PREVIEW_SIZE)
previewBg:SetPoint("TOPLEFT", LEFT_X, -110)
previewBg:SetBackdrop({
    bgFile  = "Interface\\Buttons\\WHITE8X8",
    edgeFile= "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile=true, tileSize=8, edgeSize=16,
    insets={ left=4, right=4, top=4, bottom=4 },
})
previewBg:SetBackdropColor(0.05, 0.05, 0.05, 1)

local texPanel = CreateFrame("Frame", nil, previewBg)
texPanel:SetAllPoints()

local previewTex = texPanel:CreateTexture(nil, "ARTWORK")
previewTex:SetPoint("CENTER")
previewTex:SetSize(PREVIEW_SIZE - 16, PREVIEW_SIZE - 16)

-- Sprite sheet controls (below the preview square)
local sheetFrame = CreateFrame("Frame", nil, f)
sheetFrame:SetSize(LEFT_W, 80)
sheetFrame:SetPoint("TOPLEFT", LEFT_X, -420)

local spriteAnim = {
    running=false, elapsed=0, frame=0,
    cols=SPRITE_DEFAULT, rows=SPRITE_DEFAULT, fps=15,
    uLeft=0, uRight=1, vTop=0, vBottom=1, fileID=nil,
}

-- Row 1: cols / rows / fps / Animate / Stop
local colsLabel = sheetFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
colsLabel:SetPoint("TOPLEFT", 0, 0)
colsLabel:SetText("Cols:")

local colsBox = CreateFrame("EditBox", nil, sheetFrame, "InputBoxTemplate")
colsBox:SetSize(36, 18)
colsBox:SetPoint("LEFT", colsLabel, "RIGHT", 4, 0)
colsBox:SetAutoFocus(false)
colsBox:SetText(tostring(SPRITE_DEFAULT))
colsBox:SetMaxLetters(3)

local rowsLabel = sheetFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
rowsLabel:SetPoint("LEFT", colsBox, "RIGHT", 10, 0)
rowsLabel:SetText("Rows:")

local rowsBox = CreateFrame("EditBox", nil, sheetFrame, "InputBoxTemplate")
rowsBox:SetSize(36, 18)
rowsBox:SetPoint("LEFT", rowsLabel, "RIGHT", 4, 0)
rowsBox:SetAutoFocus(false)
rowsBox:SetText(tostring(SPRITE_DEFAULT))
rowsBox:SetMaxLetters(3)

local fpsLabel = sheetFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
fpsLabel:SetPoint("LEFT", rowsBox, "RIGHT", 10, 0)
fpsLabel:SetText("FPS:")

local fpsBox = CreateFrame("EditBox", nil, sheetFrame, "InputBoxTemplate")
fpsBox:SetSize(36, 18)
fpsBox:SetPoint("LEFT", fpsLabel, "RIGHT", 4, 0)
fpsBox:SetAutoFocus(false)
fpsBox:SetText("15")
fpsBox:SetMaxLetters(3)

local framesLabel = sheetFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
framesLabel:SetPoint("LEFT", fpsBox, "RIGHT", 10, 0)
framesLabel:SetText("Frames:")

local framesBox = CreateFrame("EditBox", nil, sheetFrame, "InputBoxTemplate")
framesBox:SetSize(36, 18)
framesBox:SetPoint("LEFT", framesLabel, "RIGHT", 4, 0)
framesBox:SetAutoFocus(false)
framesBox:SetText(tostring(SPRITE_DEFAULT * SPRITE_DEFAULT))
framesBox:SetMaxLetters(4)

local animateBtn = CreateFrame("Button", nil, sheetFrame, "UIPanelButtonTemplate")
animateBtn:SetSize(72, 20)
animateBtn:SetPoint("LEFT", framesBox, "RIGHT", 10, 0)
animateBtn:SetText("Animate")

local stopBtn = CreateFrame("Button", nil, sheetFrame, "UIPanelButtonTemplate")
stopBtn:SetSize(50, 20)
stopBtn:SetPoint("LEFT", animateBtn, "RIGHT", 4, 0)
stopBtn:SetText("Stop")
stopBtn:Disable()

-- Row 2: action buttons
local saveOverlayBtn = CreateFrame("Button", nil, sheetFrame, "UIPanelButtonTemplate")
saveOverlayBtn:SetSize(148, 20)
saveOverlayBtn:SetPoint("TOPLEFT", 0, -28)
saveOverlayBtn:SetText("+ Save as New Overlay")

local favBtn = CreateFrame("Button", nil, sheetFrame, "UIPanelButtonTemplate")
favBtn:SetSize(130, 20)
favBtn:SetPoint("LEFT", saveOverlayBtn, "RIGHT", 6, 0)
favBtn:SetText("★ Add to Favorites")

-- Hint line
local sheetHint = sheetFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
sheetHint:SetPoint("TOPLEFT", 0, -54)
sheetHint:SetWidth(LEFT_W)
sheetHint:SetJustifyH("LEFT")
sheetHint:SetTextColor(0.6, 0.6, 0.6)
sheetHint:SetText("Set cols/rows/fps and press Animate to play a spritesheet. Save cols/rows/fps with ★.")

-- ============================================================
-- Sprite animation logic
-- ============================================================

local function StopSpriteAnim()
    spriteAnim.running = false
    texPanel:SetScript("OnUpdate", nil)
    stopBtn:Disable()
    animateBtn:Enable()
    previewTex:SetTexCoord(
        spriteAnim.uLeft, spriteAnim.uRight,
        spriteAnim.vTop,  spriteAnim.vBottom)
end

local function StartSpriteAnim()
    spriteAnim.cols    = tonumber(colsBox:GetText()) or SPRITE_DEFAULT
    spriteAnim.rows    = tonumber(rowsBox:GetText()) or SPRITE_DEFAULT
    spriteAnim.fps     = tonumber(fpsBox:GetText())  or 15
    spriteAnim.elapsed = 0
    spriteAnim.frame   = 0
    spriteAnim.running = true
    -- Use explicit frame count if set, otherwise fall back to cols*rows
    local totalFrames  = tonumber(framesBox:GetText()) or (spriteAnim.cols * spriteAnim.rows)
    totalFrames = math.max(1, math.min(totalFrames, spriteAnim.cols * spriteAnim.rows))
    local frameDur     = 1 / math.max(1, spriteAnim.fps)
    local uRange = spriteAnim.uRight - spriteAnim.uLeft
    local vRange = spriteAnim.vBottom - spriteAnim.vTop
    local cw = uRange / spriteAnim.cols
    local rh = vRange / spriteAnim.rows
    animateBtn:Disable()
    stopBtn:Enable()
    texPanel:SetScript("OnUpdate", function(_, dt)
        if not spriteAnim.running then return end
        spriteAnim.elapsed = spriteAnim.elapsed + dt
        if spriteAnim.elapsed >= frameDur then
            spriteAnim.elapsed = spriteAnim.elapsed - frameDur
            spriteAnim.frame   = (spriteAnim.frame + 1) % totalFrames
            local col = spriteAnim.frame % spriteAnim.cols
            local row = math.floor(spriteAnim.frame / spriteAnim.cols)
            previewTex:SetTexCoord(
                spriteAnim.uLeft + col       * cw, spriteAnim.uLeft + (col+1) * cw,
                spriteAnim.vTop  + row       * rh, spriteAnim.vTop  + (row+1) * rh)
        end
    end)
end

animateBtn:SetScript("OnClick", StartSpriteAnim)
stopBtn:SetScript("OnClick",    StopSpriteAnim)

-- ============================================================
-- Texture load logic
-- ============================================================

local function TryLoadTexture(input)
    StopSpriteAnim()
    previewTex:SetTexCoord(0, 1, 0, 1)

    if not input or input == "" then
        statusLine:SetText("|cffff4444Please enter something first.|r")
        return
    end

    local numID = tonumber(input)
    if numID then
        previewTex:SetTexture(numID)
        previewTex:SetTexCoord(0, 1, 0, 1)
        previewTex:SetSize(PREVIEW_SIZE - 16, PREVIEW_SIZE - 16)
        spriteAnim.uLeft, spriteAnim.uRight = 0, 1
        spriteAnim.vTop,  spriteAnim.vBottom = 0, 1
        spriteAnim.fileID = numID
        colsBox:SetText(tostring(SPRITE_DEFAULT))
        rowsBox:SetText(tostring(SPRITE_DEFAULT))
        framesBox:SetText(tostring(SPRITE_DEFAULT * SPRITE_DEFAULT))
        statusLine:SetText(string.format(
            "|cff44ff44File ID %d loaded.|r", numID))
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
        previewTex:SetTexCoord(
            info.leftTexCoord, info.rightTexCoord,
            info.topTexCoord,  info.bottomTexCoord)

        local uSpan = info.rightTexCoord - info.leftTexCoord
        local vSpan = info.bottomTexCoord - info.topTexCoord
        local cols, rows = 1, 1
        if uSpan > 0 and vSpan > 0 then
            local fullW = info.width  / uSpan
            local fullH = info.height / vSpan
            cols = math.max(1, math.floor(fullW / info.width  + 0.5))
            rows = math.max(1, math.floor(fullH / info.height + 0.5))
        end
        colsBox:SetText(tostring(cols))
        rowsBox:SetText(tostring(rows))
        framesBox:SetText(tostring(cols * rows))

        local w = math.min(info.width,  PREVIEW_SIZE - 16)
        local h = math.min(info.height, PREVIEW_SIZE - 16)
        local aspect = info.width / math.max(1, info.height)
        if aspect >= 1 then
            previewTex:SetSize(w, w / aspect)
        else
            previewTex:SetSize(h * aspect, h)
        end

        local gridNote = (cols > 1 or rows > 1)
            and string.format(" |cffffcc00Spritesheet: %dx%d (%d frames)|r", cols, rows, cols*rows)
            or  " |cff888888(single frame)|r"
        statusLine:SetText(string.format(
            "|cff44ff44'%s' — %dx%d px|r%s", input, info.width, info.height, gridNote))
        return
    end

    previewTex:SetTexture(input)
    statusLine:SetText(string.format(
        "|cffff9900'%s' not found as atlas — trying as path.|r", input))
end

-- ============================================================
-- RIGHT COLUMN: Favorites
-- ============================================================

local FAV_X = LEFT_W + LEFT_X + 18

local favTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
favTitle:SetPoint("TOPLEFT", FAV_X, -44)
favTitle:SetText("|cff9966ffFavorites|r")

local favClearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
favClearBtn:SetSize(54, 18)
favClearBtn:SetPoint("TOPRIGHT", -16, -42)
favClearBtn:SetText("Clear all")

-- Scrollable favorites list
local favScroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
favScroll:SetSize(FAV_W - 20, PANEL_H - 100)
favScroll:SetPoint("TOPLEFT", FAV_X, -66)

local favContent = CreateFrame("Frame", nil, favScroll)
favContent:SetSize(FAV_W - 36, 1)
favScroll:SetScrollChild(favContent)

-- Row pool for favorites list
local favRowPool = {}
local RefreshFavorites  -- forward declaration

local function GetOrCreateFavRow(i)
    if not favRowPool[i] then
        local row = CreateFrame("Frame", nil, favContent)
        row:SetSize(FAV_W - 36, 44)

        row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.nameText:SetPoint("TOPLEFT", 0, 0)
        row.nameText:SetWidth(FAV_W - 80)
        row.nameText:SetJustifyH("LEFT")
        row.nameText:SetWordWrap(true)

        row.metaText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.metaText:SetPoint("TOPLEFT", 0, -18)
        row.metaText:SetTextColor(0.6, 0.6, 0.6)
        row.metaText:SetWidth(FAV_W - 80)

        row.loadBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.loadBtn:SetSize(34, 18)
        row.loadBtn:SetPoint("TOPRIGHT", 0, 0)
        row.loadBtn:SetText("Load")

        row.delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.delBtn:SetSize(34, 18)
        row.delBtn:SetPoint("TOPRIGHT", 0, -20)
        row.delBtn:SetText("Del")

        favRowPool[i] = row
    end
    return favRowPool[i]
end

RefreshFavorites = function()
    local favs = GetFavs()
    local yOff = 0
    for i, fav in ipairs(favs) do
        local row = GetOrCreateFavRow(i)
        row:SetPoint("TOPLEFT", 0, -yOff)
        row:Show()

        -- Shorten long atlas names for display
        local displayName = fav.name or "?"
        if #displayName > 28 then
            displayName = "..." .. displayName:sub(-25)
        end
        row.nameText:SetText(displayName)

        local totalFrames = (fav.cols or 1) * (fav.rows or 1)
        local frameNote = (fav.frames and fav.frames ~= totalFrames)
            and string.format("  |cffffcc00%d frames|r", fav.frames) or ""
        local meta = string.format("cols %d  rows %d  fps %d%s",
            fav.cols or 1, fav.rows or 1, fav.fps or 15, frameNote)
        row.metaText:SetText(meta)

        row.loadBtn:SetScript("OnClick", function()
            -- Load into preview: set input, load texture, restore sheet settings
            inputBox:SetText(fav.texture or fav.name)
            TryLoadTexture(fav.texture or fav.name)
            colsBox:SetText(tostring(fav.cols or 1))
            rowsBox:SetText(tostring(fav.rows or 1))
            fpsBox:SetText(tostring(fav.fps or 15))
            framesBox:SetText(tostring(fav.frames or ((fav.cols or 1) * (fav.rows or 1))))
            -- Restore spriteAnim UV bounds if stored
            if fav.uLeft  then spriteAnim.uLeft   = fav.uLeft  end
            if fav.uRight then spriteAnim.uRight  = fav.uRight end
            if fav.vTop   then spriteAnim.vTop    = fav.vTop   end
            if fav.vBottom then spriteAnim.vBottom = fav.vBottom end
            if fav.fileID then spriteAnim.fileID  = fav.fileID end
        end)

        row.delBtn:SetScript("OnClick", function()
            table.remove(favs, i)
            RefreshFavorites()
        end)

        yOff = yOff + 50
    end
    for i = #favs + 1, #favRowPool do
        favRowPool[i]:Hide()
    end
    favContent:SetHeight(math.max(1, yOff))
end

favClearBtn:SetScript("OnClick", function()
    if VibeOverlayDB then VibeOverlayDB.favorites = {} end
    RefreshFavorites()
end)

-- Show favorites when panel opens
f:SetScript("OnShow", function()
    RefreshFavorites()
end)

-- ============================================================
-- Add to Favorites button
-- ============================================================

favBtn:SetScript("OnClick", function()
    local input = inputBox:GetText():match("^%s*(.-)%s*$")
    if not input or input == "" then
        statusLine:SetText("|cffff4444Load a texture first.|r")
        return
    end
    if not VibeOverlayDB then
        statusLine:SetText("|cffff4444DB not ready — wait for login.|r")
        return
    end
    local favs = GetFavs()
    -- Avoid exact duplicates (same name + same grid)
    local cols   = tonumber(colsBox:GetText())   or 1
    local rows   = tonumber(rowsBox:GetText())   or 1
    local fps    = tonumber(fpsBox:GetText())    or 15
    local frames = tonumber(framesBox:GetText()) or (cols * rows)
    for _, fav in ipairs(favs) do
        if fav.name == input and fav.cols == cols and fav.rows == rows and fav.frames == frames then
            statusLine:SetText("|cffff9900Already in favorites with those settings.|r")
            return
        end
    end
    table.insert(favs, {
        name    = input,
        texture = input,
        cols    = cols,
        rows    = rows,
        fps     = fps,
        frames  = frames,
        uLeft   = spriteAnim.uLeft,
        uRight  = spriteAnim.uRight,
        vTop    = spriteAnim.vTop,
        vBottom = spriteAnim.vBottom,
        fileID  = spriteAnim.fileID,
    })
    RefreshFavorites()
    statusLine:SetText("|cff44ff44Added to favorites.|r")
end)

-- ============================================================
-- Save as New Overlay button
-- ============================================================

saveOverlayBtn:SetScript("OnClick", function()
    local input = inputBox:GetText():match("^%s*(.-)%s*$")
    if not input or input == "" then
        statusLine:SetText("|cffff4444Load a texture first, then save.|r")
        return
    end
    if not GloomsOverlays_SaveFromPreview then
        statusLine:SetText("|cffff4444Editor not loaded yet — try again after login.|r")
        return
    end
    local cols = tonumber(colsBox:GetText()) or 1
    local rows = tonumber(rowsBox:GetText()) or 1
    local sheetData = nil
    if cols > 1 or rows > 1 then
        local frames = tonumber(framesBox:GetText()) or (cols * rows)
        sheetData = {
            cols    = cols,
            rows    = rows,
            fps     = tonumber(fpsBox:GetText()) or 15,
            frames  = frames,
            uLeft   = spriteAnim.uLeft   or 0,
            uRight  = spriteAnim.uRight  or 1,
            vTop    = spriteAnim.vTop    or 0,
            vBottom = spriteAnim.vBottom or 1,
            fileID  = spriteAnim.fileID,
        }
    end
    local ok, err = pcall(GloomsOverlays_SaveFromPreview, input, sheetData)
    if ok then
        statusLine:SetText("|cff44ff44Saved! Edit position and settings in the Overlays panel.|r")
    else
        statusLine:SetText("|cffff4444Save failed: " .. tostring(err) .. "|r")
    end
end)

-- ============================================================
-- Go button / Enter key
-- ============================================================

local function OnGo()
    TryLoadTexture(inputBox:GetText():match("^%s*(.-)%s*$"))
end

goBtn:SetScript("OnClick", OnGo)
inputBox:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    OnGo()
end)

-- ============================================================
-- Slash command hook
-- ============================================================

local extendFrame = CreateFrame("Frame")
extendFrame:RegisterEvent("PLAYER_LOGIN")
extendFrame:SetScript("OnEvent", function(self)
    local original = SlashCmdList["GLOOMSOVERLAYS"]
    SlashCmdList["GLOOMSOVERLAYS"] = function(msg)
        local cmd = msg and msg:lower():match("^%s*(.-)%s*$") or ""
        if cmd == "preview" or cmd == "p" then
            if f:IsShown() then f:Hide()
            else f:Show(); f:Raise() end
        elseif cmd == "overlays" or cmd == "o" then
            if GloomsOverlays_OpenManager then GloomsOverlays_OpenManager() end
        else
            original(msg)
        end
    end
    print("|cff936bffGloom's Overlays|r asset browser ready. "..
          "Type |cffcccccc/go preview|r (or |cffcccccc/go p|r) to open the asset browser.")
    self:UnregisterAllEvents()
end)

-- Esc closes the preview panel
tinsert(UISpecialFrames, "GloomsOverlaysPreview")
