-- ProgressionClient (LocalScript en StarterGui.ProgressionUI)
-- Panel de progreso SOLO para el lobby (menu principal abierto):
--   perfil (rango, nivel, XP), monedas y racha, bono de primera victoria,
--   misiones diarias / semanales en pestanas y resumen de la ultima pelea.
-- Los datos los manda el servidor (ProgressionService); aqui solo se muestran.

local LOBBY_ONLY = true -- true: el panel solo existe con el menu principal (lobby) abierto

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local gui = script.Parent
gui.ResetOnSpawn = false
gui.DisplayOrder = 55 -- sobre el menu (50); bajo el HUD de ronda (54+), combate (58) y partida (60)
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local Shared = require(ReplicatedStorage:WaitForChild("ProgressionShared"))
local updateEvent = ReplicatedStorage:WaitForChild("UpdateProgression")
local notifyEvent = ReplicatedStorage:WaitForChild("MissionNotify")
local requestEvent = ReplicatedStorage:WaitForChild("RequestProgression", 30)
local menu = player:WaitForChild("PlayerGui"):WaitForChild("MainMenu", 30)

-- ===== Estilo =====
local C = {
	bg = Color3.fromRGB(22, 26, 21),
	card = Color3.fromRGB(34, 40, 32),
	track = Color3.fromRGB(12, 15, 12),
	gold = Color3.fromRGB(240, 200, 90),
	green = Color3.fromRGB(110, 220, 120),
	text = Color3.fromRGB(240, 236, 220),
	dim = Color3.fromRGB(160, 160, 140),
	xp = Color3.fromRGB(90, 170, 255),
	red = Color3.fromRGB(235, 90, 80),
}
local FONT_B, FONT = Enum.Font.GothamBold, Enum.Font.Gotham
local COIN, FIRE, HOURGLASS = "\u{1F4B0}", "\u{1F525}", "\u{23F3}"
local CHECK, TROPHY, OKBOX, WARN, DOT, STAR = "\u{2713}", "\u{1F3C6}", "\u{2705}", "\u{26A0}", "\u{00B7}", "\u{2B50}"
local QUAD_OUT = Enum.EasingStyle.Quad
local WIDTH = 280

-- La columna vive aqui para siempre. Antes se ancla a la izquierda O a la derecha segun
-- el hueco que dejara el menu, y como el menu esta centrado y sus submenus son anchos, al
-- abrir el selector de modo o la tienda la columna saltaba al lado derecho y luego volvia:
-- se veia fatal y ademas tapaba el menu. Ahora no hay eleccion, siempre a la izquierda, y lo
-- que se aparta es el menu (ver refreshDock).
local DOCK_LEFT = UDim2.new(0, 12, 0, 64)

local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	if parent then
		o.Parent = parent
	end
	return o
end
local function corner(o, r)
	return make("UICorner", { CornerRadius = UDim.new(0, r) }, o)
end
local function stroke(o, color, thick, transp)
	return make("UIStroke", { Color = color, Thickness = thick, Transparency = transp, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, o)
end
local function label(parent, props)
	local base = {
		BackgroundTransparency = 1, Font = FONT, TextColor3 = C.text, TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center, Text = "",
	}
	for k, v in pairs(props) do
		base[k] = v
	end
	return make("TextLabel", base, parent)
end
local function fmt(n)
	local s = tostring(math.floor(n))
	local r = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (r:gsub("^,", ""))
end
local function fmtTime(sec)
	sec = math.max(0, math.floor(sec))
	if sec >= 86400 then
		return string.format("%dd %02dh", sec // 86400, (sec % 86400) // 3600)
	end
	return string.format("%02d:%02d:%02d", sec // 3600, (sec % 3600) // 60, sec % 60)
end

-- ===== Columna izquierda (todo el panel vive aqui) =====
local column = make("Frame", {
	Name = "Column", Position = UDim2.new(0, 12, 0, 64), Size = UDim2.new(0, WIDTH, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
}, gui)
make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, column)
local uiScale = make("UIScale", {}, column)

local function newCard(name, order, accent)
	local f = make("Frame", {
		Name = name, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.bg, BackgroundTransparency = 0.1, BorderSizePixel = 0, LayoutOrder = order,
	}, column)
	corner(f, 14)
	stroke(f, accent or C.gold, 1.5, 0.55)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
	}, f)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, f)
	return f
end

-- ===== 1) Perfil: rango, nivel, XP, monedas y racha =====
local profile = newCard("Profile", 1)

local header = make("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, 50), BackgroundTransparency = 1, LayoutOrder = 1 }, profile)
local badge = make("Frame", { Name = "Badge", Size = UDim2.new(0, 46, 0, 46), BackgroundColor3 = C.gold, BorderSizePixel = 0 }, header)
corner(badge, 23)
stroke(badge, Color3.fromRGB(255, 240, 180), 2, 0.2)
local badgeText = label(badge, {
	Size = UDim2.new(1, 0, 1, 0), Font = FONT_B, TextSize = 22, TextColor3 = Color3.fromRGB(40, 30, 10),
	TextXAlignment = Enum.TextXAlignment.Center, Text = "1",
})
local levelTitle = label(header, {
	Position = UDim2.new(0, 56, 0, 0), Size = UDim2.new(1, -90, 0, 22), Font = FONT_B, TextSize = 16, RichText = true, Text = "Nivel 1",
})
local toggle = make("TextButton", {
	Name = "Toggle", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0, 24, 0, 24),
	BackgroundColor3 = C.card, BorderSizePixel = 0, Font = FONT_B, TextSize = 16, TextColor3 = C.dim, Text = "-",
}, header)
corner(toggle, 8)
local xpBar = make("Frame", {
	Name = "XPBar", Position = UDim2.new(0, 56, 0, 28), Size = UDim2.new(1, -56, 0, 18),
	BackgroundColor3 = C.track, BorderSizePixel = 0, ClipsDescendants = true,
}, header)
corner(xpBar, 9)
local xpFill = make("Frame", { Name = "Fill", Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = C.xp, BorderSizePixel = 0 }, xpBar)
corner(xpFill, 9)
local xpText = label(xpBar, {
	Size = UDim2.new(1, 0, 1, 0), Font = FONT_B, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center,
	Text = "0 / 100 XP", ZIndex = 2,
})

local coinsRow = make("Frame", { Name = "CoinsRow", Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = C.card, BorderSizePixel = 0, LayoutOrder = 2 }, profile)
corner(coinsRow, 8)
local coinsLabel = label(coinsRow, {
	Position = UDim2.new(0, 10, 0, 0), Size = UDim2.new(1, -90, 1, 0), Font = FONT_B, TextSize = 16,
	TextColor3 = C.gold, Text = COIN .. " 0",
})
local streakChip = make("TextLabel", {
	Name = "Streak", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.new(0, 74, 0, 22),
	BackgroundColor3 = Color3.fromRGB(200, 100, 40), BorderSizePixel = 0, Font = FONT_B, TextSize = 12,
	TextColor3 = Color3.new(1, 1, 1), Text = FIRE .. " x2", Visible = false,
}, coinsRow)
corner(streakChip, 11)

-- ===== 2) Bono de primera victoria del dia =====
local firstWinBanner = make("Frame", {
	Name = "FirstWin", Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = Color3.fromRGB(60, 50, 22),
	BackgroundTransparency = 0.05, BorderSizePixel = 0, LayoutOrder = 2, Visible = false,
}, column)
corner(firstWinBanner, 10)
stroke(firstWinBanner, C.gold, 1.5, 0.35)
local firstWinText = label(firstWinBanner, {
	Position = UDim2.new(0, 10, 0, 0), Size = UDim2.new(1, -20, 1, 0), Font = FONT_B, TextSize = 12,
	TextColor3 = C.gold, TextWrapped = true, Text = "",
})

-- ===== 3) Misiones (pestanas Diarias / Semanales) =====
local missionsCard = newCard("Missions", 3)

local tabsRow = make("Frame", { Name = "Tabs", Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 1 }, missionsCard)
local function newTab(name, x, w)
	local b = make("TextButton", {
		Name = name, Position = UDim2.new(x, x == 0 and 0 or 3, 0, 0), Size = UDim2.new(w, -3, 1, 0),
		BackgroundColor3 = C.card, BorderSizePixel = 0, Font = FONT_B, TextSize = 13, TextColor3 = C.dim, Text = "", AutoButtonColor = false,
	}, tabsRow)
	corner(b, 8)
	return b
end
local tabDaily = newTab("Daily", 0, 0.5)
local tabWeekly = newTab("Weekly", 0.5, 0.5)

local infoRow = make("Frame", { Name = "Info", Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, LayoutOrder = 2 }, missionsCard)
local infoTitle = label(infoRow, { Size = UDim2.new(0.5, 0, 1, 0), Font = FONT_B, TextSize = 12, TextColor3 = C.dim, Text = "MISIONES DIARIAS" })
local resetLabel = label(infoRow, {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0.5, 0, 1, 0), TextSize = 12,
	TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Right, Text = HOURGLASS .. " --:--:--",
})

local dailyList = make("Frame", { Name = "DailyList", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 3 }, missionsCard)
make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, dailyList)
local weeklyList = make("Frame", { Name = "WeeklyList", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 3, Visible = false }, missionsCard)
make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, weeklyList)
local bonusLabel = label(missionsCard, { Name = "Bonus", Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 4, TextSize = 12, TextColor3 = C.dim, TextWrapped = true, Text = "" })

local rowStore = { daily = {}, weekly = {} }
local function getRow(kind, listFrame, m, order)
	local rows = rowStore[kind]
	local r = rows[m.id]
	if r then
		r.frame.LayoutOrder = order
		return r
	end
	local f = make("Frame", { Name = "Mission_" .. m.id, Size = UDim2.new(1, 0, 0, 50), BackgroundColor3 = C.card, BorderSizePixel = 0, LayoutOrder = order }, listFrame)
	corner(f, 8)
	local title = label(f, { Position = UDim2.new(0, 8, 0, 4), Size = UDim2.new(1, -16, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd, Text = m.label })
	local bar = make("Frame", { Position = UDim2.new(0, 8, 0, 31), Size = UDim2.new(1, -118, 0, 8), BackgroundColor3 = C.track, BorderSizePixel = 0, ClipsDescendants = true }, f)
	corner(bar, 4)
	local fill = make("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = C.xp, BorderSizePixel = 0 }, bar)
	corner(fill, 4)
	local count = label(f, {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 25), Size = UDim2.new(0, 104, 0, 20),
		Font = FONT_B, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right, Text = "",
	})
	r = { frame = f, title = title, count = count, fill = fill }
	rows[m.id] = r
	return r
end

-- ===== 4) Ultima pelea =====
local lastCard = newCard("LastFight", 4)
lastCard.Visible = false
label(lastCard, { Name = "Caption", Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 1, Font = FONT_B, TextSize = 11, TextColor3 = C.dim, Text = "\u{00DA}LTIMA PELEA" })
local lastTitle = label(lastCard, { Name = "Title", Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 2, Font = FONT_B, TextSize = 15, Text = "" })
local lastDetail = label(lastCard, { Name = "Detail", Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 3, TextSize = 13, TextColor3 = C.text, Text = "" })

-- ===== 5) Estado de guardado y avisos =====
local statusLabel = label(column, { Name = "Status", Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 5, TextSize = 12, TextColor3 = C.red, Text = "", Visible = false })
local toastHolder = make("Frame", { Name = "Toasts", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 6 }, column)
make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, toastHolder)

lastDetail.TextWrapped = true
lastDetail.AutomaticSize = Enum.AutomaticSize.Y

-- ============================================================
-- Estado y disposicion
-- ============================================================
local state = {
	tab = "daily",
	userCollapsed = false, -- el jugador plegó el panel con el boton -/+
	subOpen = false,       -- el menu tiene abierta la tienda / codigos / modos
	inLobby = false,
	snap = nil,
	firstWin = false,
	lastFight = nil,
	unsaved = false,
	dock = DOCK_LEFT, -- lado de la pantalla en el que esta anclada la columna
}

local function applyLayout()
	local compact = state.userCollapsed or state.subOpen
	missionsCard.Visible = not compact
	firstWinBanner.Visible = (not compact) and state.firstWin
	lastCard.Visible = (not compact) and state.lastFight ~= nil
	toggle.Text = state.userCollapsed and "+" or "-"
end

toggle.MouseButton1Click:Connect(function()
	state.userCollapsed = not state.userCollapsed
	applyLayout()
end)

-- Escala segun el tamano de pantalla (movil / escritorio)
local camera = workspace.CurrentCamera
local baseScale = 1
local refreshDock -- se define mas abajo
local function updateScale()
	baseScale = math.clamp(camera.ViewportSize.Y / 800, 0.85, 1.15)
	uiScale.Scale = baseScale
	if refreshDock then
		refreshDock()
	end
end
updateScale()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)

-- ============================================================
-- Monedas (contador animado) y barra de XP
-- ============================================================
local coinsValue = make("NumberValue", { Value = 0 }, script)
coinsValue.Changed:Connect(function(v)
	coinsLabel.Text = COIN .. " " .. fmt(v)
end)
local lastCoins = nil
local function setCoins(target)
	if lastCoins == nil then
		coinsValue.Value = target
	else
		TweenService:Create(coinsValue, TweenInfo.new(0.6, QUAD_OUT), { Value = target }):Play()
		if target > lastCoins then
			coinsLabel.TextColor3 = C.green
			TweenService:Create(coinsLabel, TweenInfo.new(0.9), { TextColor3 = C.gold }):Play()
		end
	end
	lastCoins = target
end

local displayedLevel = nil
local barToken = 0
local function setXPBar(s)
	local ratio = (s.level >= s.maxLevel) and 1 or math.clamp(s.xp / math.max(1, s.xpReq), 0, 1)
	barToken += 1
	local my = barToken
	if displayedLevel == nil or s.level < displayedLevel then
		xpFill.Size = UDim2.new(ratio, 0, 1, 0)
	elseif s.level > displayedLevel then
		TweenService:Create(xpFill, TweenInfo.new(0.3, QUAD_OUT), { Size = UDim2.new(1, 0, 1, 0) }):Play()
		task.delay(0.4, function()
			if barToken ~= my then
				return
			end
			xpFill.Size = UDim2.new(0, 0, 1, 0)
			TweenService:Create(xpFill, TweenInfo.new(0.4, QUAD_OUT), { Size = UDim2.new(ratio, 0, 1, 0) }):Play()
		end)
	else
		TweenService:Create(xpFill, TweenInfo.new(0.4, QUAD_OUT), { Size = UDim2.new(ratio, 0, 1, 0) }):Play()
	end
	displayedLevel = s.level
end

-- ============================================================
-- Estado de guardado
-- ============================================================
local statusToken = 0
local function setStatus(text, color, persistent)
	statusToken += 1
	local my = statusToken
	statusLabel.Text = text
	statusLabel.TextColor3 = color
	statusLabel.Visible = text ~= ""
	if text ~= "" and not persistent then
		task.delay(2.5, function()
			if statusToken == my then
				statusLabel.Visible = false
			end
		end)
	end
end

-- ============================================================
-- Misiones y pestanas
-- ============================================================
local function applyMissionList(kind, listFrame, missions)
	local keep = {}
	for i, m in ipairs(missions or {}) do
		keep[m.id] = true
		local r = getRow(kind, listFrame, m, i)
		r.title.Text = (m.done and (CHECK .. " ") or "") .. m.label
		r.title.TextColor3 = m.done and C.green or C.text
		if m.done then
			r.count.Text = CHECK .. " +" .. m.reward .. COIN
			r.count.TextColor3 = C.green
		else
			r.count.Text = m.progress .. "/" .. m.goal .. " " .. DOT .. " +" .. m.reward .. COIN
			r.count.TextColor3 = C.gold
		end
		r.fill.BackgroundColor3 = m.done and C.green or C.xp
		TweenService:Create(r.fill, TweenInfo.new(0.35, QUAD_OUT), { Size = UDim2.new(math.clamp(m.progress / math.max(1, m.goal), 0, 1), 0, 1, 0) }):Play()
	end
	-- la mision diaria rotativa cambia cada dia: se quitan las filas que ya no existen
	for id, r in pairs(rowStore[kind]) do
		if not keep[id] then
			r.frame:Destroy()
			rowStore[kind][id] = nil
		end
	end
end

local function countDone(list)
	local n = 0
	for _, m in ipairs(list or {}) do
		if m.done then
			n += 1
		end
	end
	return n
end

local function styleTabs()
	local s = state.snap
	local daily = s and s.missions or {}
	local weekly = (s and s.weekly and s.weekly.missions) or {}
	local function style(btn, active, text)
		btn.Text = text
		btn.BackgroundColor3 = active and C.gold or C.card
		btn.TextColor3 = active and Color3.fromRGB(40, 30, 10) or C.dim
	end
	style(tabDaily, state.tab == "daily", string.format("Diarias %d/%d", countDone(daily), #daily))
	style(tabWeekly, state.tab == "weekly", string.format("Semanales %d/%d", countDone(weekly), #weekly))
	dailyList.Visible = state.tab == "daily"
	weeklyList.Visible = state.tab == "weekly"
	infoTitle.Text = state.tab == "daily" and "MISIONES DIARIAS" or "MISIONES SEMANALES"

	local bonus, done, word
	if state.tab == "daily" then
		bonus, done, word = s and s.bonus or 0, s and s.bonusDone, "todas las diarias"
	else
		bonus, done = s and s.weekly and s.weekly.bonus or 0, s and s.weekly and s.weekly.bonusDone
		word = "todas las semanales"
	end
	if done then
		bonusLabel.Text = TROPHY .. " Bonus reclamado (+" .. bonus .. COIN .. ")"
		bonusLabel.TextColor3 = C.green
	else
		bonusLabel.Text = "Completa " .. word .. ": +" .. bonus .. COIN .. " extra"
		bonusLabel.TextColor3 = C.dim
	end
end

tabDaily.MouseButton1Click:Connect(function()
	state.tab = "daily"
	styleTabs()
end)
tabWeekly.MouseButton1Click:Connect(function()
	state.tab = "weekly"
	styleTabs()
end)

-- ============================================================
-- Aplicar el estado recibido del servidor
-- ============================================================
local gotSnapshot = false
local resetDailyAt, resetWeeklyAt = os.clock() + 86400, os.clock() + 604800

local function applySnapshot(s)
	gotSnapshot = true
	state.snap = s
	local rank = Shared.Ranks[s.rank or Shared.RankIndex(s.level)] or Shared.Ranks[1]
	local maxed = s.level >= s.maxLevel

	badge.BackgroundColor3 = rank.color
	badgeText.Text = tostring(s.level)
	levelTitle.Text = string.format('Nivel %d  <font color="#%s">%s</font>', s.level, rank.color:ToHex(), rank.name)
	xpText.Text = maxed and "NIVEL M\u{00C1}XIMO" or (fmt(s.xp) .. " / " .. fmt(s.xpReq) .. " XP")
	setXPBar(s)
	setCoins(s.coins)

	streakChip.Visible = (s.streak or 0) >= 2
	streakChip.Text = FIRE .. " x" .. tostring(s.streak or 0)

	state.firstWin = s.firstWin ~= nil and s.firstWin.available == true
	if state.firstWin then
		firstWinText.Text = string.format("%s Primera victoria del d\u{00ED}a: +%d XP %s +%d %s", STAR, s.firstWin.xp, DOT, s.firstWin.coins, COIN)
	end

	applyMissionList("daily", dailyList, s.missions)
	applyMissionList("weekly", weeklyList, s.weekly and s.weekly.missions)
	resetDailyAt = os.clock() + (s.resetIn or 0)
	resetWeeklyAt = os.clock() + ((s.weekly and s.weekly.resetIn) or 0)

	if s.unsaved then
		state.unsaved = true
		setStatus(WARN .. " Progreso sin guardar", C.red, true)
	elseif state.unsaved then
		state.unsaved = false
		statusLabel.Visible = false
	end

	styleTabs()
	applyLayout()
end
updateEvent.OnClientEvent:Connect(applySnapshot)

-- Cuenta atras hasta el reinicio de la pestana abierta
local lastAutoRequest = 0
task.spawn(function()
	while gui.Parent do
		local at = state.tab == "daily" and resetDailyAt or resetWeeklyAt
		local remain = math.max(0, at - os.clock())
		resetLabel.Text = HOURGLASS .. " " .. fmtTime(remain)
		if resetDailyAt - os.clock() <= 0 and requestEvent and os.clock() - lastAutoRequest > 5 then
			lastAutoRequest = os.clock()
			requestEvent:FireServer()
		end
		task.wait(1)
	end
end)

-- ============================================================
-- Ultima pelea
-- ============================================================
local function setLastFight(r)
	state.lastFight = r
	if r.win then
		lastTitle.Text = TROPHY .. " Victoria"
		lastTitle.TextColor3 = C.gold
	else
		lastTitle.Text = "Derrota"
		lastTitle.TextColor3 = C.dim
	end
	local parts = {}
	if (r.xp or 0) > 0 then
		table.insert(parts, "+" .. r.xp .. " XP")
	end
	table.insert(parts, "+" .. (r.coins or 0) .. " " .. COIN)
	if (r.points or 0) > 0 then
		table.insert(parts, r.points .. " pts")
	end
	if r.win and (r.streak or 0) >= 2 then
		table.insert(parts, FIRE .. " x" .. r.streak)
	end
	if r.firstWin then
		table.insert(parts, STAR .. " 1\u{00AA}")
	end
	lastDetail.Text = table.concat(parts, "  " .. DOT .. "  ")
	applyLayout()
	lastCard.BackgroundColor3 = Color3.fromRGB(70, 62, 28)
	TweenService:Create(lastCard, TweenInfo.new(1.2), { BackgroundColor3 = C.bg }):Play()
end

-- ============================================================
-- Avisos (toasts) y banner de nivel
-- ============================================================
local toastOrder = 0
local function toast(title, subtitle, color, duration)
	toastOrder += 1
	local existing = {}
	for _, c in ipairs(toastHolder:GetChildren()) do
		if c:IsA("CanvasGroup") then
			table.insert(existing, c)
		end
	end
	if #existing >= 3 then
		existing[1]:Destroy()
	end
	local tall = subtitle ~= nil or #title > 30
	local f = make("CanvasGroup", {
		Size = UDim2.new(1, 0, 0, tall and 52 or 36), BackgroundColor3 = C.bg, BackgroundTransparency = 0.05,
		BorderSizePixel = 0, GroupTransparency = 1, LayoutOrder = toastOrder,
	}, toastHolder)
	corner(f, 10)
	stroke(f, color, 1.5, 0.3)
	if subtitle then
		label(f, { Position = UDim2.new(0, 12, 0, 6), Size = UDim2.new(1, -24, 0, 22), Font = FONT_B, TextSize = 14, TextColor3 = color, TextTruncate = Enum.TextTruncate.AtEnd, Text = title })
		label(f, { Position = UDim2.new(0, 12, 0, 28), Size = UDim2.new(1, -24, 0, 18), TextSize = 13, TextTruncate = Enum.TextTruncate.AtEnd, Text = subtitle })
	else
		label(f, { Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(1, -24, 1, 0), Font = FONT_B, TextSize = 13, TextColor3 = color, TextWrapped = true, Text = title })
	end
	TweenService:Create(f, TweenInfo.new(0.25), { GroupTransparency = 0 }):Play()
	task.delay(duration or 4, function()
		if f.Parent then
			TweenService:Create(f, TweenInfo.new(0.4), { GroupTransparency = 1 }):Play()
			task.delay(0.45, function()
				if f.Parent then
					f:Destroy()
				end
			end)
		end
	end)
end

local banner = make("CanvasGroup", {
	Name = "LevelUpBanner", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.28, 0), Size = UDim2.new(0, 400, 0, 130),
	BackgroundColor3 = C.bg, BackgroundTransparency = 0.05, BorderSizePixel = 0, GroupTransparency = 1, Visible = false,
}, gui)
corner(banner, 18)
stroke(banner, C.gold, 3, 0.1)
local bannerScale = make("UIScale", { Scale = 0.6 }, banner)
local bannerTitle = label(banner, { Position = UDim2.new(0, 0, 0, 10), Size = UDim2.new(1, 0, 0, 48), Font = FONT_B, TextSize = 36, TextColor3 = C.gold, TextXAlignment = Enum.TextXAlignment.Center })
local bannerSub = label(banner, { Position = UDim2.new(0, 0, 0, 62), Size = UDim2.new(1, 0, 0, 24), TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center })
local bannerExtra = label(banner, { Position = UDim2.new(0, 0, 0, 92), Size = UDim2.new(1, 0, 0, 24), Font = FONT_B, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center })
local bannerQueue, bannerBusy = {}, false

local function showNextBanner()
	if bannerBusy then
		return
	end
	local item = table.remove(bannerQueue, 1)
	if not item then
		return
	end
	bannerBusy = true
	bannerTitle.Text = "\u{00A1}NIVEL " .. tostring(item.level) .. "!"
	local sub = "+" .. fmt(item.coins or 0) .. " " .. COIN .. " de recompensa"
	if (item.milestone or 0) > 0 then
		sub ..= "  " .. DOT .. "  hito +" .. item.milestone
	end
	bannerSub.Text = sub
	local rk = item.rankUp and Shared.Ranks[item.rank] or nil
	bannerExtra.Text = rk and ("\u{00A1}Nuevo rango: " .. rk.name .. "!") or ""
	bannerExtra.TextColor3 = rk and rk.color or C.text
	banner.Visible = true
	bannerScale.Scale = 0.6
	TweenService:Create(banner, TweenInfo.new(0.3), { GroupTransparency = 0 }):Play()
	TweenService:Create(bannerScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(rk and 3.4 or 2.6, function()
		TweenService:Create(banner, TweenInfo.new(0.4), { GroupTransparency = 1 }):Play()
		task.wait(0.45)
		banner.Visible = false
		bannerBusy = false
		showNextBanner()
	end)
end

-- ============================================================
-- Notificaciones del servidor (fuera del lobby se guardan y se muestran al volver)
-- ============================================================
local pending = {}

local function deliver(kind, data)
	if kind == "levelup" then
		table.insert(bannerQueue, data)
		showNextBanner()
	elseif kind == "mission" then
		toast(OKBOX .. (data.weekly and " \u{00A1}Misi\u{00F3}n semanal!" or " \u{00A1}Misi\u{00F3}n completada!"),
			tostring(data.label) .. " " .. DOT .. " +" .. tostring(data.reward) .. " " .. COIN, C.green, 5)
	elseif kind == "bonus" then
		toast(TROPHY .. (data.weekly and " \u{00A1}Todas las semanales!" or " \u{00A1}Todas las diarias!"),
			"+" .. tostring(data.reward) .. " " .. COIN .. " de bonus", C.gold, 5)
	elseif kind == "warn" then
		toast(WARN .. " " .. tostring(data.text or ""), nil, C.red, 8)
	elseif kind == "info" then
		toast(tostring(data.text or ""), nil, C.gold, 4)
	end
end

local function flushPending()
	local list = pending
	pending = {}
	for i, n in ipairs(list) do
		task.delay((i - 1) * 0.35, function()
			if state.inLobby or not LOBBY_ONLY then
				deliver(n.kind, n.data)
			end
		end)
	end
end

notifyEvent.OnClientEvent:Connect(function(kind, data)
	if type(kind) == "string" and data == nil then
		kind, data = "info", { text = kind } -- formato antiguo: solo texto
	end
	data = data or {}
	if kind == "result" then
		setLastFight(data)
		return
	elseif kind == "saved" then
		if not state.unsaved then
			setStatus(CHECK .. " Guardado", C.green, false)
		end
		return
	end
	if state.inLobby or not LOBBY_ONLY then
		deliver(kind, data)
	else
		table.insert(pending, { kind = kind, data = data })
		if #pending > 12 then
			table.remove(pending, 1)
		end
	end
end)

-- ============================================================
-- Solo en el lobby: el panel existe unicamente con el menu principal abierto
-- ============================================================
local menuPanels = {}
local menuBase = {} -- posicion original de cada submenu, sin nuestro desplazamiento
do
	local bg = menu and menu:FindFirstChild("Background")
	if bg then
		for _, n in ipairs({ "Panel", "ModePanel", "ShopPanel", "CodesPanel" }) do
			local p = bg:FindFirstChild(n)
			if p then
				table.insert(menuPanels, { name = n, obj = p })
				-- Se guarda la posicion original porque el desplazamiento de refreshDock se
				-- recalcula cada vez: si se aplicara sobre el valor ya movido, el desplazamiento
				-- se acumularia y los submenus se irian hasta salirse de la pantalla.
				menuBase[n] = p.Position
			end
		end
	end
end

-- Si el menu abre la tienda / codigos / modos el panel se compacta; si no queda sitio, se oculta
function refreshDock()
	local sub = false
	-- Hueco libre a la izquierda, medido sobre la posicion ORIGINAL de los submenus. Medirlo
	-- sobre la posicion ya desplazada seria circular: el desplazamiento depende del hueco y el
	-- hueco dependeria del desplazamiento.
	local leftBase = math.huge
	local mid = camera.ViewportSize.X / 2
	local vp = camera.ViewportSize
	local menuTarget = math.clamp(math.min(vp.X / 820, vp.Y / 560), 0.5, 1.25) -- misma formula que MainMenuClient
	for _, e in ipairs(menuPanels) do
		if e.obj.Visible then
			-- los submenus estan centrados con AnchorPoint 0.5, asi que su borde izquierdo es
			-- el centro de la pantalla menos la mitad de su ancho ya escalado
			leftBase = math.min(leftBase, mid - (e.obj.Size.X.Offset * menuTarget) / 2)
			if e.name ~= "Panel" then
				sub = true
			end
		end
	end
	state.subOpen = sub
	applyLayout()

	-- La columna se queda a la izquierda con su escala normal, siempre. Si el submenu abierto
	-- se la comes, lo que se mueve es el menu: se le anade un desplazamiento en X para que no
	-- la pise. MainMenuClient nunca escribe la Position de estos paneles (solo alterna Visible),
	-- asi que no hay pelea por ese valor.
	local anchoPanel = WIDTH * baseScale
	local disponible = (leftBase == math.huge) and math.huge or (leftBase - 12 - 8)
	-- El menu NO se desplaza nunca: antes saltaba a la derecha al abrir un submenu y se recolocaba
	-- otra vez 0.45 s despues. Si el submenu abierto no deja hueco, es la columna la que se oculta.
	local extra = 0
	local sinHueco = disponible < anchoPanel
	for _, e in ipairs(menuPanels) do
		local base = menuBase[e.name]
		if base then
			e.obj.Position = UDim2.new(base.X.Scale, base.X.Offset + extra, base.Y.Scale, base.Y.Offset)
		end
	end

	uiScale.Scale = baseScale
	if state.dock ~= DOCK_LEFT then
		state.dock = DOCK_LEFT
		column.Position = DOCK_LEFT
	end
	column.Visible = not (sub and sinHueco)
end

for _, e in ipairs(menuPanels) do
	e.obj:GetPropertyChangedSignal("Visible"):Connect(function()
		refreshDock()
		task.delay(0.45, refreshDock) -- el menu anima la apertura: se recalcula al terminar
	end)
end

local function onEnterLobby()
	if requestEvent then
		requestEvent:FireServer() -- datos frescos al volver
	end
	-- Entra desde fuera por el lado en el que va a quedar, no siempre por la izquierda:
	-- si el menu se ha quedado sin hueco a la izquierda, el panel esta dockado a la derecha.
	local destino = state.dock
	local desde = (destino.X.Scale == 1)
		and UDim2.new(1, WIDTH + 40, 0, 64)
		or UDim2.new(0, -(WIDTH + 40), 0, 64)
	column.Position = desde
	TweenService:Create(column, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = destino }):Play()
	refreshDock()
	task.delay(0.6, function()
		refreshDock()
		flushPending()
	end)
end

local function refreshLobby()
	local show = true
	if LOBBY_ONLY then
		show = player:GetAttribute("InOilMatch") ~= true
		-- Si el MainMenu no esta (o se ha quitado) no se pierde el panel: en el lobby
		-- se muestra igualmente. Antes bastaba con que faltara el menu para que el
		-- panel no apareciera nunca.
		if menu ~= nil and menu.Enabled == false then
			show = false
		end
	end
	if show == state.inLobby then
		return
	end
	state.inLobby = show
	gui.Enabled = show
	if show then
		onEnterLobby()
	end
end

if menu then
	menu:GetPropertyChangedSignal("Enabled"):Connect(refreshLobby)
end
player:GetAttributeChangedSignal("InOilMatch"):Connect(refreshLobby)

-- ============================================================
-- Arranque
-- ============================================================
styleTabs()
applyLayout()
gui.Enabled = false
refreshLobby()

-- Pedir el estado al arrancar (el primer envio del servidor puede llegar antes que este script)
if requestEvent then
	task.spawn(function()
		for _ = 1, 8 do
			if gotSnapshot then
				return
			end
			requestEvent:FireServer()
			task.wait(2)
		end
	end)
else
	warn("[ProgressionClient] No se encontr\u{00F3} RequestProgression")
end
