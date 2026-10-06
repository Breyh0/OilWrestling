-- OilRoundsHUD (LocalScript, StarterPlayerScripts)
-- Marcador de rounds del combate (gana quien consiga 3 rounds; se juegan como máximo 5).
--   * Marcador fijo arriba al centro: nombres, rounds ganados (círculos dorados), número de round y tiempo.
--   * Pantallas grandes: cuenta atrás con el marcador, ¡LUCHA!, punto del round y VICTORIA / DERROTA.
-- Solo muestra datos: el servidor (OilCombat) manda los eventos y decide quién gana.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local CFG = require(ReplicatedStorage:WaitForChild("OilConfig"))
local eventRemote = ReplicatedStorage:WaitForChild("OilEvent")

local pg = player:WaitForChild("PlayerGui")
local menu = pg:WaitForChild("MainMenu", 20)
local fighterGui = pg:WaitForChild("FighterGui", 5) -- panel de estado antiguo: se oculta durante el combate

-- Tema del juego: verde oliva oscuro con detalles dorados
local GOLD = Color3.fromRGB(240, 200, 90)
local CREAM = Color3.fromRGB(240, 220, 120)
local RED = Color3.fromRGB(235, 90, 80)
local DIM = Color3.fromRGB(180, 172, 140)
local WHITE = Color3.new(1, 1, 1)
local EMPTY = Color3.fromRGB(20, 24, 20)

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

local function stroke(o, color, thickness, transparency)
	return make("UIStroke", { Color = color, Thickness = thickness, Transparency = transparency or 0 }, o)
end

local gui = make("ScreenGui", {
	Name = "OilRoundsHUD",
	ResetOnSpawn = false,
	DisplayOrder = 54, -- bajo la progresión (55), el HUD de combate (58) y el de partida (60)
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Enabled = false,
}, player:WaitForChild("PlayerGui"))

-- ===== Estado =====
local fighters = {} -- { { name, score, ai, gone } }
local target = CFG.PointsToWin
local roundNo = 0
local shown = false
local finalShown = false
local matchToken = 0
local timerEnd = nil
local ui = nil -- { cards, round, best, timer, multi }

local function bestOf()
	return target * 2 - 1
end

local function fmtTime(seconds)
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- Siempre tú primero (izquierda), el resto después
local function ordered(list)
	local out = {}
	for _, f in ipairs(list) do
		if f.name == player.Name then
			table.insert(out, 1, f)
		else
			table.insert(out, f)
		end
	end
	return out
end

local function nameOf(f)
	return f.name == player.Name and "TÚ" or f.name
end

local function scoreLine()
	local list = ordered(fighters)
	if #list == 2 then
		return string.format("%s  %d — %d  %s", nameOf(list[1]), list[1].score, list[2].score, nameOf(list[2]))
	end
	local parts = {}
	for _, f in ipairs(list) do
		table.insert(parts, nameOf(f) .. " " .. f.score)
	end
	return table.concat(parts, "  ·  ")
end

-- ===== Marcador superior =====
local board = make("Frame", {
	Name = "Board",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 60), -- justo bajo la barra superior de la partida
	Size = UDim2.fromOffset(580, 104),
	BackgroundColor3 = WHITE,
	BackgroundTransparency = 0.08,
	BorderSizePixel = 0,
	Visible = false,
}, gui)
corner(board, 16)
stroke(board, GOLD, 2.5, 0.05)
make("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(40, 52, 36), Color3.fromRGB(14, 18, 14)),
	Rotation = 90,
}, board)
local boardScale = make("UIScale", {}, board)
local content = make("Frame", { Name = "Content", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, board)

local function setPips(entry, score, animate)
	for i, p in ipairs(entry.pips) do
		local won = i <= score
		p.frame.BackgroundColor3 = won and GOLD or EMPTY
		p.stroke.Color = won and Color3.fromRGB(255, 244, 200) or GOLD
		p.stroke.Transparency = won and 0 or 0.45
		if animate and won and i == score and entry.shown < score then
			-- el round recién ganado "salta" y la tarjeta destella
			p.scale.Scale = 2.2
			TweenService:Create(p.scale, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			entry.stroke.Color = WHITE
			entry.stroke.Transparency = 0
			entry.stroke.Thickness = 6
			TweenService:Create(entry.stroke, TweenInfo.new(0.9), {
				Color = entry.baseColor,
				Transparency = 0.35,
				Thickness = 2,
			}):Play()
		end
	end
	entry.shown = score
end

local function buildCard(f, alignRight, w, h, compact)
	local isMe = f.name == player.Name
	local baseColor = isMe and GOLD or RED
	local card = make("Frame", {
		Name = "Card_" .. f.name,
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = isMe and Color3.fromRGB(74, 62, 24) or Color3.fromRGB(62, 34, 30),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
	}, nil)
	corner(card, 12)
	local st = stroke(card, baseColor, 2, 0.35)
	local xAlign = alignRight and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left

	local nameLabel = make("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 5),
		Size = UDim2.new(1, -20, 0, compact and 20 or 26),
		Font = Enum.Font.GothamBlack,
		TextSize = compact and 14 or 18,
		TextColor3 = WHITE,
		TextXAlignment = xAlign,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = f.name,
	}, card)

	local py = compact and 30 or 38
	local pipsFrame = make("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, py),
		Size = UDim2.new(1, -20, 0, 32),
	}, card)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		HorizontalAlignment = alignRight and Enum.HorizontalAlignment.Right or Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, pipsFrame)

	local pips = {}
	for i = 1, target do
		local pip = make("Frame", {
			LayoutOrder = i,
			Size = UDim2.fromOffset(28, 28),
			BackgroundColor3 = EMPTY,
			BorderSizePixel = 0,
		}, pipsFrame)
		corner(pip, 14)
		pips[i] = {
			frame = pip,
			stroke = stroke(pip, GOLD, 2.5, 0.45),
			scale = make("UIScale", {}, pip),
		}
	end

	if isMe then
		-- etiqueta "TÚ" en el lado opuesto a los círculos
		local chip = make("TextLabel", {
			AnchorPoint = Vector2.new(alignRight and 0 or 1, 0.5),
			Position = UDim2.new(alignRight and 0 or 1, alignRight and 10 or -10, 0, py + 16),
			Size = UDim2.fromOffset(38, 20),
			BackgroundColor3 = GOLD,
			Font = Enum.Font.GothamBlack,
			TextSize = 12,
			TextColor3 = Color3.fromRGB(34, 26, 8),
			Text = "TÚ",
		}, card)
		corner(chip, 10)
	end

	local entry = { card = card, name = nameLabel, stroke = st, baseColor = baseColor, pips = pips, shown = 0 }
	ui.cards[f.name] = entry
	return entry
end

local function setRoundText()
	if not ui then
		return
	end
	if ui.multi then
		ui.round.Text = roundNo > 0 and ("ROUND " .. roundNo) or "ROUND"
	else
		ui.round.Text = roundNo > 0 and tostring(roundNo) or "-"
	end
end

local function setTimerIdle()
	if ui and ui.timer then
		ui.timer.Text = fmtTime(CFG.RoundTimeout)
		ui.timer.TextColor3 = CREAM
	end
end

local function applyScores(animate)
	if not ui then
		return
	end
	for _, f in ipairs(fighters) do
		local entry = ui.cards[f.name]
		if entry then
			setPips(entry, f.score, animate)
			if f.gone then
				entry.card.BackgroundTransparency = 0.65
				entry.name.Text = f.name .. " (fuera)"
				entry.name.TextTransparency = 0.4
			end
		end
	end
end

local function textLabel(parent, props)
	local base = { BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextColor3 = CREAM, Text = "" }
	for k, v in pairs(props) do
		base[k] = v
	end
	return make("TextLabel", base, parent)
end

local function buildBoard()
	content:ClearAllChildren()
	local list = ordered(fighters)
	local n = #list
	ui = { cards = {}, multi = n > 2 }

	if n <= 2 then
		-- 1 contra 1: [tú] [round / tiempo] [rival]
		board.Size = UDim2.fromOffset(580, 104)
		for i, f in ipairs(list) do
			local right = i == 2
			local entry = buildCard(f, right, 208, 84, false)
			entry.card.AnchorPoint = Vector2.new(right and 1 or 0, 0)
			entry.card.Position = UDim2.new(right and 1 or 0, right and -10 or 10, 0, 10)
			entry.card.Parent = content
		end
		local center = make("Frame", {
			Name = "Center",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 0),
			Size = UDim2.fromOffset(132, 104),
			BackgroundTransparency = 1,
		}, content)
		textLabel(center, { Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 14), TextSize = 12, TextColor3 = DIM, Text = "ROUND" })
		ui.round = textLabel(center, {
			Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 46),
			Font = Enum.Font.GothamBlack, TextSize = 44, TextColor3 = GOLD, TextStrokeTransparency = 0.5, Text = "-",
		})
		ui.best = textLabel(center, { Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 0, 14), TextSize = 11 })
		ui.timer = textLabel(center, {
			Position = UDim2.fromOffset(0, 80), Size = UDim2.new(1, 0, 0, 20), Font = Enum.Font.GothamBlack, TextSize = 16,
		})
	else
		-- 3 o 4 luchadores: franja de información arriba y una tarjeta por luchador
		local cardW, gap = 132, 8
		local width = math.max(580, n * cardW + (n - 1) * gap + 20)
		board.Size = UDim2.fromOffset(width, 124)
		ui.round = textLabel(content, {
			Position = UDim2.new(0, 0, 0, 6), Size = UDim2.new(0.34, 0, 0, 30),
			Font = Enum.Font.GothamBlack, TextSize = 20, TextColor3 = GOLD, Text = "ROUND",
		})
		ui.best = textLabel(content, { Position = UDim2.new(0.34, 0, 0, 6), Size = UDim2.new(0.32, 0, 0, 30), TextSize = 14 })
		ui.timer = textLabel(content, {
			Position = UDim2.new(0.66, 0, 0, 6), Size = UDim2.new(0.34, 0, 0, 30), Font = Enum.Font.GothamBlack, TextSize = 20,
		})
		local startX = (width - (n * cardW + (n - 1) * gap)) / 2
		for i, f in ipairs(list) do
			local entry = buildCard(f, false, cardW, 74, true)
			entry.card.Position = UDim2.fromOffset(startX + (i - 1) * (cardW + gap), 42)
			entry.card.Parent = content
		end
	end

	ui.best.Text = "PRIMERO A " .. target .. " WINS"
	setRoundText()
	setTimerIdle()
	applyScores(false)
	board.Visible = true
end

RunService.RenderStepped:Connect(function()
	if ui and ui.timer and timerEnd then
		local left = timerEnd - os.clock()
		ui.timer.Text = fmtTime(left)
		ui.timer.TextColor3 = (left <= 10) and RED or CREAM
	end
end)

-- ===== Pantallas grandes (cuenta atrás, punto, victoria) =====
local splash = make("Frame", {
	Name = "Splash",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 178),
	Size = UDim2.new(1, 0, 0, 200),
	BackgroundTransparency = 1,
	Visible = false,
}, gui)
local band = make("Frame", {
	Name = "Band",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BorderSizePixel = 0,
}, splash)
-- la franja oscura se desvanece hacia los lados
make("UIGradient", {
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.18, 0.4),
		NumberSequenceKeypoint.new(0.82, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	}),
}, band)

local stage = make("Frame", {
	Name = "Stage",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
}, splash)
local pop = make("UIScale", {}, stage)

local sKick = textLabel(stage, {
	Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, 0, 0, 28),
	TextSize = 24, TextColor3 = GOLD, TextStrokeTransparency = 0.4,
})
local sMain = textLabel(stage, {
	Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 96),
	Font = Enum.Font.GothamBlack, TextScaled = true, TextColor3 = WHITE, TextStrokeTransparency = 0.3,
})
local mainLimit = make("UITextSizeConstraint", { MaxTextSize = 100, MinTextSize = 20 }, sMain)
local sSub = textLabel(stage, {
	Position = UDim2.fromOffset(0, 138), Size = UDim2.new(1, 0, 0, 32),
	TextSize = 26, TextStrokeTransparency = 0.4,
})
local sFoot = textLabel(stage, {
	Position = UDim2.fromOffset(0, 168), Size = UDim2.new(1, 0, 0, 24),
	TextSize = 18, TextColor3 = DIM, TextStrokeTransparency = 0.5,
})
local splashLabels = { sKick, sMain, sSub, sFoot }

local splashBase = 1
local splashToken = 0

local function hideSplash(my)
	local info = TweenInfo.new(0.35)
	for _, l in ipairs(splashLabels) do
		TweenService:Create(l, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end
	TweenService:Create(band, info, { BackgroundTransparency = 1 }):Play()
	task.delay(0.37, function()
		if splashToken == my then
			splash.Visible = false
		end
	end)
end

-- o: { kicker, main, color, size, sub, foot, seconds }  (sin 'seconds' se queda hasta que se oculte el HUD)
local function showSplash(o)
	splashToken += 1
	local my = splashToken
	sKick.Text = o.kicker or ""
	sMain.Text = o.main or ""
	sMain.TextColor3 = o.color or WHITE
	-- textos largos (p. ej. nombres de jugador) se reducen para que no se salgan de la pantalla
	local len = math.max(utf8.len(sMain.Text) or 1, 1)
	mainLimit.MaxTextSize = math.min(o.size or 90, math.max(30, math.floor(760 / len / 0.62)))
	sSub.Text = o.sub or ""
	sFoot.Text = o.foot or ""
	for _, l in ipairs(splashLabels) do
		l.TextTransparency = 0
		l.TextStrokeTransparency = (l == sFoot or l == sSub or l == sKick) and 0.45 or 0.3
	end
	band.BackgroundTransparency = 0
	splash.Visible = true
	pop.Scale = splashBase * 1.35
	TweenService:Create(pop, TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = splashBase }):Play()
	if o.seconds then
		task.delay(o.seconds, function()
			if splashToken == my then
				hideSplash(my)
			end
		end)
	end
end

-- ===== Visibilidad =====
local function refresh()
	local menuOn = menu ~= nil and menu.Enabled
	gui.Enabled = shown and not menuOn
	if fighterGui then
		if shown then
			fighterGui.Enabled = false -- el panel antiguo taparia el marcador
		elseif not menuOn then
			fighterGui.Enabled = true
		end
	end
end

local function hideAll()
	shown = false
	finalShown = false
	timerEnd = nil
	splashToken += 1
	splash.Visible = false
	board.Visible = false
	ui = nil
	refresh()
end

if menu then
	menu:GetPropertyChangedSignal("Enabled"):Connect(refresh)
end
if fighterGui then
	fighterGui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if shown and fighterGui.Enabled then
			fighterGui.Enabled = false
		end
	end)
end

-- Cuando el servidor te saca del combate (fin, renuncia), el marcador desaparece
local wasIn = false
player:GetAttributeChangedSignal("InOilMatch"):Connect(function()
	local nowIn = player:GetAttribute("InOilMatch") == true
	if wasIn and not nowIn and shown then
		hideAll()
	end
	wasIn = nowIn
end)

-- ===== Escala según la pantalla =====
local function updateScale()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local vp = cam.ViewportSize
	local s = math.min(vp.X / 1000, vp.Y / 760)
	-- el marcador no debe tapar el panel de progresión (columna de 292 px a la izquierda): se encoge si la pantalla es estrecha
	boardScale.Scale = math.clamp(math.min(s, (vp.X - 600) / 580), 0.55, 1.15)
	splashBase = math.clamp(s, 0.55, 1.2)
	pop.Scale = splashBase
end
updateScale()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
end

-- ===== Eventos del combate =====
local function parseWinner(raw)
	if type(raw) ~= "string" then
		return nil, nil
	end
	-- el servidor manda "Nombre (Lobby en 3s)" durante la cuenta atrás hacia el lobby
	local name, secs = string.match(raw, "^(.*) %(Lobby en (%d+)s%)$")
	if name then
		return name, tonumber(secs)
	end
	return raw, nil
end

local function updateFromList(list, animate)
	if type(list) ~= "table" then
		return
	end
	local present = {}
	for _, item in ipairs(list) do
		present[item.name] = true
		for _, f in ipairs(fighters) do
			if f.name == item.name then
				f.score = item.score or f.score
			end
		end
	end
	for _, f in ipairs(fighters) do
		if not present[f.name] then
			f.gone = true
		end
	end
	applyScores(animate)
end

local function roundKicker()
	return string.format("ROUND %d  ·  PRIMERO A %d WINS", roundNo, target)
end

eventRemote.OnClientEvent:Connect(function(kind, a, b, c)
	if kind == "match_start" then
		fighters = {}
		for _, f in ipairs(a or {}) do
			table.insert(fighters, { name = f.name, score = f.score or 0, ai = f.ai, gone = false })
		end
		if #fighters < 1 then
			return
		end
		target = tonumber(b) or CFG.PointsToWin
		roundNo = 0
		timerEnd = nil
		finalShown = false
		matchToken += 1
		shown = true
		buildBoard()
		refresh()
		return
	end
	if not shown then
		return
	end

	if kind == "countdown" then
		roundNo = tonumber(b) or roundNo
		timerEnd = nil
		setRoundText()
		setTimerIdle()
		showSplash({ kicker = roundKicker(), main = tostring(a), color = WHITE, size = 120, sub = scoreLine(), seconds = 0.95 })

	elseif kind == "go" then
		timerEnd = os.clock() + CFG.RoundTimeout
		showSplash({ kicker = roundKicker(), main = "¡LUCHA!", color = Color3.fromRGB(255, 120, 70), size = 110, sub = scoreLine(), seconds = 0.9 })

	elseif kind == "point" then
		timerEnd = nil
		updateFromList(c, true)
		local mine = a == player.Name
		showSplash({
			kicker = "ROUND " .. roundNo,
			main = mine and "¡ROUND PARA TI!" or ("ROUND PARA " .. string.upper(tostring(a))),
			color = mine and GOLD or RED,
			size = 84,
			sub = scoreLine(),
			foot = tostring(b) .. " cae del ring",
			seconds = 2.4,
		})

	elseif kind == "noscore" then
		timerEnd = nil
		updateFromList(b, false)
		showSplash({
			kicker = "ROUND " .. roundNo,
			main = "ROUND SIN PUNTO",
			color = CREAM,
			size = 76,
			sub = scoreLine(),
			foot = tostring(a) .. " salió del ring por su cuenta",
			seconds = 2.4,
		})

	elseif kind == "draw" then
		timerEnd = nil
		showSplash({
			kicker = "ROUND " .. roundNo,
			main = "ROUND NULO",
			color = CREAM,
			size = 80,
			sub = scoreLine(),
			foot = "Se acabó el tiempo: se repite el round",
			seconds = 2.2,
		})

	elseif kind == "roster" then
		updateFromList(a, false)

	elseif kind == "forfeit" then
		if a == player.Name then
			hideAll() -- renunciaste: el servidor te manda al lobby
			return
		end
		timerEnd = nil
		updateFromList(b, false)
		showSplash({
			kicker = "ABANDONO",
			main = string.upper(tostring(a)) .. " RENUNCIÓ",
			color = RED,
			size = 70,
			sub = scoreLine(),
			seconds = 2.2,
		})

	elseif kind == "match_end" then
		timerEnd = nil
		local winner, secs = parseWinner(a)
		updateFromList(b, false)
		local myToken = matchToken
		if not winner then
			showSplash({ kicker = "COMBATE TERMINADO", main = "FIN DEL COMBATE", color = CREAM, size = 76, sub = scoreLine(), seconds = 3 })
			task.delay(3.4, function()
				if matchToken == myToken then
					hideAll()
				end
			end)
			return
		end

		local mine = winner == player.Name
		local participant = false
		for _, f in ipairs(fighters) do
			if f.name == player.Name and not f.gone then
				participant = true
			end
		end
		local foot = (c == "forfeit") and "Por abandono del rival" or ""
		if secs then
			foot = (foot ~= "" and (foot .. "  ·  ") or "") .. "Volviendo al lobby en " .. secs .. "s"
		end
		if not finalShown then
			finalShown = true
			local main, color
			if mine then
				main, color = "¡VICTORIA!", GOLD
			elseif participant then
				main, color = "DERROTA", RED
			else
				main, color = "¡" .. string.upper(winner) .. " GANA!", GOLD
			end
			showSplash({ kicker = "COMBATE TERMINADO", main = main, color = color, size = 110, sub = scoreLine(), foot = foot })
		else
			sFoot.Text = foot -- solo se actualiza la cuenta atrás hacia el lobby
		end
		if not secs then
			-- último aviso del servidor: el HUD se retira poco después (quien peleaba lo pierde antes, al salir del combate)
			task.delay(5, function()
				if matchToken == myToken then
					hideAll()
				end
			end)
		end
	end
end)

refresh()
