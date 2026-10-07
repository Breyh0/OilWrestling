-- MainMenuClient (cliente)
-- Menu principal: entrada animada, hover, particulas, seleccion de modo, tienda y codigos.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local gui = player:WaitForChild("PlayerGui"):WaitForChild("MainMenu")
local bg = gui:WaitForChild("Background")
local particles = bg:WaitForChild("Particles")
local panel = bg:WaitForChild("Panel")
local modePanel = bg:WaitForChild("ModePanel")
local shopPanel = bg:WaitForChild("ShopPanel")
local codesPanel = bg:WaitForChild("CodesPanel")

local title = panel:WaitForChild("Title")
local subtitle = panel:WaitForChild("Subtitle")
local divider = panel:WaitForChild("Divider")
local btns = panel:WaitForChild("Buttons")
local playBtn = btns:WaitForChild("PlayBtn")
local shopBtn = btns:WaitForChild("ShopBtn")
local codesBtn = btns:WaitForChild("CodesBtn")

local modeBtns = modePanel:WaitForChild("Buttons")
local soloBtn = modeBtns:WaitForChild("SoloBtn")
local multiBtn = modeBtns:WaitForChild("MultiBtn")
local modeBack = modePanel:WaitForChild("BackBtn")

local shopItems = shopPanel:WaitForChild("Items")
local shopBack = shopPanel:WaitForChild("BackBtn")

local codeInput = codesPanel:WaitForChild("CodeInput")
local redeemBtn = codesPanel:WaitForChild("RedeemBtn")
local codeMsg = codesPanel:WaitForChild("Message")
local codesBack = codesPanel:WaitForChild("BackBtn")

local startEvent = ReplicatedStorage:WaitForChild("StartGame")

local GOLD = Color3.fromRGB(240, 200, 90)
local OK_COLOR = Color3.fromRGB(110, 220, 120)
local ERR_COLOR = Color3.fromRGB(230, 90, 80)

local INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local mainButtons = { playBtn, shopBtn, codesBtn }
local panels = { panel, modePanel, shopPanel, codesPanel }

-- ============================================================
-- CONFIGURACION DE LA TIENDA (edita esta tabla para cambiar los items)
-- ============================================================
local SHOP_ITEMS = {
	{ id = "oil_gold",    name = "Aceite Dorado",       price = 250,  icon = "\u{2728}",  color = Color3.fromRGB(220, 170, 50) },
	{ id = "oil_crimson", name = "Aceite Carmes\u{00ED}", price = 250,  icon = "\u{1F525}", color = Color3.fromRGB(200, 70, 60) },
	{ id = "oil_emerald", name = "Aceite Esmeralda",    price = 400,  icon = "\u{1F340}", color = Color3.fromRGB(70, 150, 70) },
	{ id = "oil_night",   name = "Aceite Medianoche",   price = 400,  icon = "\u{1F319}", color = Color3.fromRGB(90, 90, 180) },
	{ id = "muscle",      name = "Pack M\u{00FA}sculo",  price = 600,  icon = "\u{1F4AA}", color = Color3.fromRGB(200, 120, 50) },
	{ id = "crown",       name = "Corona de Campe\u{00F3}n", price = 1000, icon = "\u{1F451}", color = Color3.fromRGB(150, 110, 200) },
}

-- ============================================================
-- Botones: hover / click con UIScale (no mueve el layout)
-- ============================================================
local bound = {}

local function bindButton(btn)
	btn.AutoButtonColor = false
	local base = btn.BackgroundColor3
	local hover = base:Lerp(Color3.new(1, 1, 1), 0.2)
	local stroke = btn:FindFirstChild("Stroke")
	local strokeBase = stroke and stroke.Transparency or 0
	local sc = btn:FindFirstChild("HoverScale")
	if not sc then
		sc = Instance.new("UIScale")
		sc.Name = "HoverScale"
		sc.Parent = btn
	end

	table.insert(bound, { btn = btn, base = base, sc = sc, stroke = stroke, strokeBase = strokeBase })

	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, INFO, { BackgroundColor3 = hover }):Play()
		TweenService:Create(sc, INFO, { Scale = 1.04 }):Play()
		if stroke then TweenService:Create(stroke, INFO, { Transparency = 0.2 }):Play() end
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, INFO, { BackgroundColor3 = base }):Play()
		TweenService:Create(sc, INFO, { Scale = 1 }):Play()
		if stroke then TweenService:Create(stroke, INFO, { Transparency = strokeBase }):Play() end
	end)
	btn.MouseButton1Down:Connect(function()
		TweenService:Create(sc, TweenInfo.new(0.08), { Scale = 0.96 }):Play()
	end)
	btn.MouseButton1Up:Connect(function()
		TweenService:Create(sc, TweenInfo.new(0.1), { Scale = 1.04 }):Play()
	end)
end

-- ============================================================
-- Tienda: tarjetas generadas desde SHOP_ITEMS
-- ============================================================
local toast = Instance.new("TextLabel")
toast.Name = "Toast"
toast.AnchorPoint = Vector2.new(0.5, 1)
toast.Position = UDim2.new(0.5, 0, 1, -16)
toast.Size = UDim2.fromOffset(280, 34)
toast.BackgroundColor3 = Color3.new(0, 0, 0)
toast.BackgroundTransparency = 1
toast.TextTransparency = 1
toast.Font = Enum.Font.GothamBold
toast.TextSize = 14
toast.Text = ""
toast.ZIndex = 20
toast.Parent = shopPanel
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = toast
end

local toastToken = 0
local function showToast(text, color)
	toastToken += 1
	local my = toastToken
	toast.Text = text
	toast.TextColor3 = color
	toast.BackgroundTransparency = 0.25
	toast.TextTransparency = 0
	task.delay(2, function()
		if toastToken ~= my then return end
		TweenService:Create(toast, TweenInfo.new(0.4), { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
	end)
end

local function newLabel(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.ZIndex = 12
	for k, v in pairs(props) do l[k] = v end
	l.Parent = parent
	return l
end

for i, item in ipairs(SHOP_ITEMS) do
	local card = Instance.new("Frame")
	card.Name = item.id
	card.LayoutOrder = i
	card.BackgroundColor3 = Color3.fromRGB(38, 46, 32)
	card.BorderSizePixel = 0
	card.ZIndex = 11
	card.Parent = shopItems

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Color = item.color
	stroke.Thickness = 1.5
	stroke.Transparency = 0.6
	stroke.Parent = card

	newLabel(card, { Name = "Icon", Position = UDim2.new(0, 0, 0, 12), Size = UDim2.new(1, 0, 0, 56),
		Font = Enum.Font.GothamBold, TextSize = 44, TextColor3 = Color3.new(1, 1, 1), Text = item.icon })
	newLabel(card, { Name = "Name", Position = UDim2.new(0, 8, 0, 74), Size = UDim2.new(1, -16, 0, 22),
		Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = Color3.new(1, 1, 1), Text = item.name, TextTruncate = Enum.TextTruncate.AtEnd })
	newLabel(card, { Name = "Price", Position = UDim2.new(0, 0, 0, 98), Size = UDim2.new(1, 0, 0, 20),
		Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = GOLD, Text = "\u{1F4B0} " .. item.price })

	local buy = Instance.new("TextButton")
	buy.Name = "BuyBtn"
	buy.AnchorPoint = Vector2.new(0.5, 1)
	buy.Position = UDim2.new(0.5, 0, 1, -12)
	buy.Size = UDim2.new(1, -24, 0, 34)
	buy.BackgroundColor3 = item.color
	buy.BorderSizePixel = 0
	buy.ZIndex = 12
	buy.Font = Enum.Font.GothamBold
	buy.TextSize = 14
	buy.TextColor3 = Color3.new(1, 1, 1)
	buy.Text = "COMPRAR"
	buy.Parent = card
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0, 10)
	bc.Parent = buy
	local bs = Instance.new("UIStroke")
	bs.Name = "Stroke"
	bs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	bs.Color = Color3.new(1, 1, 1)
	bs.Thickness = 1.5
	bs.Transparency = 0.7
	bs.Parent = buy

	bindButton(buy)
	buy.MouseButton1Click:Connect(function()
		local remote = ReplicatedStorage:FindFirstChild("PurchaseItem")
		if remote and remote:IsA("RemoteEvent") then
			remote:FireServer(item.id)
			showToast("Solicitud enviada: " .. item.name, OK_COLOR)
		else
			showToast("Pr\u{00F3}ximamente", GOLD)
		end
	end)
end

-- ============================================================
-- Codigos
-- ============================================================
local function setMessage(text, color)
	codeMsg.Text = text
	codeMsg.TextColor3 = color
end

codeInput:GetPropertyChangedSignal("Text"):Connect(function()
	local clean = string.upper(codeInput.Text):gsub("[^%w_%-]", "")
	clean = string.sub(clean, 1, 24)
	if clean ~= codeInput.Text then
		codeInput.Text = clean
	end
end)

local redeeming = false
local function redeem()
	if redeeming then return end
	local code = codeInput.Text
	if code == "" then
		setMessage("Escribe un c\u{00F3}digo primero.", GOLD)
		return
	end

	local rf = ReplicatedStorage:FindFirstChild("RedeemCode")
	if not (rf and rf:IsA("RemoteFunction")) then
		setMessage("Los c\u{00F3}digos a\u{00FA}n no est\u{00E1}n disponibles.", GOLD)
		return
	end

	redeeming = true
	setMessage("Comprobando...", Color3.fromRGB(190, 200, 175))
	local ok, success, msg = pcall(function()
		return rf:InvokeServer(code)
	end)
	redeeming = false

	if not ok then
		setMessage("No se pudo conectar. Int\u{00E9}ntalo de nuevo.", ERR_COLOR)
	elseif success then
		setMessage(msg or "\u{00A1}C\u{00F3}digo canjeado!", OK_COLOR)
		codeInput.Text = ""
	else
		setMessage(msg or "C\u{00F3}digo inv\u{00E1}lido.", ERR_COLOR)
	end
end

redeemBtn.MouseButton1Click:Connect(redeem)
codeInput.FocusLost:Connect(function(enterPressed)
	if enterPressed then redeem() end
end)

-- ============================================================
-- Escala responsiva de los paneles (PC / movil)
-- ============================================================
local scales = {}
for _, p in ipairs(panels) do
	scales[p] = p:WaitForChild("UIScale", 5)
end

local function baseScale()
	local vp = camera.ViewportSize
	return math.clamp(math.min(vp.X / 820, vp.Y / 560), 0.5, 1.25)
end

local function applyScale()
	local s = baseScale()
	for _, ui in pairs(scales) do ui.Scale = s end
end
applyScale()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyScale)

-- Animacion "pop" al abrir un panel
local function popIn(p)
	local ui = scales[p]
	if not ui then return end
	local v = Instance.new("NumberValue")
	v.Value = 0.88
	local conn = v.Changed:Connect(function(x) ui.Scale = baseScale() * x end)
	local tw = TweenService:Create(v, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Value = 1 })
	tw.Completed:Connect(function()
		conn:Disconnect()
		v:Destroy()
		ui.Scale = baseScale()
	end)
	ui.Scale = baseScale() * 0.88
	tw:Play()
end

local function showPanel(target)
	for _, p in ipairs(panels) do p.Visible = (p == target) end
	popIn(target)
end

-- ============================================================
-- Hover en todos los botones
-- ============================================================
for _, b in ipairs({ playBtn, shopBtn, codesBtn, soloBtn, multiBtn, modeBack, shopBack, codesBack, redeemBtn }) do
	bindButton(b)
end

-- ============================================================
-- Estado original (para fade-out y restaurar al volver)
-- ============================================================
local saved = {}
for _, d in ipairs(bg:GetDescendants()) do
	if d:IsA("TextButton") or d:IsA("TextLabel") or d:IsA("TextBox") then
		saved[d] = { BackgroundTransparency = d.BackgroundTransparency, TextTransparency = d.TextTransparency }
	elseif d:IsA("ScrollingFrame") then
		saved[d] = { BackgroundTransparency = d.BackgroundTransparency, ScrollBarImageTransparency = d.ScrollBarImageTransparency }
	elseif d:IsA("Frame") then
		saved[d] = { BackgroundTransparency = d.BackgroundTransparency }
	elseif d:IsA("UIStroke") then
		saved[d] = { Transparency = d.Transparency }
	end
end
saved[bg] = { BackgroundTransparency = bg.BackgroundTransparency }

local function restore()
	for obj, props in pairs(saved) do
		if obj.Parent then
			for k, v in pairs(props) do obj[k] = v end
		end
	end
	for _, b in ipairs(bound) do
		b.btn.BackgroundColor3 = b.base
		b.sc.Scale = 1
		if b.stroke then b.stroke.Transparency = b.strokeBase end
	end
end

-- ============================================================
-- Particulas de aceite
-- ============================================================
local function spawnOilDrop()
	local drop = Instance.new("Frame")
	drop.BackgroundColor3 = Color3.fromRGB(240, 200, 90)
	drop.BackgroundTransparency = math.random(70, 90) / 100
	drop.BorderSizePixel = 0
	drop.ZIndex = 1
	local size = math.random(8, 22)
	drop.Size = UDim2.fromOffset(size, size)
	local x = math.random(0, 100) / 100
	drop.Position = UDim2.new(x, 0, 1.1, 0)
	drop.Parent = particles
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = drop

	local tween = TweenService:Create(drop, TweenInfo.new(math.random(6, 12), Enum.EasingStyle.Linear), {
		Position = UDim2.new(x, 0, -0.15, 0)
	})
	tween:Play()
	tween.Completed:Connect(function() drop:Destroy() end)
end

task.spawn(function()
	while gui.Parent do
		if gui.Enabled then spawnOilDrop() end
		task.wait(math.random(30, 70) / 100)
	end
end)

-- Flotado sutil del titulo
task.spawn(function()
	while gui.Parent do
		local up = TweenService:Create(title, TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Position = UDim2.new(0, 20, 0, 20) })
		up:Play(); up.Completed:Wait()
		local down = TweenService:Create(title, TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Position = UDim2.new(0, 20, 0, 28) })
		down:Play(); down.Completed:Wait()
	end
end)

-- ============================================================
-- Animacion de entrada
-- ============================================================
local function playIntro()
	restore()
	for _, p in ipairs(panels) do p.Visible = (p == panel) end
	applyScale()

	local panelStroke = panel:FindFirstChildOfClass("UIStroke")

	-- estado inicial
	panel.Position = UDim2.new(0.5, 0, 0.5, 36)
	panel.BackgroundTransparency = 1
	if panelStroke then panelStroke.Transparency = 1 end
	title.TextTransparency = 1
	subtitle.TextTransparency = 1
	divider.BackgroundTransparency = 1
	for _, b in ipairs(mainButtons) do
		b.BackgroundTransparency = 1
		b.TextTransparency = 1
		local s = b:FindFirstChild("Stroke")
		if s then s.Transparency = 1 end
		b.HoverScale.Scale = 0.85
	end

	TweenService:Create(panel, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = saved[panel].BackgroundTransparency,
	}):Play()
	if panelStroke then
		TweenService:Create(panelStroke, TweenInfo.new(0.5), { Transparency = saved[panelStroke].Transparency }):Play()
	end

	task.wait(0.15)
	TweenService:Create(title, TweenInfo.new(0.4), { TextTransparency = 0 }):Play()
	TweenService:Create(subtitle, TweenInfo.new(0.4), { TextTransparency = 0 }):Play()
	TweenService:Create(divider, TweenInfo.new(0.4), { BackgroundTransparency = saved[divider].BackgroundTransparency }):Play()

	for _, b in ipairs(mainButtons) do
		task.wait(0.09)
		TweenService:Create(b, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			BackgroundTransparency = 0,
			TextTransparency = 0,
		}):Play()
		TweenService:Create(b.HoverScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		local s = b:FindFirstChild("Stroke")
		if s then TweenService:Create(s, TweenInfo.new(0.4), { Transparency = saved[s].Transparency }):Play() end
	end
end

gui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if gui.Enabled then playIntro() end
end)
if gui.Enabled then task.spawn(playIntro) end

-- ============================================================
-- Fade out al empezar partida
-- ============================================================
local function fadeOut()
	local info = TweenInfo.new(0.5, Enum.EasingStyle.Quad)
	for obj, props in pairs(saved) do
		if obj.Parent then
			local goal = {}
			for k in pairs(props) do goal[k] = 1 end
			TweenService:Create(obj, info, goal):Play()
		end
	end
	task.wait(0.55)
	gui.Enabled = false
end

-- ============================================================
-- Navegacion
-- ============================================================
playBtn.MouseButton1Click:Connect(function() showPanel(modePanel) end)
shopBtn.MouseButton1Click:Connect(function() showPanel(shopPanel) end)
codesBtn.MouseButton1Click:Connect(function()
	setMessage("", Color3.new(1, 1, 1))
	showPanel(codesPanel)
end)

for _, b in ipairs({ modeBack, shopBack, codesBack }) do
	b.MouseButton1Click:Connect(function() showPanel(panel) end)
end

soloBtn.MouseButton1Click:Connect(function()
	startEvent:FireServer("solo")
	fadeOut()
end)

multiBtn.MouseButton1Click:Connect(function()
	startEvent:FireServer("multi")
	fadeOut()
end)
