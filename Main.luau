local SITE = "https://website-nine-silk-23.vercel.app"
local DISCORD = "https://discord.gg/CfANbyhcTj"

local GAMES = {
	[13042495892] = {name = "Afternight", file = "afternight.lua"},
	[4557322431] = {name = "Afternight", file = "afternight.lua"},
}

local HttpService = game:GetService("HttpService")

local COLORS = {
	darkest = Color3.fromRGB(30, 31, 34),
	main = Color3.fromRGB(49, 51, 56),
	white = Color3.new(1, 1, 1),
	muted = Color3.fromRGB(148, 155, 164),
	blurple = Color3.fromRGB(88, 101, 242),
	green = Color3.fromRGB(35, 165, 89),
	red = Color3.fromRGB(218, 55, 60),
}

local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end

local function round(o, r)
	make("UICorner", {CornerRadius = UDim.new(0, r)}, o)
	return o
end

local function window(height)
	local old = gethui():FindFirstChild("QuasarHub")
	if old then old:Destroy() end
	local gui = make("ScreenGui", {Name = "QuasarHub", ResetOnSpawn = false, DisplayOrder = 1000}, gethui())
	local win = round(make("Frame", {
		Size = UDim2.fromOffset(360, height), Position = UDim2.new(0.5, -180, 0.5, -height / 2),
		BackgroundColor3 = COLORS.main, BorderSizePixel = 0,
	}, gui), 8)
	make("TextLabel", {
		Text = "QUASAR HUB", Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = COLORS.white, BackgroundTransparency = 1,
		Position = UDim2.fromOffset(20, 16), Size = UDim2.new(1, -40, 0, 24), TextXAlignment = Enum.TextXAlignment.Left,
	}, win)
	return gui, win
end

local function label(parent, text, y, size, color)
	return make("TextLabel", {
		Text = text, Font = Enum.Font.Gotham, TextSize = size or 13, TextColor3 = color or COLORS.muted, BackgroundTransparency = 1,
		Position = UDim2.fromOffset(20, y), Size = UDim2.new(1, -40, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
	}, parent)
end

local function button(parent, text, y, color)
	return round(make("TextButton", {
		Text = text, Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = COLORS.white, BackgroundColor3 = color or COLORS.blurple,
		BorderSizePixel = 0, AutoButtonColor = false, Position = UDim2.fromOffset(20, y), Size = UDim2.new(1, -40, 0, 36),
	}, parent), 5)
end

local function notice(message)
	local gui, win = window(170)
	label(win, message, 48, 14, COLORS.white).Size = UDim2.new(1, -40, 0, 40)
	local join = button(win, "Copy Discord invite", 108)
	join.MouseButton1Click:Connect(function()
		pcall(setclipboard, DISCORD)
		join.Text = "Invite copied"
	end)
end

local function deviceId()
	local ok, id = pcall(function()
		return game:GetService("RbxAnalyticsService"):GetClientId()
	end)
	if ok and type(id) == "string" and id ~= "" then return id end
	if type(gethwid) == "function" then
		local ok2, hw = pcall(gethwid)
		if ok2 and hw then return tostring(hw) end
	end
	return nil
end

local function checkKey(key)
	local device = deviceId()
	if not device then return false, "Could not read your device ID" end
	local url = SITE .. "/api/check?key=" .. HttpService:UrlEncode(key) .. "&hwid=" .. HttpService:UrlEncode(device)
	local ok, body = pcall(game.HttpGet, game, url)
	if not ok then return false, "Could not reach the key server" end
	local decoded, data = pcall(HttpService.JSONDecode, HttpService, body)
	if not decoded then return false, "Could not reach the key server" end
	if data.valid == true then return true end
	if data.error == "other_device" then return false, "This key is linked to another device" end
	return false, "Invalid or expired key"
end

local function trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function launch()
	setthreadidentity(8)
	local entry = GAMES[game.PlaceId] or GAMES[game.GameId]
	if not entry then
		notice("This game is not supported yet. Ask for it in the Discord.")
		return
	end
	local ok, source = pcall(readfile, entry.file)
	if not ok or type(source) ~= "string" then
		notice("The " .. entry.name .. " script file is missing from your workspace folder.")
		return
	end
	local fn, err = loadstring(source)
	if not fn then
		notice("The " .. entry.name .. " script failed to load.")
		warn("[Quasar Hub] " .. tostring(err))
		return
	end
	local gui = gethui():FindFirstChild("QuasarHub")
	if gui then gui:Destroy() end
	fn()
end

local function askForKey()
	local gui, win = window(250)
	label(win, "Enter your key to continue", 42)

	local box = round(make("TextBox", {
		Text = "", PlaceholderText = "QH-XXXX-XXXX-XXXX", PlaceholderColor3 = COLORS.muted, ClearTextOnFocus = false,
		Font = Enum.Font.Gotham, TextSize = 14, TextColor3 = COLORS.white, BackgroundColor3 = COLORS.darkest, BorderSizePixel = 0,
		Position = UDim2.fromOffset(20, 76), Size = UDim2.new(1, -40, 0, 38),
	}, win), 5)
	make("UIPadding", {PaddingLeft = UDim.new(0, 12)}, box)

	local status = label(win, "", 120, 12)
	local verify = button(win, "Verify", 146)
	local getKey = button(win, "Copy key page link", 194, COLORS.darkest)

	local busy = false
	local function submit()
		if busy then return end
		busy = true
		local key = trim(box.Text):upper()
		status.TextColor3 = COLORS.muted
		status.Text = "Checking..."
		local ok, reason = checkKey(key)
		if ok then
			pcall(writefile, KEY_FILE, key)
			status.Text = "Key accepted"
			status.TextColor3 = COLORS.green
			task.wait(0.4)
			launch()
		else
			status.Text = reason
			status.TextColor3 = COLORS.red
			busy = false
		end
	end

	verify.MouseButton1Click:Connect(submit)
	box.FocusLost:Connect(function(enter)
		if enter then submit() end
	end)
	getKey.MouseButton1Click:Connect(function()
		pcall(setclipboard, SITE .. "/getkey.html")
		getKey.Text = "Link copied"
	end)
end

local okRead, saved = pcall(readfile, KEY_FILE)
if okRead and type(saved) == "string" and checkKey(trim(saved)) then
	launch()
else
	askForKey()
end
