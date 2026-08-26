-- Minimal FluentUI adapter (ModuleScript)
-- Place this ModuleScript into ReplicatedStorage as "FluentUI" in Roblox Studio.
-- Provides a small API surface used by Engine V14 integration:
-- Fluent.CreateWindow(opts) -> window
-- window:AddGroup(title, opts) -> group
-- group:AddToggle(label, initial, callback) -> toggleControl
-- group:AddGrid(cols) -> grid (grid:AddToggle same as AddToggle)
-- group:AddRow() -> row (row:AddToggle, row:AddButton, row:AddInput)
-- group:AddLabel(text) -> label (label:SetText)
-- Input control: returned object has SetText(text)

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local GuiService = game:GetService("GuiService")

local Fluent = {}

local function ensureGui()
    local pg = player and player:FindFirstChild("PlayerGui")
    if not pg then
        pg = player:WaitForChild("PlayerGui")
    end
    local gui = pg:FindFirstChild("FluentUI_Adapter")
    if gui and gui:IsA("ScreenGui") then return gui end
    gui = Instance.new("ScreenGui")
    gui.Name = "FluentUI_Adapter"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 9999
    gui.Parent = pg
    return gui
end

local function makeFrame(parent, size, pos)
    local f = Instance.new("Frame")
    f.Size = size or UDim2.fromOffset(360, 240)
    if pos then f.Position = pos end
    f.BackgroundColor3 = Color3.fromRGB(18,18,20)
    f.BorderSizePixel = 0
    f.Parent = parent
    local corner = Instance.new("UICorner", f)
    corner.CornerRadius = UDim.new(0,8)
    return f
end

local function makeLabel(parent, text)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -8, 0, 18)
    lbl.Position = UDim2.new(0, 4, 0, 4)
    lbl.BackgroundTransparency = 1
    lbl.Text = text or ""
    lbl.TextColor3 = Color3.fromRGB(230,230,230)
    lbl.TextSize = 14
    lbl.Font = Enum.Font.Gotham
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = parent
    function lbl:SetText(t) self.Text = tostring(t) end
    return lbl
end

function Fluent.CreateWindow(opts)
    opts = opts or {}
    local gui = ensureGui()
    local main = makeFrame(gui, UDim2.fromOffset(opts.Size and opts.Size.X or 360, opts.Size and opts.Size.Y or 240), opts.Position)

    -- Title
    local title = Instance.new("TextLabel", main)
    title.Size = UDim2.new(1, -12, 0, 28)
    title.Position = UDim2.new(0, 6, 0, 6)
    title.BackgroundTransparency = 1
    title.Text = opts.Title or "Window"
    title.TextColor3 = Color3.fromRGB(250,250,250)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 14
    title.TextXAlignment = Enum.TextXAlignment.Left

    local content = Instance.new("Frame", main)
    content.Size = UDim2.new(1, -12, 1, -40)
    content.Position = UDim2.new(0, 6, 0, 36)
    content.BackgroundTransparency = 1

    -- Simple vertical layout manager
    local layout = Instance.new("UIListLayout", content)
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 6)

    local window = {}

    function window:AddGroup(titleText, groupOpts)
        local groupFrame = Instance.new("Frame", content)
        groupFrame.Size = UDim2.new(1, 0, 0, 0)
        groupFrame.BackgroundTransparency = 1
        groupFrame.LayoutOrder = #content:GetChildren()

        local gLayout = Instance.new("UIListLayout", groupFrame)
        gLayout.FillDirection = Enum.FillDirection.Vertical
        gLayout.SortOrder = Enum.SortOrder.LayoutOrder
        gLayout.Padding = UDim.new(0, 4)

        local header = makeLabel(groupFrame, titleText or "Group")
        header.LayoutOrder = 1

        local container = Instance.new("Frame", groupFrame)
        container.BackgroundTransparency = 1
        container.Size = UDim2.new(1, 0, 0, 1)
        container.LayoutOrder = 2

        local gridLayout = Instance.new("UIGridLayout", container)
        gridLayout.CellSize = UDim2.new(0, 120, 0, 24)
        gridLayout.CellPadding = UDim2.new(0, 6, 0, 6)

        local group = {}

        function group:AddToggle(label, initial, callback)
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.fromOffset(120, 24)
            btn.BackgroundColor3 = initial and Color3.fromRGB(80,160,255) or Color3.fromRGB(35,35,38)
            btn.TextColor3 = Color3.fromRGB(240,240,240)
            btn.Text = label or "Toggle"
            btn.Font = Enum.Font.GothamBold
            btn.TextSize = 12
            btn.Parent = container
            btn:SetAttribute("state", initial == true)
            btn.MouseButton1Click:Connect(function()
                local new = not btn:GetAttribute("state")
                btn:SetAttribute("state", new)
                btn.BackgroundColor3 = new and Color3.fromRGB(80,160,255) or Color3.fromRGB(35,35,38)
                if callback then
                    pcall(callback, new)
                end
            end)
            return btn
        end

        function group:AddGrid(cols)
            -- Return an object that proxies AddToggle into this group
            local grid = {}
            function grid:AddToggle(label, initial, callback)
                return group:AddToggle(label, initial, callback)
            end
            return grid
        end

        function group:AddRow()
            local row = {}
            function row:AddToggle(label, initial, callback)
                return group:AddToggle(label, initial, callback)
            end
            function row:AddButton(label, callback)
                local b = Instance.new("TextButton")
                b.Size = UDim2.fromOffset(80, 22)
                b.BackgroundColor3 = Color3.fromRGB(60,60,64)
                b.TextColor3 = Color3.fromRGB(240,240,240)
                b.Font = Enum.Font.GothamBold
                b.TextSize = 12
                b.Text = label or "Btn"
                b.Parent = container
                b.MouseButton1Click:Connect(function() pcall(callback) end)
                return b
            end
            function row:AddInput(placeholder, text, onChange)
                local tb = Instance.new("TextBox")
                tb.Size = UDim2.fromOffset(140, 22)
                tb.PlaceholderText = placeholder or ""
                tb.Text = text or ""
                tb.BackgroundColor3 = Color3.fromRGB(28,28,30)
                tb.TextColor3 = Color3.fromRGB(240,240,240)
                tb.Font = Enum.Font.Gotham
                tb.TextSize = 12
                tb.Parent = container
                tb.ClearTextOnFocus = false
                tb.FocusLost:Connect(function()
                    if onChange then pcall(onChange, tb.Text) end
                end)
                function tb:SetText(t) tb.Text = tostring(t or "") end
                return tb
            end
            return row
        end

        function group:AddInput(placeholder, text, onChange)
            local tb = Instance.new("TextBox")
            tb.Size = UDim2.fromOffset(200, 24)
            tb.PlaceholderText = placeholder or ""
            tb.Text = text or ""
            tb.BackgroundColor3 = Color3.fromRGB(28,28,30)
            tb.TextColor3 = Color3.fromRGB(240,240,240)
            tb.Font = Enum.Font.Gotham
            tb.TextSize = 12
            tb.Parent = container
            tb.ClearTextOnFocus = false
            tb.FocusLost:Connect(function()
                if onChange then pcall(onChange, tb.Text) end
            end)
            function tb:SetText(t) tb.Text = tostring(t or "") end
            return tb
        end

        function group:AddButton(label, callback)
            local b = Instance.new("TextButton")
            b.Size = UDim2.fromOffset(80, 24)
            b.BackgroundColor3 = Color3.fromRGB(180,60,60)
            b.TextColor3 = Color3.fromRGB(250,250,250)
            b.Font = Enum.Font.GothamBold
            b.TextSize = 12
            b.Text = label or "Btn"
            b.Parent = container
            b.MouseButton1Click:Connect(function() pcall(callback) end)
            return b
        end

        function group:AddLabel(text)
            local l = Instance.new("TextLabel")
            l.Size = UDim2.fromOffset(200, 18)
            l.BackgroundTransparency = 1
            l.Text = text or ""
            l.TextColor3 = Color3.fromRGB(160,255,160)
            l.Font = Enum.Font.GothamBold
            l.TextSize = 12
            l.Parent = container
            function l:SetText(t) l.Text = tostring(t) end
            return l
        end

        return group
    end

    return window
end

return Fluent
