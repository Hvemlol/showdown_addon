local MinimapButton = {}

local ADDON_NAME = "ShowdownClone"

local button
local dragging = false

function MinimapButton:Create(onClick)
    if button then return button end
    button = CreateFrame("Button", "ShowdownCloneMinimapButton", Minimap)
    button:SetFrameStrata("MEDIUM")
    button:SetSize(32, 32)
    button:SetPoint("CENTER", Minimap, "CENTER", 0, 0)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetMovable(true)
    button:EnableMouse(true)
    button:RegisterForDrag("LeftButton")

    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.6, 0.9)

    local ring = button:CreateTexture(nil, "BORDER")
    ring:SetAllPoints()
    ring:SetColorTexture(0.9, 0.9, 0.2, 1)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Head_Dragon_01")

    -- No floating label: it overlapped the minimap ring at most angles.
    -- The tooltip (OnEnter) already says "Showdown Clone".
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER", button, "CENTER", 0, 0)
    label:SetText("SC")
    label:SetTextColor(1, 1, 1, 1)

    button:SetScript("OnDragStart", function(self)
        dragging = true
        self:StartMoving()
    end)
    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        dragging = false
        MinimapButton:SavePosition()
    end)
    button:SetScript("OnClick", function(self, btn)
        if btn == "RightButton" then
            if ShowdownClone and ShowdownClone.ToggleTeamBuilder then
                ShowdownClone.ToggleTeamBuilder()
            end
        else
            if onClick then onClick() end
        end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Showdown Clone")
        GameTooltip:AddLine("Left-click: open team builder", 1, 1, 1)
        GameTooltip:AddLine("Right-click: toggle team builder", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- position updater
    button:SetScript("OnUpdate", function(self, elapsed)
        MinimapButton:UpdatePosition(self)
    end)

    MinimapButton:RestorePosition()
    return button
end

function MinimapButton:UpdatePosition(self)
    if dragging then return end
    local db = ShowdownCloneDB and ShowdownCloneDB.minimap
    if not db then return end
    local angle = db.angle or 45
    local radius = (Minimap:GetWidth() / 2) + 6
    local x = math.cos(math.rad(angle)) * radius
    local y = math.sin(math.rad(angle)) * radius
    self:ClearAllPoints()
    self:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function MinimapButton:SavePosition()
    if not ShowdownCloneDB then ShowdownCloneDB = { minimap = {} } end
    ShowdownCloneDB.minimap = ShowdownCloneDB.minimap or {}
    local cx, cy = Minimap:GetCenter()
    local bx, by = button:GetCenter()
    local dx, dy = bx - cx, by - cy
    local angle = math.deg(math.atan2(dy, dx))
    ShowdownCloneDB.minimap.angle = angle
end

function MinimapButton:RestorePosition()
    local db = ShowdownCloneDB and ShowdownCloneDB.minimap
    if db and db.angle then
        MinimapButton:UpdatePosition(button)
    end
end

function MinimapButton:Show()
    if button then button:Show() end
end

function MinimapButton:Hide()
    if button then button:Hide() end
end

_G[ADDON_NAME .. "_MinimapButton"] = MinimapButton
return MinimapButton
