local addonName, ns = ...

-- Saved variable (initialized on ADDON_LOADED)
local db

-- Runtime state
local lastMountID
local fallbackMountID
local blacklist
local mountButton
local optionsCategory

-- Lazy spell-to-mount lookup
local spellToMount

-- Throttle for COMPANION_UPDATE
local companionUpdatePending = false
local COMPANION_THROTTLE = 0.5

local DB_DEFAULTS = {
    lastMountID = nil,
    fallbackMountID = nil,
    blacklist = {},
}

local function InitDB()
    if not LastMountDB then
        LastMountDB = {}
    end
    for k, v in pairs(DB_DEFAULTS) do
        if LastMountDB[k] == nil then
            LastMountDB[k] = v
        end
    end
    if type(LastMountDB.blacklist) ~= "table" then
        LastMountDB.blacklist = {}
    end
    db = LastMountDB
    lastMountID = db.lastMountID
    fallbackMountID = db.fallbackMountID
    blacklist = db.blacklist
end

---------------------------------------------------------------------------
-- Mount Detection
---------------------------------------------------------------------------

local function FindActiveMount()
    local mountIDs = C_MountJournal.GetMountIDs()
    for _, mountID in ipairs(mountIDs) do
        local name, spellID, _, isActive = C_MountJournal.GetMountInfoByID(mountID)
        if isActive then
            return mountID
        end
    end
    return nil
end

local function BuildMountSpellLookup()
    if spellToMount then return end
    spellToMount = {}
    local mountIDs = C_MountJournal.GetMountIDs()
    for _, mountID in ipairs(mountIDs) do
        local name, spellID = C_MountJournal.GetMountInfoByID(mountID)
        if spellID then
            spellToMount[spellID] = mountID
        end
    end
end

local function OnSpellcastSucceeded(unit, _, spellID)
    -- Unit is always "player" (filtered via RegisterUnitEvent)
    BuildMountSpellLookup()
    local mountID = spellToMount[spellID]
    if mountID then
        if blacklist and blacklist[mountID] then return end
        lastMountID = mountID
        db.lastMountID = mountID
    end
end

local function OnCompanionUpdate()
    if not IsMounted() then return end
    -- Throttle: coalesce rapid COMPANION_UPDATE bursts into a single scan
    if companionUpdatePending then return end
    companionUpdatePending = true
    C_Timer.After(COMPANION_THROTTLE, function()
        companionUpdatePending = false
        if not IsMounted() then return end
        local mountID = FindActiveMount()
        if mountID then
            if blacklist and blacklist[mountID] then return end
            lastMountID = mountID
            db.lastMountID = mountID
        end
    end)
end

---------------------------------------------------------------------------
-- Mount Button
---------------------------------------------------------------------------

local function CreateMountButton()
    mountButton = CreateFrame("Button", "LastMountButton", UIParent)
    mountButton:RegisterForClicks("AnyUp")
    mountButton:Show()

    mountButton:SetScript("OnClick", function(self, button, down)
        if IsMounted() then
            C_MountJournal.Dismiss()
            return
        end

        local id = lastMountID or fallbackMountID or 0
        C_MountJournal.SummonByID(id)
    end)
end

---------------------------------------------------------------------------
-- Slash Commands
---------------------------------------------------------------------------

local function GetMountName(mountID)
    if not mountID then return nil end
    local name = C_MountJournal.GetMountInfoByID(mountID)
    return name
end

local function GetMountSpellID(mountID)
    if not mountID then return nil end
    local _, spellID = C_MountJournal.GetMountInfoByID(mountID)
    return spellID
end

local function ShowStatus()
    local lastName = GetMountName(lastMountID)
    local fbName = GetMountName(fallbackMountID)

    print("|cff00ccffLastMount|r status:")
    if lastName then
        print("  Last mount: |cff00ff00" .. lastName .. "|r (ID: " .. (GetMountSpellID(lastMountID) or "?") .. ")")
    else
        print("  Last mount: |cff888888none|r")
    end
    if fbName then
        print("  Fallback: |cff00ff00" .. fbName .. "|r (ID: " .. (GetMountSpellID(fallbackMountID) or "?") .. ")")
    else
        print("  Fallback: |cff888888none|r")
    end
    local blCount = 0
    if blacklist then
        for _ in pairs(blacklist) do blCount = blCount + 1 end
    end
    print("  Blacklisted: |cffffff00" .. blCount .. "|r mount(s)")
    print("  Macro: |cffffff00/click LastMountButton|r")
end

local function FindMountByName(input)
    local search = strtrim(input)
    if search == "" then return nil end

    local searchID = tonumber(search)
    local searchLower = search:lower()
    local mountIDs = C_MountJournal.GetMountIDs()
    local exactMatch, substringMatch

    for _, mountID in ipairs(mountIDs) do
        local name, spellID, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
        if isCollected and name then
            if searchID and spellID == searchID then
                return mountID
            end
            local lower = name:lower()
            if lower == searchLower then
                exactMatch = mountID
                break
            elseif not substringMatch and lower:find(searchLower, 1, true) then
                substringMatch = mountID
            end
        end
    end

    return exactMatch or substringMatch
end

local function SetFallbackByName(input)
    if strtrim(input) == "" then
        print("|cff00ccffLastMount|r: Please provide a mount name or spell ID.")
        return
    end

    local match = FindMountByName(input)
    if match then
        fallbackMountID = match
        db.fallbackMountID = match
        local name = GetMountName(match)
        print("|cff00ccffLastMount|r: Fallback set to |cff00ff00" .. name .. "|r (ID: " .. (GetMountSpellID(match) or "?") .. ")")
    else
        print("|cff00ccffLastMount|r: No collected mount found matching \"" .. input .. "\".")
    end
end

local function ClearFallback()
    fallbackMountID = nil
    db.fallbackMountID = nil
    print("|cff00ccffLastMount|r: Fallback mount cleared.")
end

local function AddToBlacklist(input)
    if strtrim(input) == "" then
        print("|cff00ccffLastMount|r: Please provide a mount name or spell ID.")
        return
    end
    local mountID = FindMountByName(input)
    if not mountID then
        print("|cff00ccffLastMount|r: No collected mount found matching \"" .. input .. "\".")
        return
    end
    if blacklist[mountID] then
        print("|cff00ccffLastMount|r: |cff00ff00" .. GetMountName(mountID) .. "|r is already blacklisted.")
        return
    end
    blacklist[mountID] = true
    print("|cff00ccffLastMount|r: Added |cff00ff00" .. GetMountName(mountID) .. "|r to blacklist.")
end

local function RemoveFromBlacklist(input)
    local mountID = FindMountByName(input)
    if not mountID or not blacklist[mountID] then
        print("|cff00ccffLastMount|r: Mount not found in blacklist.")
        return
    end
    blacklist[mountID] = nil
    local name = GetMountName(mountID)
    print("|cff00ccffLastMount|r: Removed |cff00ff00" .. name .. "|r from blacklist.")
end

local function ListBlacklist()
    local count = 0
    for mountID in pairs(blacklist) do
        local name = GetMountName(mountID) or "Unknown"
        print("  |cff00ff00" .. name .. "|r (ID: " .. (GetMountSpellID(mountID) or "?") .. ")")
        count = count + 1
    end
    if count == 0 then
        print("|cff00ccffLastMount|r: Blacklist is empty.")
    else
        print("|cff00ccffLastMount|r: " .. count .. " mount(s) blacklisted.")
    end
end

local function PrintUsage()
    print("|cff00ccffLastMount|r usage:")
    print("  |cffffff00/lastmount|r — open options panel")
    print("  |cffffff00/lastmount help|r — show status and commands")
    print("  |cffffff00/lastmount fallback <name|id>|r — set fallback mount")
    print("  |cffffff00/lastmount fallback reset|r — clear fallback mount")
    print("  |cffffff00/lastmount blacklist add <name|id>|r — blacklist a mount")
    print("  |cffffff00/lastmount blacklist remove <name|id>|r — remove from blacklist")
    print("  |cffffff00/lastmount blacklist list|r — show blacklisted mounts")
end

local function RegisterSlashCommands()
    SLASH_LASTMOUNT1 = "/lastmount"
    SlashCmdList["LASTMOUNT"] = function(msg)
        local cmd, rest = msg:match("^(%S+)%s*(.*)")
        if not cmd then
            if msg and strtrim(msg) ~= "" then
                PrintUsage()
            else
                Settings.OpenToCategory(optionsCategory:GetID())
            end
            return
        end

        cmd = cmd:lower()
        if cmd == "help" then
            ShowStatus()
            PrintUsage()
        elseif cmd == "fallback" then
            rest = strtrim(rest or "")
            if rest == "" then
                PrintUsage()
            elseif rest:lower() == "reset" then
                ClearFallback()
            else
                SetFallbackByName(rest)
            end
        elseif cmd == "blacklist" then
            rest = strtrim(rest or "")
            local sub, arg = rest:match("^(%S+)%s*(.*)")
            if not sub then
                PrintUsage()
                return
            end
            sub = sub:lower()
            if sub == "add" then
                AddToBlacklist(strtrim(arg or ""))
            elseif sub == "remove" then
                RemoveFromBlacklist(strtrim(arg or ""))
            elseif sub == "list" then
                ListBlacklist()
            else
                PrintUsage()
            end
        else
            PrintUsage()
        end
    end
end

---------------------------------------------------------------------------
-- Validate stored mount IDs on login
---------------------------------------------------------------------------

local function ValidateStoredMounts()
    if lastMountID then
        local name, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(lastMountID)
        if not name or not isCollected then
            lastMountID = nil
            db.lastMountID = nil
        end
    end
    if fallbackMountID then
        local name, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(fallbackMountID)
        if not name or not isCollected then
            fallbackMountID = nil
            db.fallbackMountID = nil
        end
    end
end

---------------------------------------------------------------------------
-- Options Panel
---------------------------------------------------------------------------

local optionsPanel
local RefreshPanel

local function CreateOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "LastMount"
    panel:Hide()

    local INDENT = 16
    local yOff = -16

    -- Title
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", INDENT, yOff)
    title:SetText("LastMount")
    yOff = yOff - 30

    -- Status: last mount
    local statusLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    statusLabel:SetPoint("TOPLEFT", INDENT, yOff)
    statusLabel:SetText("Last mount:")
    local statusValue = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    statusValue:SetPoint("LEFT", statusLabel, "RIGHT", 6, 0)
    yOff = yOff - 24

    -----------------------------------------------------------------------
    -- Fallback section
    -----------------------------------------------------------------------
    local fbHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fbHeader:SetPoint("TOPLEFT", INDENT, yOff)
    fbHeader:SetText("Fallback mount:")
    local fbValue = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fbValue:SetPoint("LEFT", fbHeader, "RIGHT", 6, 0)
    yOff = yOff - 26

    local fbEditBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    fbEditBox:SetPoint("TOPLEFT", INDENT, yOff)
    fbEditBox:SetSize(200, 22)
    fbEditBox:SetAutoFocus(false)

    local fbSetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    fbSetBtn:SetPoint("LEFT", fbEditBox, "RIGHT", 6, 0)
    fbSetBtn:SetSize(60, 22)
    fbSetBtn:SetText("Set")
    fbSetBtn:SetScript("OnClick", function()
        local text = fbEditBox:GetText()
        if strtrim(text) == "" then return end
        local mountID = FindMountByName(text)
        if mountID then
            fallbackMountID = mountID
            db.fallbackMountID = mountID
            fbEditBox:SetText("")
            RefreshPanel()
        else
            print("|cff00ccffLastMount|r: No collected mount found matching \"" .. text .. "\".")
        end
    end)

    local fbClearBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    fbClearBtn:SetPoint("LEFT", fbSetBtn, "RIGHT", 6, 0)
    fbClearBtn:SetSize(60, 22)
    fbClearBtn:SetText("Clear")
    fbClearBtn:SetScript("OnClick", function()
        fallbackMountID = nil
        db.fallbackMountID = nil
        RefreshPanel()
    end)

    yOff = yOff - 34

    -----------------------------------------------------------------------
    -- Blacklist section
    -----------------------------------------------------------------------
    local blHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    blHeader:SetPoint("TOPLEFT", INDENT, yOff)
    blHeader:SetText("Blacklisted Mounts")
    yOff = yOff - 24

    local blEditBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    blEditBox:SetPoint("TOPLEFT", INDENT, yOff)
    blEditBox:SetSize(200, 22)
    blEditBox:SetAutoFocus(false)

    local blAddBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    blAddBtn:SetPoint("LEFT", blEditBox, "RIGHT", 6, 0)
    blAddBtn:SetSize(60, 22)
    blAddBtn:SetText("Add")
    blAddBtn:SetScript("OnClick", function()
        local text = blEditBox:GetText()
        if strtrim(text) == "" then return end
        local mountID = FindMountByName(text)
        if mountID then
            blacklist[mountID] = true
            blEditBox:SetText("")
            RefreshPanel()
        else
            print("|cff00ccffLastMount|r: No collected mount found matching \"" .. text .. "\".")
        end
    end)

    yOff = yOff - 30

    -- Container for blacklist rows (rebuilt on refresh)
    local blListAnchor = CreateFrame("Frame", nil, panel)
    blListAnchor:SetPoint("TOPLEFT", INDENT, yOff)
    blListAnchor:SetSize(400, 1)

    -- Store references for refresh
    panel._statusValue = statusValue
    panel._fbValue = fbValue
    panel._blListAnchor = blListAnchor

    -- Frame pool for blacklist rows
    local blRowPool = {}
    local blRowPoolSize = 0

    local function AcquireRow(parent)
        for i = 1, blRowPoolSize do
            local row = blRowPool[i]
            if not row._inUse then
                row._inUse = true
                row:SetParent(parent)
                row:Show()
                return row
            end
        end
        -- Create new row
        local row = CreateFrame("Frame", nil, parent)
        row:SetSize(400, 20)
        row._nameStr = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        row._nameStr:SetPoint("LEFT", 0, 0)
        row._removeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row._removeBtn:SetPoint("LEFT", row._nameStr, "RIGHT", 8, 0)
        row._removeBtn:SetSize(70, 20)
        row._removeBtn:SetText("Remove")
        row._inUse = true
        blRowPoolSize = blRowPoolSize + 1
        blRowPool[blRowPoolSize] = row
        return row
    end

    local function ReleaseAllRows()
        for i = 1, blRowPoolSize do
            local row = blRowPool[i]
            row._inUse = false
            row:Hide()
            row:ClearAllPoints()
        end
    end

    function RefreshPanel()
        -- Status
        local lastName = GetMountName(lastMountID)
        statusValue:SetText(lastName and (lastName .. "  (ID: " .. (GetMountSpellID(lastMountID) or "?") .. ")") or "None")

        -- Fallback
        local fbName = GetMountName(fallbackMountID)
        fbValue:SetText(fbName and (fbName .. "  (ID: " .. (GetMountSpellID(fallbackMountID) or "?") .. ")") or "None")

        -- Recycle old blacklist rows
        ReleaseAllRows()

        -- Build blacklist rows (reusing pooled frames)
        local rowY = 0
        for mountID in pairs(blacklist) do
            local row = AcquireRow(blListAnchor)
            row:SetPoint("TOPLEFT", 0, rowY)

            local name = GetMountName(mountID) or "Unknown"
            row._nameStr:SetText(name .. "  (ID: " .. (GetMountSpellID(mountID) or "?") .. ")")

            row._removeBtn:SetScript("OnClick", function()
                blacklist[mountID] = nil
                RefreshPanel()
            end)

            rowY = rowY - 22
        end
    end

    panel:SetScript("OnShow", RefreshPanel)

    -- Register with modern Settings API
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)

    optionsPanel = panel
    optionsCategory = category
end

---------------------------------------------------------------------------
-- Event Handling
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loaded = ...
        if loaded == addonName then
            InitDB()
            CreateMountButton()
            CreateOptionsPanel()
            self:UnregisterEvent("ADDON_LOADED")
            self:RegisterEvent("PLAYER_LOGIN")
            self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
            pcall(self.RegisterEvent, self, "COMPANION_UPDATE")
        end
    elseif event == "PLAYER_LOGIN" then
        ValidateStoredMounts()
        RegisterSlashCommands()
    elseif event == "COMPANION_UPDATE" then
        OnCompanionUpdate()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        OnSpellcastSucceeded(...)
    end
end)

frame:RegisterEvent("ADDON_LOADED")
