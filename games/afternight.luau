local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("RunService")
local RepStorage = game:GetService("ReplicatedStorage")
local lp = Players.LocalPlayer
local Conductor = require(RepStorage.Modules.Main.Conductor)
local DataManager = require(RepStorage.Modules.Data.DataManager)

local env = getgenv()
if env.__AP then pcall(env.__AP) end

local BAD_TYPES = {"death", "mine", "hurt", "fire", "warn", "kill"}
local SHOP_MAP = {
	Notesplashes = "OwnedNotesplashes", Noteskins = "OwnedNoteskins", Banners = "OwnedBanners", Tags = "OwnedTags",
	Animations = "OwnedAnimations", Emotes = "OwnedEmotes", Icons = "OwnedIconPacks", Holdsplashes = "OwnedHoldsplashes",
}

local S = {input = "mimic", human = false, noMiss = false, on = false, offset = 0, humanize = 0, skipBad = true, hit = 0, skipped = 0, strumline = nil, scanning = false, lastScan = 0, frameMs = 8}
local held, conns = {}, {}
local done = setmetatable({}, {__mode = "k"})
local lead = setmetatable({}, {__mode = "k"})
local lastPos = 0

local function keyCount()
	local sl = S.strumline
	return sl and tonumber(rawget(sl, "KeyCount")) or 0
end

local VK = {
	Space = 0x20, Semicolon = 0xBA, Comma = 0xBC, Period = 0xBE, Slash = 0xBF, Quote = 0xDE, LeftBracket = 0xDB, RightBracket = 0xDD,
	Left = 0x25, Up = 0x26, Right = 0x27, Down = 0x28,
	Zero = 0x30, One = 0x31, Two = 0x32, Three = 0x33, Four = 0x34, Five = 0x35, Six = 0x36, Seven = 0x37, Eight = 0x38, Nine = 0x39,
}

local function vkOf(key)
	if #key == 1 then return key:upper():byte() end
	return VK[key]
end

local function keyFor(lane)
	local sl = S.strumline
	if not sl then return end
	local strums = rawget(sl, "Strums")
	local dir = strums[lane] and rawget(strums[lane], "dir")
	if type(dir) ~= "string" then return end
	local name, dup = dir, 0
	for i = 0, lane - 1 do
		if strums[i] and rawget(strums[i], "dir") == dir then dup += 1 end
	end
	if dup > 0 then name = name .. (dup + 1) end
	setthreadidentity(2)
	local okData, data = pcall(DataManager.GetLocalData)
	setthreadidentity(8)
	if not okData then return end
	local binds = data.Keybinds[tostring(keyCount())]
	local key = binds and binds[name]
	if not key then return end
	return vkOf(key), key, name
end

local function gameKey(down, name)
	local handler = down and env.__AP_down or env.__AP_up
	if not handler then return end
	setthreadidentity(2)
	local ok, err = pcall(handler, name)
	setthreadidentity(8)
	if not ok then warn("[Afternight] game input: " .. tostring(err)) end
end

local function setKey(lane, down)
	local vk, key, name = keyFor(lane)
	if not vk then return end
	if S.input == "mimic" then
		setthreadidentity(8)
		if down then keypress(vk) else keyrelease(vk) end
	else
		gameKey(down, name)
	end
end

local function release(lane)
	if held[lane] then
		held[lane] = nil
		setKey(lane, false)
	end
end

local function releaseAll()
	for lane in pairs(held) do release(lane) end
end

local function isBad(n)
	if n.shouldBeHitted == false or n.hitCausesMiss == true or n.ignoreNote == true then return true end
	local t = n.noteType
	if type(t) == "string" and t ~= "" then
		t = t:lower()
		for _, w in ipairs(BAD_TYPES) do
			if t:find(w, 1, true) then return true end
		end
	end
	return false
end

local function isStrumline(t)
	local k = type(t) == "table" and rawget(t, "KeyCount")
	return type(k) == "number" and k > 0 and type(rawget(t, "UnspawnNotes")) == "table" and type(rawget(t, "Strums")) == "table"
end

local function scan()
	if S.scanning then return end
	S.scanning, S.lastScan = true, os.clock()
	if not env.__AP_searched then
		env.__AP_searched = true
		local fns = getgc(false)
		for i = 1, #fns do
			local f = fns[i]
			if type(f) == "function" and islclosure(f) then
				local line = debug.info(f, "l")
				if line == 9309 and not env.__AP_down then
					env.__AP_down = f
				elseif line == 9363 and not env.__AP_up then
					env.__AP_up = f
				elseif line == 8058 and not env.__AP_loadSong and debug.info(f, "n") == "loadSong" then
					local ok, ups = pcall(debug.getupvalues, f)
					if ok and #ups > 30 then env.__AP_loadSong = f end
				elseif not env.__AP_doMiss and debug.info(f, "a") == 3 then
					local ok, consts = pcall(debug.getconstants, f)
					if ok then
						local hasNoteMiss, hasScore = false, false
						for _, c in ipairs(consts) do
							if c == "NoteMiss" then hasNoteMiss = true end
							if c == "GetMissScore" then hasScore = true end
						end
						if hasNoteMiss and hasScore then env.__AP_doMiss = f end
					end
				end
				if env.__AP_loadSong and env.__AP_down and env.__AP_up and env.__AP_doMiss then break end
			end
			if i % 4000 == 0 then task.wait() end
		end
	end
	if env.__AP_doMiss and not env.__AP_hooked then
		env.__AP_hooked = true
		local original
		original = hookfunction(env.__AP_doMiss, function(...)
			if env.__AP_noMiss then return end
			return original(...)
		end)
	end
	local cands = {}
	if env.__AP_loadSong then
		for _, u in pairs(debug.getupvalues(env.__AP_loadSong)) do
			if isStrumline(u) then
				cands[#cands + 1] = u
			elseif type(u) == "table" then
				local _, first = next(u)
				if isStrumline(first) then
					for _, x in pairs(u) do
						if isStrumline(x) then cands[#cands + 1] = x end
					end
				end
			end
		end
	end
	local best, bestScore = nil, 0
	for _, t in ipairs(cands) do
		local score, mine = 0, false
		for _, name in ipairs({"UnspawnNotes", "Notes"}) do
			local list = rawget(t, name)
			if type(list) == "table" then
				score += #list
				if list[1] and list[1].mustPress then mine = true end
			end
		end
		if score > 0 then
			if mine then score += 1e6 end
			if score >= bestScore then best, bestScore = t, score end
		end
	end
	if best and best ~= S.strumline then
		releaseAll()
		done = setmetatable({}, {__mode = "k"})
		S.strumline = best
		S.lastNotes = os.clock()
	end
	S.scanning = false
end

local function step()
	local pos = Conductor.SongPosition
	if pos < lastPos - 800 then
		releaseAll()
		done = setmetatable({}, {__mode = "k"})
		S.strumline = nil
	end
	lastPos = pos

	for lane, rel in pairs(held) do
		if pos >= rel then release(lane) end
	end

	if not S.scanning and os.clock() - S.lastScan > 1 then task.spawn(scan) end
	local sl = S.strumline
	if not sl then return end

	local left = 0
	for _, name in ipairs({"Notes", "UnspawnNotes"}) do
		local l = rawget(sl, name)
		if type(l) == "table" then left += #l end
	end
	if left > 0 then
		S.lastNotes = os.clock()
	elseif os.clock() - (S.lastNotes or os.clock()) > 4 then
		S.strumline, S.lastNotes = nil, nil
		return
	end
	if not S.on then return end

	local n = keyCount()
	for _, listName in ipairs({"Notes", "UnspawnNotes"}) do
		local list = rawget(sl, listName)
		if type(list) == "table" then
			for _, note in ipairs(list) do
				local st = note.strumTime
				if st and not done[note] and not note.isSustain and note.mustPress ~= false then
					if note.wasHit or note.hit or note.missed or note.killed then
						done[note] = true
					elseif S.skipBad and isBad(note) then
						done[note] = true
						S.skipped += 1
					else
						local l = lead[note]
						if not l then
							l = S.offset + (S.humanize > 0 and math.random(-S.humanize, S.humanize) or 0)
							lead[note] = l
						end
						if pos + l + S.frameMs >= st then
							done[note] = true
							if pos - st < 200 then
								local lane = (note.noteData or 0) % n
								release(lane)
								setKey(lane, true)
								local stop = math.max(note.susEndTime or st, st)
								local extra = stop > st and 15 or 45
								if S.human then
									extra = stop > st and math.random(0, 45) or math.random(50, 140)
								end
								held[lane] = math.max(stop, pos) + extra
								S.hit += 1
							end
						end
					end
				end
			end
		end
	end
end

local function unlockAll()
	local data = DataManager.GetLocalData()
	local assets = RepStorage.Events.Assets.GetShopAssets:InvokeServer()
	local added, total = 0, 0
	for cat, key in pairs(SHOP_MAP) do
		local list, owned = assets[cat], data[key]
		if type(list) == "table" and type(owned) == "table" then
			local have = {}
			for _, v in pairs(owned) do have[v] = true end
			for _, item in pairs(list) do
				local name = type(item) == "table" and item.name or item
				total += 1
				if name ~= nil and not have[name] then
					have[name] = true
					table.insert(owned, name)
					added += 1
				end
			end
		end
	end
	for _, key in pairs(SHOP_MAP) do
		pcall(DataManager.triggerChange, key)
	end
	return ("Unlocked %d new items (%d in catalog)"):format(added, total)
end

local C = {
	darkest = Color3.fromRGB(30, 31, 34), side = Color3.fromRGB(43, 45, 49), main = Color3.fromRGB(49, 51, 56),
	panel = Color3.fromRGB(35, 36, 40), hover = Color3.fromRGB(64, 66, 73), text = Color3.fromRGB(219, 222, 225),
	white = Color3.fromRGB(255, 255, 255), muted = Color3.fromRGB(148, 155, 164), blurple = Color3.fromRGB(88, 101, 242),
	green = Color3.fromRGB(35, 165, 89), red = Color3.fromRGB(218, 55, 60), grey = Color3.fromRGB(128, 132, 142),
}

local gui = Instance.new("ScreenGui")
gui.Name = "AutoPlayerGUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 999
gui.Parent = gethui()

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end

local function round(o, r)
	new("UICorner", {CornerRadius = UDim.new(0, r or 8)}, o)
	return o
end

local function label(parent, text, size, color, font, pos, sz, xa)
	return new("TextLabel", {
		Text = text, TextSize = size, TextColor3 = color, Font = font or Enum.Font.Gotham, BackgroundTransparency = 1,
		Position = pos, Size = sz, TextXAlignment = xa or Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	}, parent)
end

local main = round(new("Frame", {Size = UDim2.fromOffset(560, 360), Position = UDim2.new(0.5, -280, 0.5, -180), BackgroundColor3 = C.main, BorderSizePixel = 0, ClipsDescendants = true}, gui), 8)

local bar = new("Frame", {Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = C.darkest, BorderSizePixel = 0}, main)
label(bar, "Afternight", 12, C.muted, Enum.Font.GothamMedium, UDim2.fromOffset(12, 0), UDim2.new(1, -80, 1, 0))
local closeBtn = new("TextButton", {Text = "X", TextSize = 14, Font = Enum.Font.GothamBold, TextColor3 = C.muted, BackgroundTransparency = 1, Size = UDim2.fromOffset(34, 26), Position = UDim2.new(1, -34, 0, 0)}, bar)
local minBtn = new("TextButton", {Text = "-", TextSize = 18, Font = Enum.Font.GothamBold, TextColor3 = C.muted, BackgroundTransparency = 1, Size = UDim2.fromOffset(34, 26), Position = UDim2.new(1, -68, 0, 0)}, bar)

local side = new("Frame", {Size = UDim2.new(0, 170, 1, -26), Position = UDim2.fromOffset(0, 26), BackgroundColor3 = C.side, BorderSizePixel = 0}, main)
label(side, "AFTERNIGHT", 13, C.white, Enum.Font.GothamBold, UDim2.fromOffset(14, 0), UDim2.new(1, -20, 0, 36))
new("Frame", {Size = UDim2.new(1, 0, 0, 1), Position = UDim2.fromOffset(0, 36), BackgroundColor3 = C.darkest, BorderSizePixel = 0}, side)

local holder = new("Frame", {Size = UDim2.new(1, -170, 1, -26), Position = UDim2.fromOffset(170, 26), BackgroundTransparency = 1}, main)
local header = new("Frame", {Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1}, holder)
local headerText = label(header, "# autoplayer", 14, C.white, Enum.Font.GothamBold, UDim2.fromOffset(16, 0), UDim2.new(1, -20, 1, 0))
new("Frame", {Size = UDim2.new(1, 0, 0, 1), Position = UDim2.fromOffset(0, 36), BackgroundColor3 = C.darkest, BorderSizePixel = 0}, header)

local pages, tabBtns = {}, {}

local function showPage(name)
	for n, p in pairs(pages) do p.Visible = n == name end
	for n, b in pairs(tabBtns) do
		b.BackgroundTransparency = n == name and 0 or 1
		b.TextColor3 = n == name and C.white or C.muted
	end
	headerText.Text = "# " .. name
end

local function addPage(name, y)
	local p = new("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -42), Position = UDim2.fromOffset(0, 42), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 3, ScrollBarImageColor3 = C.darkest, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false,
	}, holder)
	new("UIListLayout", {Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder}, p)
	new("UIPadding", {PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 10)}, p)
	pages[name] = p
	local b = round(new("TextButton", {
		Text = "   #  " .. name, TextSize = 14, Font = Enum.Font.GothamMedium, TextColor3 = C.muted, BackgroundColor3 = C.hover, BackgroundTransparency = 1,
		AutoButtonColor = false, Size = UDim2.new(1, -16, 0, 32), Position = UDim2.fromOffset(8, y), TextXAlignment = Enum.TextXAlignment.Left,
	}, side), 5)
	tabBtns[name] = b
	b.MouseButton1Click:Connect(function() showPage(name) end)
	return p
end

local pAuto = addPage("autoplayer", 46)
local pSet = addPage("settings", 82)
local pUnl = addPage("unlocks", 118)
local pGli = addPage("glitches", 154)

local order = 0
local function card(page, h)
	order += 1
	return round(new("Frame", {Size = UDim2.new(1, 0, 0, h), BackgroundColor3 = C.side, BorderSizePixel = 0, LayoutOrder = order}, page), 8)
end

local function switch(parent, get, set, pos)
	local b = round(new("TextButton", {Text = "", AutoButtonColor = false, Size = UDim2.fromOffset(42, 24), Position = pos, BorderSizePixel = 0}, parent), 12)
	local knob = round(new("Frame", {Size = UDim2.fromOffset(18, 18), BackgroundColor3 = C.white, BorderSizePixel = 0}, b), 9)
	local function refresh()
		local on = get()
		b.BackgroundColor3 = on and C.green or C.grey
		knob.Position = on and UDim2.fromOffset(21, 3) or UDim2.fromOffset(3, 3)
	end
	b.MouseButton1Click:Connect(function()
		set(not get())
		refresh()
	end)
	refresh()
	return refresh
end

local c1 = card(pAuto, 58)
label(c1, "Autoplay", 15, C.white, Enum.Font.GothamBold, UDim2.fromOffset(14, 8), UDim2.new(1, -90, 0, 20))
label(c1, "Hits the notes for you while a song is playing", 12, C.muted, Enum.Font.Gotham, UDim2.fromOffset(14, 30), UDim2.new(1, -90, 0, 18))
local refreshOn = switch(c1, function() return S.on end, function(v)
	S.on = v
	if not v then releaseAll() end
end, UDim2.new(1, -56, 0.5, -12))

local c3 = card(pAuto, 78)
local stText = label(c3, "", 13, C.text, Enum.Font.Gotham, UDim2.fromOffset(14, 8), UDim2.new(1, -100, 1, -16))
stText.TextWrapped = true
stText.TextYAlignment = Enum.TextYAlignment.Top
stText.TextTruncate = Enum.TextTruncate.None
local rescan = round(new("TextButton", {
	Text = "Rescan", Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = C.white, BackgroundColor3 = C.blurple, BorderSizePixel = 0,
	AutoButtonColor = false, Size = UDim2.fromOffset(66, 28), Position = UDim2.new(1, -80, 0.5, -14),
}, c3), 5)
rescan.MouseButton1Click:Connect(function()
	releaseAll()
	S.strumline = nil
	S.lastScan = 0
end)

local function slider(page, title, sub, get, set, lo, hi, suffix)
	local f = card(page, 78)
	label(f, title, 14, C.white, Enum.Font.GothamBold, UDim2.fromOffset(14, 8), UDim2.new(1, -110, 0, 20))
	label(f, sub, 12, C.muted, Enum.Font.Gotham, UDim2.fromOffset(14, 28), UDim2.new(1, -28, 0, 16))
	local val = label(f, "", 14, C.white, Enum.Font.GothamBold, UDim2.new(1, -94, 0, 8), UDim2.fromOffset(80, 20), Enum.TextXAlignment.Right)
	local track = round(new("Frame", {Size = UDim2.new(1, -28, 0, 8), Position = UDim2.new(0, 14, 1, -22), BackgroundColor3 = C.darkest, BorderSizePixel = 0}, f), 4)
	local fill = round(new("Frame", {Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = C.blurple, BorderSizePixel = 0}, track), 4)
	local knob = round(new("Frame", {Size = UDim2.fromOffset(16, 16), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 0), BackgroundColor3 = C.white, BorderSizePixel = 0}, track), 8)
	local grab = new("TextButton", {Text = "", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), Position = UDim2.new(0, 0, 0.5, -14)}, track)
	local function render()
		local a = (get() - lo) / (hi - lo)
		fill.Size = UDim2.new(a, 0, 1, 0)
		knob.Position = UDim2.new(a, 0, 0.5, 0)
		val.Text = get() .. suffix
	end
	local dragging = false
	local function fromX(x)
		local a = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		set(math.clamp(math.floor(lo + (hi - lo) * a + 0.5), lo, hi))
		render()
	end
	grab.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			fromX(i.Position.X)
		end
	end)
	conns[#conns + 1] = UIS.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			fromX(i.Position.X)
		end
	end)
	conns[#conns + 1] = UIS.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
	end)
	render()
end

local cIn = card(pSet, 84)
label(cIn, "Input mode", 14, C.white, Enum.Font.GothamBold, UDim2.fromOffset(14, 8), UDim2.new(1, -28, 0, 20))
label(cIn, "Mimic presses your real keys. In-game sends input straight to the game.", 12, C.muted, Enum.Font.Gotham, UDim2.fromOffset(14, 28), UDim2.new(1, -28, 0, 16))
local modeBtns = {}
local function refreshMode()
	for m, b in pairs(modeBtns) do
		b.BackgroundColor3 = m == S.input and C.blurple or C.darkest
		b.TextColor3 = m == S.input and C.white or C.muted
	end
end
for i, m in ipairs({{"mimic", "Mimic keyboard"}, {"ingame", "In-game input"}}) do
	local b = round(new("TextButton", {
		Text = m[2], Font = Enum.Font.GothamMedium, TextSize = 13, BorderSizePixel = 0, AutoButtonColor = false,
		Size = UDim2.new(0.5, -20, 0, 30), Position = UDim2.new(i == 1 and 0 or 0.5, i == 1 and 14 or 6, 0, 46),
	}, cIn), 5)
	modeBtns[m[1]] = b
	b.MouseButton1Click:Connect(function()
		releaseAll()
		S.input = m[1]
		refreshMode()
	end)
end
refreshMode()

slider(pSet, "Hit offset", "Shift hit timing earlier (-) or later (+)", function() return S.offset end, function(v) S.offset = v end, -80, 80, " ms")
slider(pSet, "Humanize", "Random timing variation on each note", function() return S.humanize end, function(v) S.humanize = v end, 0, 40, " ms")

local cHuman = card(pSet, 58)
label(cHuman, "Human clicker", 14, C.white, Enum.Font.GothamBold, UDim2.fromOffset(14, 8), UDim2.new(1, -90, 0, 20))
label(cHuman, "Releases each key after a random time, like a real player", 12, C.muted, Enum.Font.Gotham, UDim2.fromOffset(14, 30), UDim2.new(1, -90, 0, 18))
switch(cHuman, function() return S.human end, function(v) S.human = v end, UDim2.new(1, -56, 0.5, -12))

local c4 = card(pSet, 58)
label(c4, "Skip death notes", 14, C.white, Enum.Font.GothamBold, UDim2.fromOffset(14, 8), UDim2.new(1, -90, 0, 20))
label(c4, "Never presses notes the game flags as harmful", 12, C.muted, Enum.Font.Gotham, UDim2.fromOffset(14, 30), UDim2.new(1, -90, 0, 18))
switch(c4, function() return S.skipBad end, function(v) S.skipBad = v end, UDim2.new(1, -56, 0.5, -12))

local cMiss = card(pGli, 58)
label(cMiss, "No miss", 14, C.white, Enum.Font.GothamBold, UDim2.fromOffset(14, 8), UDim2.new(1, -90, 0, 20))
label(cMiss, "Misses never count: no score loss, combo break or health loss", 12, C.muted, Enum.Font.Gotham, UDim2.fromOffset(14, 30), UDim2.new(1, -90, 0, 18))
switch(cMiss, function() return S.noMiss end, function(v)
	S.noMiss = v
	env.__AP_noMiss = v
end, UDim2.new(1, -56, 0.5, -12))

local c5 = card(pUnl, 96)
label(c5, "Unlock All (client-side)", 14, C.white, Enum.Font.GothamBold, UDim2.fromOffset(14, 8), UDim2.new(1, -28, 0, 20))
local unlInfo = label(c5, "Unlocks items in your own game view only. The server still decides what you really own.", 12, C.muted, Enum.Font.Gotham, UDim2.fromOffset(14, 28), UDim2.new(1, -28, 0, 32))
unlInfo.TextWrapped = true
unlInfo.TextYAlignment = Enum.TextYAlignment.Top
unlInfo.TextTruncate = Enum.TextTruncate.None
local unlBtn = round(new("TextButton", {
	Text = "Unlock All", Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C.white, BackgroundColor3 = C.blurple, BorderSizePixel = 0,
	AutoButtonColor = false, Size = UDim2.fromOffset(110, 28), Position = UDim2.fromOffset(14, 60),
}, c5), 5)
local unlStatus = label(c5, "", 12, C.muted, Enum.Font.Gotham, UDim2.fromOffset(134, 60), UDim2.new(1, -148, 0, 28))
unlBtn.MouseButton1Click:Connect(function()
	unlStatus.Text = "Working..."
	task.spawn(function()
		local ok, res = pcall(unlockAll)
		unlStatus.Text = ok and res or ("Error: " .. tostring(res))
	end)
end)

local user = new("Frame", {Size = UDim2.new(1, 0, 0, 52), Position = UDim2.new(0, 0, 1, -52), BackgroundColor3 = C.panel, BorderSizePixel = 0}, side)
local avatar = round(new("ImageLabel", {Size = UDim2.fromOffset(32, 32), Position = UDim2.fromOffset(10, 10), BackgroundColor3 = C.darkest, BorderSizePixel = 0}, user), 16)
task.spawn(function()
	local ok, img = pcall(Players.GetUserThumbnailAsync, Players, lp.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
	if ok then avatar.Image = img end
end)
local dotRing = round(new("Frame", {Size = UDim2.fromOffset(14, 14), Position = UDim2.fromOffset(31, 31), BackgroundColor3 = C.panel, BorderSizePixel = 0}, user), 7)
local dot = round(new("Frame", {Size = UDim2.fromOffset(10, 10), Position = UDim2.fromOffset(2, 2), BackgroundColor3 = C.grey, BorderSizePixel = 0}, dotRing), 5)
label(user, lp.DisplayName, 13, C.white, Enum.Font.GothamBold, UDim2.fromOffset(52, 8), UDim2.new(1, -58, 0, 18))
local userSub = label(user, "Autoplay off", 11, C.muted, Enum.Font.Gotham, UDim2.fromOffset(52, 26), UDim2.new(1, -58, 0, 16))

local dragging, startPos, startMouse
bar.InputBegan:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
		dragging, startPos, startMouse = true, main.Position, i.Position
	end
end)
conns[#conns + 1] = UIS.InputChanged:Connect(function(i)
	if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
		local d = i.Position - startMouse
		main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
	end
end)
conns[#conns + 1] = UIS.InputEnded:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
end)
conns[#conns + 1] = UIS.InputBegan:Connect(function(i)
	if i.KeyCode == Enum.KeyCode.RightShift then main.Visible = not main.Visible end
end)

local minimized = false
minBtn.MouseButton1Click:Connect(function()
	minimized = not minimized
	main.Size = minimized and UDim2.fromOffset(560, 26) or UDim2.fromOffset(560, 360)
end)

local function destroy()
	S.on = false
	env.__AP_noMiss = false
	releaseAll()
	for _, c in ipairs(conns) do c:Disconnect() end
	gui:Destroy()
	env.__AP = nil
end
env.__AP = destroy
closeBtn.MouseButton1Click:Connect(destroy)

local warned = {}
local function guard(tag, f)
	setthreadidentity(8)
	local ok, err = pcall(f)
	if not ok and not warned[tag] then
		warned[tag] = true
		warn("[Afternight] " .. tag .. ": " .. tostring(err))
	end
end

local function updateStatus()
	env.__AP_noMiss = S.noMiss
	local n, keys = 0, {}
	guard("keycount", function() n = keyCount() end)
	guard("keys", function()
		for lane = 0, n - 1 do
			local _, k = keyFor(lane)
			keys[#keys + 1] = k or "?"
		end
	end)
	guard("text", function()
		stText.Text = string.format("%s  •  %dK\nKeys: %s\nHit %d   •   Skipped %d",
			S.strumline and "Song found" or (S.scanning and "Scanning..." or "No song found"),
			n, table.concat(keys, " "), S.hit, S.skipped)
	end)
	guard("dot", function() dot.BackgroundColor3 = S.on and C.green or C.grey end)
	guard("sub", function() userSub.Text = S.on and "Autoplay on" or "Autoplay off" end)
	guard("switch", refreshOn)
end

local lastStatus = 0
conns[#conns + 1] = RS.Heartbeat:Connect(function(dt)
	setthreadidentity(8)
	S.frameMs = math.clamp(dt * 500, 2, 25)
	guard("step", step)
	if os.clock() - lastStatus > 0.25 then
		lastStatus = os.clock()
		updateStatus()
	end
end)

showPage("autoplayer")
task.spawn(scan)