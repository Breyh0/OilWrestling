-- OilCombatHUD (LocalScript, StarterPlayerScripts)
-- HUD del combate en aceite: barras de equilibrio y stamina, estado actual, lista de controles
-- (con la tecla de cada movimiento y su cooldown), marcador, avisos y botón RENUNCIAR.
-- Las teclas salen de ReplicatedStorage.OilControls: si las cambias allí, el HUD se actualiza solo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local CFG = require(ReplicatedStorage:WaitForChild("OilConfig"))
local Controls = require(ReplicatedStorage:WaitForChild("OilControls"))
local eventRemote = ReplicatedStorage:WaitForChild("OilEvent")

local pg = player:WaitForChild("PlayerGui")
local menu = pg:WaitForChild("MainMenu", 20)

-- Tema del juego: verde oliva oscuro con detalles dorados
local GOLD = Color3.fromRGB(240, 200, 90)
local CREAM = Color3.fromRGB(240, 220, 120)
local DARK = Color3.fromRGB(22, 28, 22)
local RED = Color3.fromRGB(235, 90, 80)

local STATE_INFO = {
	idle = { "LISTO", Color3.fromRGB(235, 235, 220) },
	pushed = { "EMPUJADO", Color3.fromRGB(255, 200, 120) },
	stunned = { "ATURDIDO", Color3.fromRGB(255, 235, 90) },
	knocked = { "DERRIBADO", Color3.fromRGB(255, 90, 90) },
	grabbed = { "AGARRADO — contraataca con clic", Color3.fromRGB(190, 120, 255) },
	grabbing = { "AGARRANDO", Color3.fromRGB(190, 120, 255) },
	blocking = { "BLOQUEANDO", Color3.fromRGB(110, 170, 255) },
	dodging = { "ESQUIVANDO", Color3.fromRGB(255, 255, 255) },
	offbalance = { "DESEQUILIBRADO", Color3.fromRGB(255, 130, 40) },
	invulnerable = { "INVULNERABLE", Color3.fromRGB(255, 215, 90) },
}

local NOTICES = {
	nostamina = { "SIN STAMINA", Color3.fromRGB(255, 200, 80) },
	broken = { "¡DESEQUILIBRADO! Protege tu espalda", Color3.fromRGB(255, 110, 60) },
	foe_broken = { "¡RIVAL DESEQUILIBRADO! ¡Empújalo ahora!", Color3.fromRGB(120, 255, 150) },
	parry = { "¡PARRY! Contraataca con clic", Color3.fromRGB(120, 230, 255) },
	parried = { "¡Te hicieron PARRY!", Color3.fromRGB(255, 120, 120) },
	dodged = { "¡ESQUIVA PERFECTA!", Color3.fromRGB(255, 255, 255) },
	guardbreak = { "¡GUARDIA ROTA!", Color3.fromRGB(255, 235, 90) },
}

-- Acciones con barra de cooldown y su costo de stamina
local COOLDOWN_ACTIONS = { push = "Push", charge = "Charge", grab = "Grab", dodge = "Dodge", block = "Block" }

-- ===== Utilidades de UI =====
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

local function addCorner(o, r)
	return make("UICorner", { CornerRadius = UDim.new(0, r) }, o)
end

local function addStroke(o, color, thickness, transparency)
	return make("UIStroke", { Color = color, Thickness = thickness or 1, Transparency = transparency or 0 }, o)
end

local gui = make("ScreenGui", {
	Name = "OilCombatHUD",
	ResetOnSpawn = false,
	DisplayOrder = 58,
	IgnoreGuiInset = true,
	Enabled = false,
}, pg)

-- ===== Barras (equilibrio, stamina) y estado =====
local barsPanel = make("Frame", {
	Name = "Bars",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -22),
	Size = UDim2.fromOffset(380, 100),
	BackgroundTransparency = 1,
}, gui)
local barsScale = make("UIScale", {}, barsPanel)
barsScale.Scale = 1

local counterLabel = make("TextLabel", {
	Name = "Counter",
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(0, -28),
	Size = UDim2.new(1, 0, 0, 24),
	Font = Enum.Font.GothamBlack,
	TextSize = 17,
	TextColor3 = GOLD,
	TextStrokeTransparency = 0.4,
	Text = "¡CONTRAATAQUE LISTO! Empuja ya (clic)",
	Visible = false,
}, barsPanel)

local stateLabel = make("TextLabel", {
	Name = "State",
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 28),
	Font = Enum.Font.GothamBlack,
	TextSize = 22,
	TextColor3 = Color3.new(1, 1, 1),
	TextStrokeTransparency = 0.35,
	Text = "LISTO",
}, barsPanel)

local function makeBarRow(y, labelText)
	make("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.fromOffset(92, 24),
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = CREAM,
		Text = labelText,
	}, barsPanel)
	local bg = make("Frame", {
		Position = UDim2.fromOffset(96, y),
		Size = UDim2.new(1, -96, 0, 24),
		BackgroundColor3 = Color3.fromRGB(18, 22, 18),
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
	}, barsPanel)
	addCorner(bg, 6)
	addStroke(bg, GOLD, 1.5, 0.15)
	local fill = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(90, 200, 120),
		BorderSizePixel = 0,
	}, bg)
	addCorner(fill, 6)
	local value = make("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Font = Enum.Font.GothamBlack,
		TextSize = 13,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.5,
		ZIndex = 3,
		Text = "100",
	}, bg)
	return fill, value
end

local balFill, balValue = makeBarRow(36, "EQUILIBRIO")
local staFill, staValue = makeBarRow(66, "STAMINA")

-- ===== Panel de controles (tecla de cada movimiento) =====
local legend = make("Frame", {
	Name = "Controls",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -10, 1, -10),
	Size = UDim2.fromOffset(176, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = DARK,
	BackgroundTransparency = 0.7,
	BorderSizePixel = 0,
}, gui)
addCorner(legend, 10)
addStroke(legend, GOLD, 1.5, 0.2)
local legendScale = make("UIScale", {}, legend)
make("UIPadding", {
	PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4),
	PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4),
}, legend)
make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, legend)

make("TextLabel", {
	Name = "Title",
	LayoutOrder = 0,
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 14),
	Font = Enum.Font.GothamBlack,
	TextSize = 10,
	TextColor3 = GOLD,
	TextTransparency = 0.25,
	Text = "CONTROLES",
}, legend)

local rows = {} -- id -> { cd = Frame, name = TextLabel, badge = TextLabel }
local order = 1
for _, b in ipairs(Controls.Bindings) do
	if b.id ~= "resign" then
		local row = make("TextButton", {
			Name = "Row_" .. b.id,
			LayoutOrder = order,
			AutoButtonColor = false,
			Text = "",
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundColor3 = Color3.fromRGB(34, 44, 32),
			BackgroundTransparency = 0.75,
			BorderSizePixel = 0,
			ClipsDescendants = true,
		}, legend)
		order += 1
		addCorner(row, 8)
		local badge = make("TextLabel", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 3, 0.5, 0),
			Size = UDim2.fromOffset(62, 16),
			BackgroundColor3 = Color3.fromRGB(14, 18, 14),
			BackgroundTransparency = 0.45,
			Font = Enum.Font.GothamBlack,
			TextSize = 10,
			TextColor3 = GOLD,
			Text = b.keyLabel,
			ZIndex = 2,
		}, row)
		addCorner(badge, 6)
		addStroke(badge, GOLD, 1, 0.4)
		local nameLabel = make("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(71, 0),
			Size = UDim2.new(1, -74, 1, 0),
			Font = Enum.Font.GothamBold,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = CREAM,
			Text = b.name,
			ZIndex = 2,
		}, row)
		-- (la descripción 'b.hint' ya no se dibuja para ahorrar espacio; sigue en OilControls)
		-- sombra de cooldown: se encoge hasta que la acción vuelve a estar lista
		local cd = make("Frame", {
			Size = UDim2.new(0, 0, 1, 0),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
			ZIndex = 4,
		}, row)
		rows[b.id] = { cd = cd, name = nameLabel, badge = badge }

		-- también se puede pulsar (táctil / ratón); el bloqueo se mantiene mientras se sostiene
		row.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				Controls.Request:Fire(b.id, true)
			end
		end)
		if b.hold then
			row.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					Controls.Request:Fire(b.id, false)
				end
			end)
		end
	end
end

-- Botón RENUNCIAR (2 pulsaciones para confirmar)
local resignInfo = Controls.ByAction.resign
local RESIGN_TEXT = "RENUNCIAR  [" .. (resignInfo and resignInfo.keyLabel or "X") .. "]"
local resignBtn = make("TextButton", {
	Name = "Resign",
	LayoutOrder = order,
	AutoButtonColor = false,
	Size = UDim2.new(1, 0, 0, 22),
	BackgroundColor3 = Color3.fromRGB(150, 45, 40),
	BackgroundTransparency = 0.45,
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBlack,
	TextSize = 11,
	TextColor3 = Color3.new(1, 1, 1),
	Text = RESIGN_TEXT,
}, legend)
addCorner(resignBtn, 8)
addStroke(resignBtn, Color3.fromRGB(255, 130, 120), 1, 0.4)
-- (Renunciar pide pulsar 2 veces: el botón cambia a '¿SEGURO?' al primer toque)

resignBtn.Activated:Connect(function()
	Controls.Request:Fire("resign", true)
end)

Controls.ResignState.Event:Connect(function(state)
	if state == "armed" then
		resignBtn.Text = "¿SEGURO? OTRA VEZ"
		resignBtn.BackgroundColor3 = Color3.fromRGB(215, 55, 45)
		resignBtn.BackgroundTransparency = 0.15
	elseif state == "sent" then
		resignBtn.Text = "SALIENDO..."
	else
		resignBtn.Text = RESIGN_TEXT
		resignBtn.BackgroundColor3 = Color3.fromRGB(150, 45, 40)
		resignBtn.BackgroundTransparency = 0.45
	end
end)

-- ===== Avisos de combate (¡PARRY!, ¡ESQUIVA!, etc.) =====
-- El marcador de rounds, la cuenta atrás y los banners de punto/victoria los dibuja OilRoundsHUD.
local noticeLabel = make("TextLabel", {
	Name = "Notice",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -190),
	Size = UDim2.fromOffset(640, 34),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	TextSize = 26,
	TextColor3 = Color3.new(1, 1, 1),
	TextStrokeTransparency = 0.3,
	Text = "",
	Visible = false,
}, gui)

local noticeToken = 0
local function showNotice(kind)
	local n = NOTICES[kind]
	if not n then
		return
	end
	noticeToken += 1
	local my = noticeToken
	noticeLabel.Text = n[1]
	noticeLabel.TextColor3 = n[2]
	noticeLabel.TextTransparency = 0
	noticeLabel.TextStrokeTransparency = 0.3
	noticeLabel.Visible = true
	task.delay(1.4, function()
		if noticeToken ~= my then
			return
		end
		TweenService:Create(noticeLabel, TweenInfo.new(0.3), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.wait(0.3)
		if noticeToken == my then
			noticeLabel.Visible = false
		end
	end)
end

eventRemote.OnClientEvent:Connect(function(kind, a)
	if kind == "notice" then
		showNotice(a)
	end
end)

-- ===== Visibilidad (solo durante un combate, y nunca sobre el menú principal) =====
local function refreshVisibility()
	local show = player:GetAttribute("InOilMatch") == true and not (menu and menu.Enabled)
	gui.Enabled = show
	if not show then
		noticeLabel.Visible = false
		Controls.ResignState:Fire("reset")
	end
end
player:GetAttributeChangedSignal("InOilMatch"):Connect(refreshVisibility)
if menu then
	menu:GetPropertyChangedSignal("Enabled"):Connect(refreshVisibility)
end
refreshVisibility()

-- Escala la interfaz según la pantalla (pantallas pequeñas / móvil)
local function updateScale()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local s = math.clamp(cam.ViewportSize.Y / 800, 0.6, 1.1)
	barsScale.Scale = s
	legendScale.Scale = s
end
updateScale()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
end

-- ===== Actualización por frame =====
local balShown = CFG.Balance.Max
local staShown = CFG.Stamina.Max

RunService.RenderStepped:Connect(function(dt)
	if not gui.Enabled then
		return
	end
	local smooth = 1 - math.exp(-14 * dt)
	local bal = player:GetAttribute("Balance") or CFG.Balance.Max
	local sta = player:GetAttribute("Stamina") or CFG.Stamina.Max
	balShown += (bal - balShown) * smooth
	staShown += (sta - staShown) * smooth

	local state = player:GetAttribute("OilState") or "idle"
	local info = STATE_INFO[state] or STATE_INFO.idle
	stateLabel.Text = info[1]
	stateLabel.TextColor3 = info[2]

	-- equilibrio: verde -> rojo; desequilibrado = rojo parpadeante a barra llena (¡cuidado!)
	local balPct = math.clamp(balShown / CFG.Balance.Max, 0, 1)
	if state == "offbalance" then
		local pulse = 0.5 + 0.5 * math.sin(os.clock() * 14)
		balFill.Size = UDim2.fromScale(1, 1)
		balFill.BackgroundColor3 = Color3.fromRGB(255, 60 + 60 * pulse, 40)
		balValue.Text = "¡ROTO!"
	else
		balFill.Size = UDim2.fromScale(balPct, 1)
		balFill.BackgroundColor3 = Color3.fromHSV(0.33 * balPct, 0.65, 0.85)
		balValue.Text = tostring(math.floor(balShown + 0.5))
	end

	local staPct = math.clamp(staShown / CFG.Stamina.Max, 0, 1)
	staFill.Size = UDim2.fromScale(staPct, 1)
	staFill.BackgroundColor3 = staPct < 0.25 and Color3.fromRGB(235, 110, 60) or Color3.fromRGB(240, 200, 60)
	staValue.Text = tostring(math.floor(staShown + 0.5))

	counterLabel.Visible = player:GetAttribute("CounterReady") == true

	-- cooldowns y costo de stamina de cada movimiento
	local now = workspace:GetServerTimeNow()
	for id, key in pairs(COOLDOWN_ACTIONS) do
		local row = rows[id]
		if row then
			local untilT = player:GetAttribute("cd_" .. id)
			local len = player:GetAttribute("cdlen_" .. id)
			local frac = 0
			if untilT and len and len > 0 then
				frac = math.clamp((untilT - now) / len, 0, 1)
			end
			row.cd.Size = UDim2.new(frac, 0, 1, 0)
			local def = CFG[key]
			local cost = def and (def.Stamina or def.MinStamina) or 0
			local affordable = staShown >= cost
			row.name.TextTransparency = affordable and 0 or 0.55
			row.badge.TextTransparency = affordable and 0 or 0.55
		end
	end
end)
