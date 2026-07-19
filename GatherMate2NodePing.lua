local ADDON_NAME = "GatherMate2NodePing"

local REAPPEAR_AFTER = 180
local ZONING_QUIET_TIME = 5
local BUTTON_ICON = "Interface\\AddOns\\GatherMate2\\Artwork\\Icon"
local PULSE_TEXTURE = "Interface\\AddOns\\GatherMate2NodePing\\pulse_ring"
local PULSE_COLOR = { 1, 0.82, 0 }
local DEFAULT_SOUND_ID = 3175  -- SOUNDKIT.MAP_PING (minimap ping)

-- Friendly named alerts for the sound picker, same list ChatScan offers.
local SOUND_PRESETS = {
    { name = "Minimap Ping",   id = SOUNDKIT.MAP_PING },
    { name = "Whisper",        id = SOUNDKIT.TELL_MESSAGE },
    { name = "Raid Warning",   id = SOUNDKIT.RAID_WARNING },
    { name = "Ready Check",    id = SOUNDKIT.READY_CHECK },
    { name = "Auction Window", id = SOUNDKIT.AUCTION_WINDOW_OPEN },
    { name = "Alarm Clock",    id = SOUNDKIT.ALARM_CLOCK_WARNING_1 },
    { name = "Murloc",         id = SOUNDKIT.MURLOC_AGGRO },
}

local COOLDOWNS = { 1, 3, 5, 10, 20, 30 }

-- Layout spacing, mirrored from ChatScan so both addons share one look.
local PAD = 16                  -- outer panel padding (sides + bottom)
local PAD_TOP = 48              -- clears the dialog-box-header banner
local SECTION_GAP = 24          -- vertical space between two section boxes
local SECTION_INNER_PAD = 8     -- inset between section border and body
local SECTION_LABEL_LIFT = 7    -- header banner overlap; visual-only
local HELPER_GAP = 8            -- space below a section's helper text
local ROW_H = 24                -- height of an interactive row (input/button)
local ROW_GAP = 4               -- vertical space between row siblings
local CB_H = 20                 -- native UICheckButton size

local GatherMate = LibStub("AceAddon-3.0"):GetAddon("GatherMate2")
local Display = GatherMate:GetModule("Display")

local db
local panel
local seen = {}
local lastPing = 0
local quietUntil = 0

local function soundName(id)
    for _, preset in ipairs(SOUND_PRESETS) do
        if preset.id == id then return preset.name end
    end
    return "Unknown"
end

-- Gold ring over the minimap edge that fades in and out on each ping.
local pulse = CreateFrame("Frame", nil, Minimap)
pulse:SetAllPoints(Minimap)
pulse:SetFrameLevel(Minimap:GetFrameLevel() + 7)
pulse:Hide()

local pulseRing = pulse:CreateTexture(nil, "OVERLAY")
pulseRing:SetAllPoints(pulse)
pulseRing:SetTexture(PULSE_TEXTURE)
pulseRing:SetVertexColor(unpack(PULSE_COLOR))

-- The texture is a 4x2 atlas of rings from hairline to bold; the slider
-- index picks a cell, runtime drawing is not possible in the client.
local function applyThickness()
    local index = (db and db.pulseThickness or 4) - 1
    local col = index % 4
    local row = math.floor(index / 4)
    pulseRing:SetTexCoord(col * 0.25, (col + 1) * 0.25, row * 0.5, (row + 1) * 0.5)
end

local pulseAnim = pulse:CreateAnimationGroup()
local fadeIn = pulseAnim:CreateAnimation("Alpha")
fadeIn:SetFromAlpha(0)
fadeIn:SetToAlpha(1)
fadeIn:SetDuration(0.1)
fadeIn:SetOrder(1)
local fadeOut = pulseAnim:CreateAnimation("Alpha")
fadeOut:SetFromAlpha(1)
fadeOut:SetToAlpha(0)
fadeOut:SetDuration(0.8)
fadeOut:SetOrder(2)
pulseAnim:SetScript("OnFinished", function() pulse:Hide() end)

-- Tint the flash like the tracking circle that triggered it, so the color
-- alone tells the node type; GatherMate2 keeps those colors per type in its
-- profile, the same table its own circles are tinted from.
local function firePulse(nodeType)
    local colors = GatherMate.db.profile.trackColors
    local color = nodeType and colors and colors[nodeType]
    if color then
        pulseRing:SetVertexColor(color.Red, color.Green, color.Blue)
    else
        pulseRing:SetVertexColor(unpack(PULSE_COLOR))
    end
    pulse:Show()
    pulseAnim:Restart()
end

local function ping(nodeType)
    if db.enabled then
        PlaySound(db.soundId or DEFAULT_SOUND_ID, db.channel, true)
    end
    if db.pulse then
        firePulse(nodeType)
    end
end

-- Display:addMiniPin turns a pin into the tracking circle once the node is
-- within GatherMate2's track distance. Ping on that transition only; far
-- icon pins at the minimap edge stay silent. The hook runs every frame per
-- pin, so bail out cheaply for everything that is not a circle.
hooksecurefunc(Display, "addMiniPin", function(_, pin)
    if not pin.isCircle then return end

    -- Skip before touching seen: nodes circled while muted, mid flight,
    -- or mid fight should still alert once pings are possible again.
    if not (db and (db.enabled or db.pulse)) then return end
    if db.mutedTypes[pin.nodeType] then return end
    if UnitOnTaxi("player") or InCombatLockdown() then return end

    local now = GetTime()
    local byType = seen[pin.nodeType]
    if not byType then
        byType = {}
        seen[pin.nodeType] = byType
    end

    local lastSeen = byType[pin.coords]
    byType[pin.coords] = now

    if lastSeen and now - lastSeen < REAPPEAR_AFTER then return end
    if now < quietUntil or now - lastPing < db.cooldown then return end

    lastPing = now
    ping(pin.nodeType)
end)

---------------------------------------------------------
-- Settings panel, built from ChatScan's dialog patterns.

-- Native Blizzard dialog backdrop (same art AceGUI's Frame / ChatScan use).
local function applyPanelBackdrop(frame)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
end

-- Blizzard dialog-box header banner from three pieces (left cap, middle,
-- right cap); texcoords match ChatScan's title.
local function buildTitleHeader(parent, text)
    local HEADER_TEXTURE = "Interface\\DialogFrame\\UI-DialogBox-Header"

    local mid = parent:CreateTexture(nil, "OVERLAY")
    mid:SetTexture(HEADER_TEXTURE)
    mid:SetTexCoord(0.31, 0.67, 0, 0.63)
    mid:SetPoint("TOP", parent, "TOP", 0, 12)
    mid:SetHeight(40)

    local left = parent:CreateTexture(nil, "OVERLAY")
    left:SetTexture(HEADER_TEXTURE)
    left:SetTexCoord(0.21, 0.31, 0, 0.63)
    left:SetPoint("RIGHT", mid, "LEFT")
    left:SetWidth(30)
    left:SetHeight(40)

    local right = parent:CreateTexture(nil, "OVERLAY")
    right:SetTexture(HEADER_TEXTURE)
    right:SetTexCoord(0.67, 0.77, 0, 0.63)
    right:SetPoint("LEFT", mid, "RIGHT")
    right:SetWidth(30)
    right:SetHeight(40)

    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", mid, "TOP", 0, -14)
    title:SetText(text)

    mid:SetWidth((title:GetStringWidth() or 0) + 10)
end

-- Nested section box (matches AceGUI InlineGroup): flat dark bg + tooltip border.
local function buildSection(parent, labelText)
    local section = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    section:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 3, right = 3, top = 5, bottom = 3 },
    })
    section:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
    section:SetBackdropBorderColor(0.4, 0.4, 0.4)

    local label = section:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("BOTTOMLEFT", section, "TOPLEFT", 12, SECTION_LABEL_LIFT)
    label:SetText(labelText)

    local body = CreateFrame("Frame", nil, section)
    body:SetPoint("TOPLEFT", section, "TOPLEFT", SECTION_INNER_PAD, -SECTION_INNER_PAD)
    body:SetPoint("BOTTOMRIGHT", section, "BOTTOMRIGHT", -SECTION_INNER_PAD, SECTION_INNER_PAD)
    section.body = body

    return section
end

-- UICheckButtonTemplate exposes a .Text region on most clients but not all;
-- fall back to a manual label so both cases render identically.
local function setCheckboxLabel(checkButton, text)
    if checkButton.Text then
        checkButton.Text:SetText(text)
        checkButton.Text:SetFontObject(GameFontHighlightSmall)
    else
        local label = checkButton:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        label:SetPoint("LEFT", checkButton, "RIGHT", 2, 0)
        label:SetText(text)
    end
end

local function buildPanel()
    local f = CreateFrame("Frame", "GatherMate2NodePingPanel", UIParent, "BackdropTemplate")
    f:SetSize(380, 1)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    applyPanelBackdrop(f)

    buildTitleHeader(f, "Node Ping")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    -- Section box with a wrapped helper line at the top and a content
    -- container below it, sized later by resizePanel.
    local function makeContentSection(label, helperText, contentH, prevSection)
        local section = buildSection(f, label)
        if prevSection then
            section:SetPoint("TOPLEFT", prevSection, "BOTTOMLEFT", 0, -SECTION_GAP)
            section:SetPoint("TOPRIGHT", prevSection, "BOTTOMRIGHT", 0, -SECTION_GAP)
        else
            section:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -PAD_TOP)
            section:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -PAD_TOP)
        end

        local helper = section.body:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        helper:SetPoint("TOPLEFT", section.body, "TOPLEFT", 0, 0)
        helper:SetPoint("RIGHT", section.body, "RIGHT", 0, 0)
        helper:SetJustifyH("LEFT")
        helper:SetWordWrap(true)
        helper:SetText(helperText)

        local container = CreateFrame("Frame", nil, section.body)
        container:SetPoint("TOPLEFT", helper, "BOTTOMLEFT", 0, -HELPER_GAP)
        container:SetPoint("RIGHT", section.body, "RIGHT", 0, 0)
        container:SetHeight(contentH)

        section.helper = helper
        section.container = container
        return section, container
    end

    -- Alert
    local alertContentH = CB_H + ROW_GAP + CB_H + HELPER_GAP + 16 + HELPER_GAP + ROW_H + ROW_GAP + CB_H
    local alertSection, alertContainer = makeContentSection(
        "Alert",
        "Plays when a trackable node comes within tracking range of the minimap.",
        alertContentH)

    local soundCheck = CreateFrame("CheckButton", nil, alertContainer, "UICheckButtonTemplate")
    soundCheck:SetSize(CB_H, CB_H)
    soundCheck:SetPoint("TOPLEFT", alertContainer, "TOPLEFT", 0, 0)
    setCheckboxLabel(soundCheck, "Play ping sound")

    local pulseCheck = CreateFrame("CheckButton", nil, alertContainer, "UICheckButtonTemplate")
    pulseCheck:SetSize(CB_H, CB_H)
    pulseCheck:SetPoint("TOPLEFT", soundCheck, "BOTTOMLEFT", 0, -ROW_GAP)
    setCheckboxLabel(pulseCheck, "Flash the minimap edge")

    -- Ring thickness, built like AceGUI's slider since the client ships no
    -- native slider template anymore. Releasing the thumb previews the flash.
    local thicknessSlider = CreateFrame("Slider", nil, alertContainer, "BackdropTemplate")
    thicknessSlider:SetOrientation("HORIZONTAL")
    thicknessSlider:SetSize(160, 16)
    thicknessSlider:SetHitRectInsets(0, 0, -10, 0)
    thicknessSlider:SetBackdrop({
        bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
        edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 3, right = 3, top = 6, bottom = 6 },
    })
    thicknessSlider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    thicknessSlider:SetMinMaxValues(1, 8)
    thicknessSlider:SetValueStep(1)
    thicknessSlider:SetObeyStepOnDrag(true)
    thicknessSlider:SetPoint("TOPLEFT", pulseCheck, "BOTTOMLEFT", 4, -HELPER_GAP)
    thicknessSlider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value + 0.5)
        if value ~= db.pulseThickness then
            db.pulseThickness = value
            applyThickness()
        end
    end)
    thicknessSlider:SetScript("OnMouseUp", function() firePulse() end)

    local thicknessLabel = alertContainer:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    thicknessLabel:SetPoint("LEFT", thicknessSlider, "RIGHT", HELPER_GAP, 0)
    thicknessLabel:SetText("Flash thickness")

    -- Named-sound picker. Choosing a sound saves it and plays it once as a preview.
    local soundDropdown = CreateFrame("DropdownButton", nil, alertContainer, "WowStyle1DropdownTemplate")
    soundDropdown:SetSize(160, ROW_H)
    soundDropdown:SetPoint("TOPLEFT", thicknessSlider, "BOTTOMLEFT", -4, -HELPER_GAP)
    soundDropdown:SetDefaultText("Choose a sound")
    soundDropdown:SetupMenu(function(_, root)
        for _, preset in ipairs(SOUND_PRESETS) do
            root:CreateRadio(preset.name,
                function() return db.soundId == preset.id end,
                function()
                    db.soundId = preset.id
                    PlaySound(preset.id, db.channel, true)
                    f.updateStatus()
                end)
        end
    end)

    -- Replays the selected sound so it can be previewed at any time.
    local testBtn = CreateFrame("Button", nil, alertContainer, "UIPanelButtonTemplate")
    testBtn:SetSize(60, ROW_H)
    testBtn:SetPoint("LEFT", soundDropdown, "RIGHT", ROW_GAP, 0)
    testBtn:SetText("Test")
    testBtn:SetScript("OnClick", function()
        PlaySound(db.soundId or DEFAULT_SOUND_ID, db.channel, true)
        firePulse()
    end)

    local channelCheck = CreateFrame("CheckButton", nil, alertContainer, "UICheckButtonTemplate")
    channelCheck:SetSize(CB_H, CB_H)
    channelCheck:SetPoint("TOPLEFT", soundDropdown, "BOTTOMLEFT", 0, -ROW_GAP)
    setCheckboxLabel(channelCheck, "Play even while sound effects are muted")

    -- Cooldown
    local cooldownSection, cooldownContainer = makeContentSection(
        "Cooldown",
        "Minimum time between two pings. Nodes noticed during the cooldown stay silent.",
        ROW_H, alertSection)

    local cooldownDropdown = CreateFrame("DropdownButton", nil, cooldownContainer, "WowStyle1DropdownTemplate")
    cooldownDropdown:SetSize(160, ROW_H)
    cooldownDropdown:SetPoint("TOPLEFT", cooldownContainer, "TOPLEFT", 0, 0)
    cooldownDropdown:SetDefaultText("Cooldown")
    cooldownDropdown:SetupMenu(function(_, root)
        for _, secs in ipairs(COOLDOWNS) do
            root:CreateRadio(secs == 1 and "1 second" or (secs .. " seconds"),
                function() return db.cooldown == secs end,
                function()
                    db.cooldown = secs
                    f.updateStatus()
                end)
        end
    end)

    -- Node Types
    local nodeTypes = {}
    for _, nodeType in pairs(GatherMate.db_types) do
        nodeTypes[#nodeTypes + 1] = nodeType
    end
    table.sort(nodeTypes)

    local typesContentH = #nodeTypes * CB_H + (#nodeTypes - 1) * ROW_GAP
    local typesSection, typesContainer = makeContentSection(
        "Node Types",
        "Only checked types trigger an alert.",
        typesContentH, cooldownSection)

    local typeChecks = {}
    local anchor
    for i, nodeType in ipairs(nodeTypes) do
        local cb = CreateFrame("CheckButton", nil, typesContainer, "UICheckButtonTemplate")
        cb:SetSize(CB_H, CB_H)
        if i == 1 then
            cb:SetPoint("TOPLEFT", typesContainer, "TOPLEFT", 0, 0)
        else
            cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -ROW_GAP)
        end
        setCheckboxLabel(cb, nodeType)
        cb:SetScript("OnClick", function(self)
            db.mutedTypes[nodeType] = not self:GetChecked() or nil
        end)
        typeChecks[nodeType] = cb
        anchor = cb
    end

    -- Footer (Close on the left, live state summary beside it)
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    closeBtn:SetSize(80, ROW_H)
    closeBtn:SetPoint("BOTTOMLEFT", PAD, PAD)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local statusText = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    statusText:SetPoint("LEFT", closeBtn, "RIGHT", 8, 0)
    statusText:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
    statusText:SetPoint("BOTTOM", closeBtn, "BOTTOM", 0, 0)
    statusText:SetHeight(ROW_H)
    statusText:SetJustifyH("CENTER")

    local function updateStatus()
        if db.enabled or db.pulse then
            statusText:SetText(("|cff40ff40Active|r  •  %s  •  every %ds"):format(
                soundName(db.soundId or DEFAULT_SOUND_ID), db.cooldown))
        else
            statusText:SetText("|cff999999Disabled|r")
        end
    end
    f.updateStatus = updateStatus

    soundCheck:SetScript("OnClick", function(self)
        db.enabled = self:GetChecked() and true or false
        updateStatus()
    end)
    pulseCheck:SetScript("OnClick", function(self)
        db.pulse = self:GetChecked() and true or false
        updateStatus()
    end)
    channelCheck:SetScript("OnClick", function(self)
        db.channel = self:GetChecked() and "Master" or "SFX"
    end)

    -- Section height = helper text + HELPER_GAP + content height + body insets.
    local function sizeContentSection(section)
        local helperH = math.max(section.helper:GetStringHeight(), CB_H)
        section:SetHeight(helperH + HELPER_GAP + section.container:GetHeight() + SECTION_INNER_PAD * 2)
    end

    local function resizePanel()
        sizeContentSection(alertSection)
        sizeContentSection(cooldownSection)
        sizeContentSection(typesSection)

        local sectionsH = alertSection:GetHeight() + SECTION_GAP +
                          cooldownSection:GetHeight() + SECTION_GAP +
                          typesSection:GetHeight()
        local footerH = SECTION_GAP + ROW_H + PAD
        f:SetHeight(PAD_TOP + sectionsH + footerH)
    end

    f:SetScript("OnShow", function()
        soundCheck:SetChecked(db.enabled)
        pulseCheck:SetChecked(db.pulse)
        thicknessSlider:SetValue(db.pulseThickness)
        channelCheck:SetChecked(db.channel == "Master")
        for nodeType, cb in pairs(typeChecks) do
            cb:SetChecked(not db.mutedTypes[nodeType])
        end
        soundDropdown:GenerateMenu()
        cooldownDropdown:GenerateMenu()
        updateStatus()
        resizePanel()
    end)

    tinsert(UISpecialFrames, "GatherMate2NodePingPanel")
    f:Hide()
    return f
end

local function togglePanel()
    if not panel then panel = buildPanel() end
    if panel:IsShown() then panel:Hide() else panel:Show() end
end

---------------------------------------------------------
-- Minimap button

local function renderTooltip(tooltip)
    tooltip:AddLine("GatherMate2NodePing")
    tooltip:AddLine((db.enabled or db.pulse) and "Alert is on." or "Alert is off.", 1, 1, 1)
    tooltip:AddLine("|cffffd200Left-click|r opens the settings.", 1, 1, 1)
    tooltip:AddLine("|cffffd200Right-click|r toggles the alert.", 1, 1, 1)
end

local function updateButton()
    local dbicon = LibStub("LibDBIcon-1.0", true)
    local button = dbicon and dbicon:GetMinimapButton(ADDON_NAME)
    if not button then return end
    button.icon:SetDesaturated(not (db.enabled or db.pulse))

    -- Refresh the tooltip in place while the cursor is still on the button.
    if GameTooltip:IsOwned(button) then
        GameTooltip:ClearLines()
        renderTooltip(GameTooltip)
        GameTooltip:Show()
    end
end

local function toggleAlert()
    local turnOn = not (db.enabled or db.pulse)
    db.enabled = turnOn
    db.pulse = turnOn
    PlaySound(turnOn and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
                     or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    updateButton()
    if panel and panel:IsShown() then panel:GetScript("OnShow")(panel) end
end

-- Libs come embedded in other addons, so register the button once every
-- addon has loaded.
local function setupMinimapButton()
    local ldb = LibStub("LibDataBroker-1.1", true)
    local dbicon = LibStub("LibDBIcon-1.0", true)
    if not (ldb and dbicon) then return end
    if dbicon:IsRegistered(ADDON_NAME) then return end

    local launcher = ldb:NewDataObject(ADDON_NAME, {
        type = "launcher",
        text = ADDON_NAME,
        icon = BUTTON_ICON,
        OnClick = function(_, button)
            if button == "RightButton" then
                toggleAlert()
            else
                togglePanel()
            end
        end,
        OnTooltipShow = renderTooltip,
    })
    dbicon:Register(ADDON_NAME, launcher, db.minimap)
    updateButton()
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" then
        if addonName == ADDON_NAME then
            GatherMate2NodePingDB = GatherMate2NodePingDB or {}
            db = GatherMate2NodePingDB
            if db.enabled == nil then db.enabled = true end
            if db.pulse == nil then db.pulse = true end
            db.minimap = db.minimap or {}
            db.cooldown = db.cooldown or 10
            db.channel = db.channel or "SFX"
            db.mutedTypes = db.mutedTypes or {}

            db.pulseThickness = db.pulseThickness or 4

            -- Older versions stored a SOUNDKIT key string in db.sound.
            db.soundId = db.soundId or (db.sound and SOUNDKIT[db.sound]) or DEFAULT_SOUND_ID
            db.sound = nil

            applyThickness()
        end
    elseif event == "PLAYER_LOGIN" then
        setupMinimapButton()
    else
        -- Zoning repopulates every pin at once; stay quiet instead of spam.
        wipe(seen)
        quietUntil = GetTime() + ZONING_QUIET_TIME
    end
end)
