-- ============================================================
-- GloomsOverlays_Editor.lua
-- Overlay manager + per-overlay editor.
-- ============================================================

local MGR_W, MGR_H   = 400, 520
local EDIT_W, EDIT_H = 460, 560
local CONTENT_W      = EDIT_W - 36
local CONTENT_H      = 1080

local ManagerFrame, EditorFrame
local RefreshManagerList, RefreshProfileDropdown
local OpenEditor

-- ============================================================
-- Utility helpers
-- ============================================================

local function MakeLabel(parent, text, y, x)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", x or 0, y)
    lbl:SetText(text)
    return lbl
end

local function MakeEditBox(parent, y, x, w, h)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(w or 80, h or 20)
    box:SetPoint("TOPLEFT", x or 0, y)
    box:SetAutoFocus(false)
    box:SetMaxLetters(256)
    return box
end

local function MakeButton(parent, label, w, h)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(w or 60, h or 22)
    btn:SetText(label)
    return btn
end

local function MakeCheck(parent, label, y, x)
    local btn = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    btn:SetSize(20, 20)
    btn:SetPoint("TOPLEFT", x or 0, y)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("LEFT", btn, "RIGHT", 4, 0)
    lbl:SetText(label)
    return btn, lbl
end

local function SectionLabel(parent, text, y)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", 0, y)
    lbl:SetText("|cffcccccc" .. text .. "|r")
    return lbl
end

local function MakeSlider(parent, y, x, w, minVal, maxVal, step)
    local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    slider:SetSize(w or (CONTENT_W - 80), 14)
    slider:SetPoint("TOPLEFT", x or 20, y)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step or 1)
    slider:SetObeyStepOnDrag(true)
    for _, child in ipairs({ slider:GetRegions() }) do
        if child.GetText then child:SetText("") end
    end
    return slider
end

-- ============================================================
-- Live-apply helpers
-- ============================================================

local currentEditIndex = nil

local function LiveApply(field, value)
    if not currentEditIndex then return end
    local profile = GloomsOverlays_GetProfile and GloomsOverlays_GetProfile()
    local ov = profile and profile.overlays and profile.overlays[currentEditIndex]
    if not ov then return end
    ov[field] = value
    GloomsOverlays_ApplyAll()
end

local function LiveApplyMulti(tbl)
    if not currentEditIndex then return end
    local profile = GloomsOverlays_GetProfile and GloomsOverlays_GetProfile()
    local ov = profile and profile.overlays and profile.overlays[currentEditIndex]
    if not ov then return end
    for k, v in pairs(tbl) do ov[k] = v end
    GloomsOverlays_ApplyAll()
end

-- ============================================================
-- MANAGER WINDOW
-- ============================================================

ManagerFrame = CreateFrame("Frame", "GloomsOverlaysManager", UIParent, "BackdropTemplate")
ManagerFrame:SetSize(MGR_W, MGR_H)
ManagerFrame:SetPoint("CENTER")
ManagerFrame:SetMovable(true)
ManagerFrame:EnableMouse(true)
ManagerFrame:RegisterForDrag("LeftButton")
ManagerFrame:SetScript("OnDragStart", ManagerFrame.StartMoving)
ManagerFrame:SetScript("OnDragStop",  ManagerFrame.StopMovingOrSizing)
ManagerFrame:SetFrameStrata("DIALOG")
ManagerFrame:SetFrameLevel(10)
ManagerFrame:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile=true, tileSize=32, edgeSize=32,
    insets={ left=8, right=8, top=8, bottom=8 },
})
ManagerFrame:SetBackdropColor(0, 0, 0, 1)
ManagerFrame:Hide()

local mgrTitle = ManagerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
mgrTitle:SetPoint("TOP", 0, -14)
mgrTitle:SetText("|cff936bffGloom's Overlays|r — Overlays")

local mgrClose = CreateFrame("Button", nil, ManagerFrame, "UIPanelCloseButton")
mgrClose:SetPoint("TOPRIGHT", -4, -4)
mgrClose:SetScript("OnClick", function() ManagerFrame:Hide() end)

-- ── Profile bar ───────────────────────────────────────────────

local profileLabel = ManagerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
profileLabel:SetPoint("TOPLEFT", 16, -38)
profileLabel:SetText("Profile:")

local profileDropdown = CreateFrame("Frame", "GloomsOverlaysProfileDropdown", ManagerFrame, "UIDropDownMenuTemplate")
profileDropdown:SetPoint("TOPLEFT", 56, -28)
UIDropDownMenu_SetWidth(profileDropdown, 140)

RefreshProfileDropdown = function()
    UIDropDownMenu_Initialize(profileDropdown, function(self, level)
        local names  = GloomsOverlays_GetProfileNames()
        local active = GloomsOverlays_GetActiveProfileName()
        for _, name in ipairs(names) do
            local info    = UIDropDownMenu_CreateInfo()
            info.text     = name
            info.value    = name
            info.checked  = (name == active)
            info.func     = function()
                GloomsOverlays_SetActiveProfile(name)
                UIDropDownMenu_SetSelectedValue(profileDropdown, name)
                RefreshManagerList()
                RefreshProfileDropdown()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    local active = GloomsOverlays_GetActiveProfileName and GloomsOverlays_GetActiveProfileName() or "Default"
    UIDropDownMenu_SetSelectedValue(profileDropdown, active)
end

local profileNewBtn    = MakeButton(ManagerFrame, "New",    44, 20)
local profileCopyBtn   = MakeButton(ManagerFrame, "Copy",   44, 20)
local profileRenameBtn = MakeButton(ManagerFrame, "Rename", 54, 20)
local profileDeleteBtn = MakeButton(ManagerFrame, "Delete", 54, 20)
profileNewBtn:SetPoint("TOPLEFT",    212, -38)
profileCopyBtn:SetPoint("LEFT",   profileNewBtn,    "RIGHT", 4, 0)
profileRenameBtn:SetPoint("LEFT", profileCopyBtn,   "RIGHT", 4, 0)
profileDeleteBtn:SetPoint("LEFT", profileRenameBtn, "RIGHT", 4, 0)

profileNewBtn:SetScript("OnClick", function()
    StaticPopupDialogs["GLOOMSOVERLAYS_NEW_PROFILE"] = {
        text         = "New profile name:",
        button1      = "Create",
        button2      = "Cancel",
        hasEditBox   = true,
        maxLetters   = 64,
        OnAccept     = function(self)
            local name = self.EditBox:GetText():match("^%s*(.-)%s*$")
            if name == "" then return end
            local ok, err = GloomsOverlays_NewProfile(name)
            if ok then
                GloomsOverlays_SetActiveProfile(name)
                RefreshManagerList()
                RefreshProfileDropdown()
            else
                print("|cff936bffGloom's Overlays|r: " .. (err or "error"))
            end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
    StaticPopup_Show("GLOOMSOVERLAYS_NEW_PROFILE")
end)

profileCopyBtn:SetScript("OnClick", function()
    local srcName = GloomsOverlays_GetActiveProfileName()
    StaticPopupDialogs["GLOOMSOVERLAYS_COPY_PROFILE"] = {
        text         = "Copy '" .. srcName .. "' as:",
        button1      = "Copy",
        button2      = "Cancel",
        hasEditBox   = true,
        maxLetters   = 64,
        OnAccept     = function(self)
            local name = self.EditBox:GetText():match("^%s*(.-)%s*$")
            if name == "" then return end
            local ok, err = GloomsOverlays_NewProfile(name, srcName)
            if ok then
                GloomsOverlays_SetActiveProfile(name)
                RefreshManagerList()
                RefreshProfileDropdown()
            else
                print("|cff936bffGloom's Overlays|r: " .. (err or "error"))
            end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
    StaticPopup_Show("GLOOMSOVERLAYS_COPY_PROFILE")
end)

profileRenameBtn:SetScript("OnClick", function()
    local current = GloomsOverlays_GetActiveProfileName()
    StaticPopupDialogs["GLOOMSOVERLAYS_RENAME_PROFILE"] = {
        text         = "Rename '" .. current .. "' to:",
        button1      = "Rename",
        button2      = "Cancel",
        hasEditBox   = true,
        maxLetters   = 64,
        OnAccept     = function(self)
            local name = self.EditBox:GetText():match("^%s*(.-)%s*$")
            if name == "" then return end
            local ok, err = GloomsOverlays_RenameProfile(current, name)
            if ok then
                RefreshManagerList()
                RefreshProfileDropdown()
            else
                print("|cff936bffGloom's Overlays|r: " .. (err or "error"))
            end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
    StaticPopup_Show("GLOOMSOVERLAYS_RENAME_PROFILE")
end)

profileDeleteBtn:SetScript("OnClick", function()
    local current = GloomsOverlays_GetActiveProfileName()
    StaticPopupDialogs["GLOOMSOVERLAYS_DELETE_PROFILE"] = {
        text       = "Delete profile '" .. current .. "'? This cannot be undone.",
        button1    = "Delete",
        button2    = "Cancel",
        OnAccept   = function()
            local ok, err = GloomsOverlays_DeleteProfile(current)
            if ok then
                RefreshManagerList()
                RefreshProfileDropdown()
            else
                print("|cff936bffGloom's Overlays|r: " .. (err or "error"))
            end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
    StaticPopup_Show("GLOOMSOVERLAYS_DELETE_PROFILE")
end)

-- ── Overlay list ──────────────────────────────────────────────

local newBtn = MakeButton(ManagerFrame, "+ New Overlay", 120, 24)
newBtn:SetPoint("TOPLEFT", 16, -62)

local mgrScroll = CreateFrame("ScrollFrame", nil, ManagerFrame, "UIPanelScrollFrameTemplate")
mgrScroll:SetSize(MGR_W - 50, MGR_H - 120)
mgrScroll:SetPoint("TOPLEFT", 12, -92)

local listContent = CreateFrame("Frame", nil, mgrScroll)
listContent:SetSize(MGR_W - 50, 1)
mgrScroll:SetScrollChild(listContent)

local rowPool = {}

local function GetOrCreateRow(index)
    if not rowPool[index] then
        local row = CreateFrame("Frame", nil, listContent)
        row:SetSize(MGR_W - 60, 30)

        row.enabledBox = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.enabledBox:SetSize(20, 20)
        row.enabledBox:SetPoint("LEFT", 0, 0)

        row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.nameText:SetPoint("LEFT", row.enabledBox, "RIGHT", 6, 0)
        row.nameText:SetWidth(150)
        row.nameText:SetJustifyH("LEFT")

        row.editBtn = MakeButton(row, "Edit", 46, 22)
        row.editBtn:SetPoint("LEFT", row.nameText, "RIGHT", 6, 0)

        row.dupeBtn = MakeButton(row, "Dupe", 46, 22)
        row.dupeBtn:SetPoint("LEFT", row.editBtn, "RIGHT", 4, 0)

        row.deleteBtn = MakeButton(row, "Delete", 52, 22)
        row.deleteBtn:SetPoint("LEFT", row.dupeBtn, "RIGHT", 4, 0)

        rowPool[index] = row
    end
    return rowPool[index]
end

RefreshManagerList = function()
    local profile  = GloomsOverlays_GetProfile and GloomsOverlays_GetProfile()
    local overlays = (profile and profile.overlays) or {}
    if RefreshProfileDropdown then RefreshProfileDropdown() end
    local yOffset = 0
    for i, ov in ipairs(overlays) do
        local row = GetOrCreateRow(i)
        row:SetPoint("TOPLEFT", 0, -yOffset)
        row:Show()

        row.nameText:SetText(ov.name or ("Overlay " .. i))
        row.enabledBox:SetChecked(ov.enabled ~= false)

        row.enabledBox:SetScript("OnClick", function(self)
            overlays[i].enabled = self:GetChecked()
            GloomsOverlays_ApplyAll()
        end)

        row.editBtn:SetScript("OnClick", function()
            OpenEditor(i)
        end)

        row.dupeBtn:SetScript("OnClick", function()
            local src  = overlays[i]
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
            table.insert(overlays, i + 1, copy)
            GloomsOverlays_ApplyAll()
            RefreshManagerList()
        end)

        row.deleteBtn:SetScript("OnClick", function()
            table.remove(overlays, i)
            GloomsOverlays_ApplyAll()
            RefreshManagerList()
        end)

        yOffset = yOffset + 34
    end
    for i = #overlays + 1, #rowPool do
        rowPool[i]:Hide()
    end
    listContent:SetHeight(math.max(1, yOffset))
end

newBtn:SetScript("OnClick", function()
    local profile  = GloomsOverlays_GetProfile()
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
    RefreshManagerList()
    OpenEditor(newIndex)
end)

-- ============================================================
-- EDITOR WINDOW
-- ============================================================

EditorFrame = CreateFrame("Frame", "GloomsOverlaysEditor", UIParent, "BackdropTemplate")
EditorFrame:SetSize(EDIT_W, EDIT_H)
EditorFrame:SetPoint("CENTER", 20, 0)
EditorFrame:SetMovable(true)
EditorFrame:SetResizable(true)
EditorFrame:SetResizeBounds(EDIT_W, 300, EDIT_W, 900)
EditorFrame:EnableMouse(true)
EditorFrame:RegisterForDrag("LeftButton")
EditorFrame:SetScript("OnDragStart", EditorFrame.StartMoving)
EditorFrame:SetScript("OnDragStop",  EditorFrame.StopMovingOrSizing)
EditorFrame:SetFrameStrata("DIALOG")
EditorFrame:SetFrameLevel(20)
EditorFrame:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile=true, tileSize=32, edgeSize=32,
    insets={ left=8, right=8, top=8, bottom=8 },
})
EditorFrame:SetBackdropColor(0, 0, 0, 1)
EditorFrame:Hide()

local edTitle = EditorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
edTitle:SetPoint("TOP", 0, -14)
edTitle:SetText("|cff936bffGloom's Overlays|r — Edit Overlay")

local edClose = CreateFrame("Button", nil, EditorFrame, "UIPanelCloseButton")
edClose:SetPoint("TOPRIGHT", -4, -4)
edClose:SetScript("OnClick", function() EditorFrame:Hide() end)

local saveBtn   = MakeButton(EditorFrame, "Save & Apply", 110, 26)
local cancelBtn = MakeButton(EditorFrame, "Cancel",        80, 26)
saveBtn:SetPoint("BOTTOMLEFT", 16, 12)
cancelBtn:SetPoint("LEFT", saveBtn, "RIGHT", 8, 0)
cancelBtn:SetScript("OnClick", function() EditorFrame:Hide() end)

local edStatus = EditorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
edStatus:SetPoint("LEFT", cancelBtn, "RIGHT", 12, 0)
edStatus:SetWidth(200)
edStatus:SetJustifyH("LEFT")
edStatus:SetText(" ")

local grip = CreateFrame("Button", nil, EditorFrame)
grip:SetSize(16, 16)
grip:SetPoint("BOTTOMRIGHT", -4, 4)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
grip:SetScript("OnMouseDown", function() EditorFrame:StartSizing("BOTTOMRIGHT") end)
grip:SetScript("OnMouseUp",   function() EditorFrame:StopMovingOrSizing() end)

local edScroll = CreateFrame("ScrollFrame", nil, EditorFrame, "UIPanelScrollFrameTemplate")
edScroll:SetPoint("TOPLEFT",     14,  -38)
edScroll:SetPoint("BOTTOMRIGHT", -30,  46)

local C = CreateFrame("Frame", nil, edScroll)
C:SetSize(CONTENT_W, CONTENT_H)
edScroll:SetScrollChild(C)

EditorFrame:SetScript("OnSizeChanged", function(self, w, h)
    C:SetWidth(w - 36)
end)

local P = C

-- ── Name ─────────────────────────────────────────────────────
MakeLabel(P, "Overlay Name:", -10)
local nameBox = MakeEditBox(P, -28, 0, CONTENT_W - 16)
nameBox:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    LiveApply("name", self:GetText():match("^%s*(.-)%s*$"))
    RefreshManagerList()
end)
nameBox:SetScript("OnEditFocusLost", function(self)
    LiveApply("name", self:GetText():match("^%s*(.-)%s*$"))
    RefreshManagerList()
end)

-- ── Texture ───────────────────────────────────────────────────
MakeLabel(P, "Texture (Suite media name, atlas name, file ID, or Interface\\ path):", -60)
local texBox = MakeEditBox(P, -78, 0, CONTENT_W - 16)
texBox:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    LiveApply("texture", self:GetText():match("^%s*(.-)%s*$"))
end)
texBox:SetScript("OnEditFocusLost", function(self)
    LiveApply("texture", self:GetText():match("^%s*(.-)%s*$"))
end)

-- ── Size ──────────────────────────────────────────────────────
SectionLabel(P, "Size", -114)
MakeLabel(P, "Width:", -134)
local widthBox = MakeEditBox(P, -152, 50, 60)
MakeLabel(P, "Height:", -134, 130)
local heightBox = MakeEditBox(P, -152, 180, 60)

local function ApplySize()
    local w = tonumber(widthBox:GetText())  or 200
    local h = tonumber(heightBox:GetText()) or 200
    LiveApplyMulti({ width = w, height = h })
end
widthBox:SetScript("OnEnterPressed",  function(self) self:ClearFocus() ApplySize() end)
widthBox:SetScript("OnEditFocusLost", function() ApplySize() end)
heightBox:SetScript("OnEnterPressed",  function(self) self:ClearFocus() ApplySize() end)
heightBox:SetScript("OnEditFocusLost", function() ApplySize() end)

-- ── Position ──────────────────────────────────────────────────
SectionLabel(P, "Position", -180)
MakeLabel(P, "X:", -200)
local xBox = MakeEditBox(P, -218, 18, 60)
MakeLabel(P, "Y:", -200, 100)
local yBox = MakeEditBox(P, -218, 118, 60)

local function ApplyPosition()
    local x = tonumber(xBox:GetText()) or 0
    local y = tonumber(yBox:GetText()) or 0
    LiveApplyMulti({ x = x, y = y })
end
xBox:SetScript("OnEnterPressed",  function(self) self:ClearFocus() ApplyPosition() end)
xBox:SetScript("OnEditFocusLost", function() ApplyPosition() end)
yBox:SetScript("OnEnterPressed",  function(self) self:ClearFocus() ApplyPosition() end)
yBox:SetScript("OnEditFocusLost", function() ApplyPosition() end)

-- ── Nudge controls ────────────────────────────────────────────
local nudgeRow = CreateFrame("Frame", nil, P)
nudgeRow:SetSize(CONTENT_W, 30)
nudgeRow:SetPoint("TOPLEFT", 0, -248)

local nudgeIncrLbl = nudgeRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
nudgeIncrLbl:SetPoint("TOPLEFT", 0, 0)
nudgeIncrLbl:SetText("Nudge:")

local nudgeIncr = CreateFrame("EditBox", nil, nudgeRow, "InputBoxTemplate")
nudgeIncr:SetSize(36, 18)
nudgeIncr:SetPoint("LEFT", nudgeIncrLbl, "RIGHT", 4, 0)
nudgeIncr:SetAutoFocus(false)
nudgeIncr:SetText("1")
nudgeIncr:SetMaxLetters(5)

local nudgePxLbl = nudgeRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
nudgePxLbl:SetPoint("LEFT", nudgeIncr, "RIGHT", 4, 0)
nudgePxLbl:SetText("px")

local btnUp    = MakeButton(nudgeRow, "▲", 24, 20)
local btnDown  = MakeButton(nudgeRow, "▼", 24, 20)
local btnLeft  = MakeButton(nudgeRow, "◄", 24, 20)
local btnRight = MakeButton(nudgeRow, "►", 24, 20)
btnUp:SetPoint("LEFT",    nudgePxLbl, "RIGHT", 16, 0)
btnDown:SetPoint("LEFT",  btnUp,      "RIGHT",  4, 0)
btnLeft:SetPoint("LEFT",  btnDown,    "RIGHT",  4, 0)
btnRight:SetPoint("LEFT", btnLeft,    "RIGHT",  4, 0)

-- ── Transform ─────────────────────────────────────────────────
SectionLabel(P, "Transform", -290)
MakeLabel(P, "Rotation:", -310)

local rotSlider = MakeSlider(P, -328, 20, CONTENT_W - 80, -360, 360, 1)
rotSlider:SetValue(0)

local rotValLbl = P:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
rotValLbl:SetPoint("LEFT", rotSlider, "RIGHT", 6, 0)
rotValLbl:SetText("0°")
rotValLbl:SetWidth(36)

local rotTickParent = CreateFrame("Frame", nil, P)
rotTickParent:SetSize(CONTENT_W - 80, 10)
rotTickParent:SetPoint("TOPLEFT", 20, -344)

for i, frac in ipairs({ 0, 0.25, 0.5, 0.75, 1.0 }) do
    local tick = rotTickParent:CreateTexture(nil, "OVERLAY")
    tick:SetSize(1, 4)
    tick:SetColorTexture(0.5, 0.5, 0.5, 0.8)
    tick:SetPoint("TOPLEFT", (CONTENT_W - 80) * frac, 0)
    local labels = { "-360°", "-180°", "0°", "180°", "360°" }
    local tlbl = rotTickParent:CreateFontString(nil, "OVERLAY", "GameFontNormalTiny")
    tlbl:SetPoint("TOP", tick, "BOTTOM", 0, -1)
    tlbl:SetText(labels[i])
    tlbl:SetTextColor(0.55, 0.55, 0.55)
end

rotSlider:SetScript("OnValueChanged", function(self, val)
    val = math.floor(val + 0.5)
    rotValLbl:SetText(val .. "°")
    LiveApply("rotation", val)
end)

local rotResetBtn = MakeButton(P, "Reset", 46, 16)
rotResetBtn:SetPoint("TOPLEFT", 0, -310)
rotResetBtn:SetScript("OnClick", function()
    rotSlider:SetValue(0)
end)

-- ── Flip ──────────────────────────────────────────────────────
local flipHBtn, _ = MakeCheck(P, "Flip Horizontal", -366, 0)
local flipVBtn, _ = MakeCheck(P, "Flip Vertical",   -366, 160)

flipHBtn:SetScript("OnClick", function(self)
    LiveApply("flipH", self:GetChecked() and true or false)
end)
flipVBtn:SetScript("OnClick", function(self)
    LiveApply("flipV", self:GetChecked() and true or false)
end)

-- ── Spin animation ────────────────────────────────────────────
MakeLabel(P, "Spin speed (°/sec, 0 = off):", -398)
local spinSpeedBox = MakeEditBox(P, -416, 0, 60)
spinSpeedBox:SetText("0")
spinSpeedBox:SetMaxLetters(6)

local function ApplySpin()
    LiveApplyMulti({
        spinSpeed = tonumber(spinSpeedBox:GetText()) or 0,
        spinDir   = selectedSpinDir,
    })
end

spinSpeedBox:SetScript("OnEnterPressed",  function(self) self:ClearFocus() ApplySpin() end)
spinSpeedBox:SetScript("OnEditFocusLost", function() ApplySpin() end)

MakeLabel(P, "Direction:", -398, 120)
local spinDirs    = { "cw", "ccw" }
local spinDirBtns = {}
selectedSpinDir   = "cw"

local function SetSpinDir(d)
    selectedSpinDir = d
    for _, b in pairs(spinDirBtns) do b:Enable() end
    spinDirBtns[d]:Disable()
    ApplySpin()
end

local sdx = 190
for _, d in ipairs(spinDirs) do
    local btn = MakeButton(P, d == "cw" and "CW ↻" or "CCW ↺", 58, 20)
    btn:SetPoint("TOPLEFT", sdx, -416)
    btn:SetScript("OnClick", function() SetSpinDir(d) end)
    spinDirBtns[d] = btn
    sdx = sdx + 62
end
spinDirBtns["cw"]:Disable()

-- ── Appearance ────────────────────────────────────────────────
SectionLabel(P, "Appearance", -446)
MakeLabel(P, "Alpha:", -466)

local alphaSlider = MakeSlider(P, -484, 20, CONTENT_W - 80, 0, 100, 1)
alphaSlider:SetValue(100)

local alphaValLbl = P:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
alphaValLbl:SetPoint("LEFT", alphaSlider, "RIGHT", 6, 0)
alphaValLbl:SetText("100%")
alphaValLbl:SetWidth(36)

alphaSlider:SetScript("OnValueChanged", function(self, val)
    val = math.floor(val + 0.5)
    alphaValLbl:SetText(val .. "%")
    LiveApply("alpha", val / 100)
end)

-- ── Tint ──────────────────────────────────────────────────────
MakeLabel(P, "Tint:", -510)

local tintR, tintG, tintB = 1, 1, 1

local tintSwatch = P:CreateTexture(nil, "OVERLAY")
tintSwatch:SetSize(24, 14)
tintSwatch:SetPoint("TOPLEFT", 38, -512)
tintSwatch:SetColorTexture(1, 1, 1, 1)

local function SetTint(r, g, b)
    tintR, tintG, tintB = r, g, b
    tintSwatch:SetColorTexture(r, g, b, 1)
end

local chooseColorBtn = MakeButton(P, "Choose Color\226\128\166", 110, 22)
chooseColorBtn:SetPoint("TOPLEFT", 70, -508)

chooseColorBtn:SetScript("OnClick", function()
    local rOld, gOld, bOld = tintR, tintG, tintB

    local function OnChange(restore)
        local r, g, b
        if restore then
            r, g, b = rOld, gOld, bOld
        else
            r, g, b = ColorPickerFrame:GetColorRGB()
        end
        SetTint(r, g, b)
        LiveApplyMulti({ tintR = r, tintG = g, tintB = b })
    end

    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = tintR, g = tintG, b = tintB,
            hasOpacity  = false,
            swatchFunc  = function() OnChange(false) end,
            cancelFunc  = function() OnChange(true)  end,
        })
    else
        ColorPickerFrame:SetColorRGB(tintR, tintG, tintB)
        ColorPickerFrame.previousValues = { tintR, tintG, tintB }
        ColorPickerFrame.func           = function() OnChange(false) end
        ColorPickerFrame.cancelFunc     = function() OnChange(true)  end
        ColorPickerFrame.hasOpacity     = false
        ColorPickerFrame:Hide()
        ColorPickerFrame:Show()
    end
end)

local resetTintBtn = MakeButton(P, "Reset", 46, 22)
resetTintBtn:SetPoint("LEFT", chooseColorBtn, "RIGHT", 6, 0)
resetTintBtn:SetScript("OnClick", function()
    SetTint(1, 1, 1)
    LiveApplyMulti({ tintR = 1, tintG = 1, tintB = 1 })
end)

local classColorCheck,       _ = MakeCheck(P, "Player class color", -538,  0)
local targetClassColorCheck, _ = MakeCheck(P, "Target class color", -538, 160)

local function GetUnitClassColor(unit)
    local _, classTag = UnitClass(unit)
    if classTag and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classTag] then
        return RAID_CLASS_COLORS[classTag]
    end
end

local function ApplyClassColor(unit)
    local c = GetUnitClassColor(unit or "player")
    if c then
        SetTint(c.r, c.g, c.b)
        LiveApplyMulti({
            tintR          = c.r,
            tintG          = c.g,
            tintB          = c.b,
            useClassColor  = (unit ~= "target") and true or nil,
            useTargetColor = (unit == "target")  and true or nil,
        })
    end
end

local function LockTintControls(locked)
    if locked then
        chooseColorBtn:Disable()
        resetTintBtn:Disable()
    else
        chooseColorBtn:Enable()
        resetTintBtn:Enable()
    end
end

classColorCheck:SetScript("OnClick", function(self)
    if self:GetChecked() then
        targetClassColorCheck:SetChecked(false)
        LiveApply("useTargetColor", false)
        ApplyClassColor("player")
        LockTintControls(true)
    else
        LiveApply("useClassColor", false)
        LockTintControls(false)
    end
end)

targetClassColorCheck:SetScript("OnClick", function(self)
    if self:GetChecked() then
        classColorCheck:SetChecked(false)
        LiveApply("useClassColor", false)
        ApplyClassColor("target")
        LockTintControls(true)
    else
        LiveApply("useTargetColor", false)
        LockTintControls(false)
    end
end)

local targetColorFrame = CreateFrame("Frame")
targetColorFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
targetColorFrame:SetScript("OnEvent", function()
    local profile = GloomsOverlays_GetProfile and GloomsOverlays_GetProfile()
    if not profile or not profile.overlays then return end
    for _, ov in ipairs(profile.overlays) do
        if ov.useTargetColor then
            local c = GetUnitClassColor("target")
            if c then
                ov.tintR, ov.tintG, ov.tintB = c.r, c.g, c.b
            else
                ov.tintR, ov.tintG, ov.tintB = 1, 1, 1
            end
        end
    end
    GloomsOverlays_ApplyAll()
    if currentEditIndex and EditorFrame:IsShown() then
        local ov = profile.overlays[currentEditIndex]
        if ov and ov.useTargetColor then
            SetTint(ov.tintR, ov.tintG, ov.tintB)
        end
    end
end)

-- ── Blend mode ────────────────────────────────────────────────
MakeLabel(P, "Blend mode:", -552)
local blendModes  = { "BLEND", "ADD", "MOD" }
local blendBtns   = {}
local selectedBlend = "BLEND"

local function SetBlendMode(mode)
    selectedBlend = mode
    for _, b in pairs(blendBtns) do b:Enable() end
    blendBtns[mode]:Disable()
    LiveApply("blendMode", mode)
end

local bx = 100
for _, mode in ipairs(blendModes) do
    local btn = MakeButton(P, mode, 54, 20)
    btn:SetPoint("TOPLEFT", bx, -570)
    btn:SetScript("OnClick", function() SetBlendMode(mode) end)
    blendBtns[mode] = btn
    bx = bx + 58
end

-- ── Layer (strata) ────────────────────────────────────────────
SectionLabel(P, "Layer (z-order)", -600)
local strataHint = P:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
strataHint:SetPoint("TOPLEFT", 0, -616)
strataHint:SetWidth(CONTENT_W)
strataHint:SetJustifyH("LEFT")
strataHint:SetTextColor(0.55, 0.55, 0.55)
strataHint:SetText("BACKGROUND = below UI   HIGH = above most UI   TOOLTIP = above everything")

local strataOptions = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "TOOLTIP" }
local strataBtns    = {}
local selectedStrata = "HIGH"

local function SetStrata(s)
    selectedStrata = s
    for _, b in pairs(strataBtns) do b:Enable() end
    strataBtns[s]:Disable()
    LiveApply("strata", s)
end

local strataY1, strataY2 = -632, -654
local strataXs = {}
for i = 1, 4 do strataXs[i] = (i-1) * 62 end
for i = 5, 7 do strataXs[i] = (i-5) * 62 end
local strataYs = { strataY1, strataY1, strataY1, strataY1, strataY2, strataY2, strataY2 }

for i, s in ipairs(strataOptions) do
    local btn = MakeButton(P, s == "FULLSCREEN" and "FSCREEN" or s, 58, 18)
    btn:SetPoint("TOPLEFT", strataXs[i], strataYs[i])
    btn:SetScript("OnClick", function() SetStrata(s) end)
    strataBtns[s] = btn
end
strataBtns["HIGH"]:Disable()

-- ── Visibility ────────────────────────────────────────────────
SectionLabel(P, "Visibility  |cffaaaaaa(show if any checked condition is true)|r", -686)

local condOptions = { "always", "combat", "nocombat", "target", "casting" }
local condLabels  = { "Always visible", "In combat", "Out of combat", "Target selected", "While casting" }
local condBtns    = {}

local function GetConditionSet()
    local set = {}
    for i, opt in ipairs(condOptions) do
        if condBtns[i]:GetChecked() then
            set[opt] = true
        end
    end
    return set
end

local function SetConditionSet(condStr)
    local active = {}
    for word in (condStr or "always"):gmatch("[^,]+") do
        active[word] = true
    end
    local anyKnown = false
    for _, opt in ipairs(condOptions) do
        if active[opt] then anyKnown = true; break end
    end
    if not anyKnown then active["always"] = true end
    for i, opt in ipairs(condOptions) do
        condBtns[i]:SetChecked(active[opt] == true)
    end
end

local function ApplyConditions()
    local set = GetConditionSet()
    local parts = {}
    for _, opt in ipairs(condOptions) do
        if set[opt] then parts[#parts+1] = opt end
    end
    local condStr = #parts > 0 and table.concat(parts, ",") or "always"
    LiveApply("condition", condStr)
end

for i, opt in ipairs(condOptions) do
    local btn, _ = MakeCheck(P, condLabels[i], -704 - (i-1)*24, 0)
    btn:SetScript("OnClick", function() ApplyConditions() end)
    condBtns[i] = btn
end
condBtns[1]:SetChecked(true)

-- ============================================================
-- OpenEditor
-- ============================================================

OpenEditor = function(index)
    local profile = GloomsOverlays_GetProfile()
    local ov = profile and profile.overlays and profile.overlays[index]
    if not ov then return end
    currentEditIndex = index

    nameBox:SetText(ov.name or "")
    texBox:SetText(ov.texture or "")
    widthBox:SetText(tostring(ov.width  or 200))
    heightBox:SetText(tostring(ov.height or 200))
    xBox:SetText(tostring(ov.x or 0))
    yBox:SetText(tostring(ov.y or 0))

    local rot = math.max(-360, math.min(360, ov.rotation or 0))
    rotSlider:SetValue(rot)

    alphaSlider:SetValue(math.floor((ov.alpha or 1.0) * 100 + 0.5))
    flipHBtn:SetChecked(ov.flipH or false)
    flipVBtn:SetChecked(ov.flipV or false)
    spinSpeedBox:SetText(tostring(ov.spinSpeed or 0))
    SetSpinDir(ov.spinDir or "cw")
    SetTint(ov.tintR or 1, ov.tintG or 1, ov.tintB or 1)
    local ucc = ov.useClassColor  == true
    local utc = ov.useTargetColor == true
    classColorCheck:SetChecked(ucc)
    targetClassColorCheck:SetChecked(utc)
    if ucc then
        LockTintControls(true)
        ApplyClassColor("player")
    elseif utc then
        LockTintControls(true)
        ApplyClassColor("target")
    else
        LockTintControls(false)
    end
    SetBlendMode(ov.blendMode or "BLEND")
    SetStrata(ov.strata or "HIGH")
    SetConditionSet(ov.condition or "always")

    edScroll:SetVerticalScroll(0)
    edStatus:SetText(" ")
    EditorFrame:Show()
    EditorFrame:Raise()
    EditorFrame:SetFrameLevel(20)
end

-- ============================================================
-- Nudge button logic
-- ============================================================

local function GetNudge()
    return tonumber(nudgeIncr:GetText()) or 1
end

local function LiveNudge(field, delta)
    if not currentEditIndex then return end
    local profile = GloomsOverlays_GetProfile()
    local ov = profile and profile.overlays and profile.overlays[currentEditIndex]
    if not ov then return end
    ov[field] = (ov[field] or 0) + delta
    if field == "x" then xBox:SetText(tostring(ov.x))
    else                  yBox:SetText(tostring(ov.y)) end
    GloomsOverlays_ApplyAll()
end

btnUp:SetScript("OnClick",    function() LiveNudge("y",  GetNudge()) end)
btnDown:SetScript("OnClick",  function() LiveNudge("y", -GetNudge()) end)
btnRight:SetScript("OnClick", function() LiveNudge("x",  GetNudge()) end)
btnLeft:SetScript("OnClick",  function() LiveNudge("x", -GetNudge()) end)

-- ============================================================
-- Save & Apply button
-- ============================================================

saveBtn:SetScript("OnClick", function()
    if not currentEditIndex then return end
    local profile = GloomsOverlays_GetProfile()
    local ov = profile and profile.overlays and profile.overlays[currentEditIndex]
    if not ov then return end

    ov.name    = nameBox:GetText():match("^%s*(.-)%s*$")
    ov.texture = texBox:GetText():match("^%s*(.-)%s*$")
    ov.width   = tonumber(widthBox:GetText())  or 200
    ov.height  = tonumber(heightBox:GetText()) or 200
    ov.x       = tonumber(xBox:GetText())      or 0
    ov.y       = tonumber(yBox:GetText())      or 0

    GloomsOverlays_ApplyAll()
    RefreshManagerList()
    edStatus:SetText("|cff44ff44Saved!|r")
end)

-- ============================================================
-- Save as New Overlay (called from Preview panel)
-- ============================================================

function GloomsOverlays_SaveFromPreview(textureInput, sheetData)
    if not VibeOverlayDB then
        error("VibeOverlayDB not initialised")
    end
    local profile  = GloomsOverlays_GetProfile()
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
    RefreshManagerList()
    ManagerFrame:Show()
    ManagerFrame:Raise()
    OpenEditor(newIndex)
end

-- ============================================================
-- Expose open function for slash commands
-- ============================================================

function GloomsOverlays_OpenManager()
    RefreshProfileDropdown()
    RefreshManagerList()
    ManagerFrame:Show()
    ManagerFrame:Raise()
    ManagerFrame:SetFrameLevel(10)
end

-- ============================================================
-- Esc key support
-- ============================================================

tinsert(UISpecialFrames, "GloomsOverlaysEditor")
tinsert(UISpecialFrames, "GloomsOverlaysManager")
