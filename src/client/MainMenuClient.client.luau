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
-- Tienda: las tarjetas las PINTA lo que el servidor manda
--
-- Antes esta tabla vivia aqui, en el cliente, con los precios dentro. Eso era justo el
-- fallo que marca lucha-feature: si el cliente decide el precio, el precio se puede
-- cambiar. Ahora el catalogo viene de ProgressionService.GetCatalog(), que lo arma desde
-- CosmeticsShared, y el boton solo manda un id.
-- ============================================================
local purchaseEvent = ReplicatedStorage:WaitForChild("PurchaseItem")
local equipEvent = ReplicatedStorage:WaitForChild("EquipItem")
local requestEvent = ReplicatedStorage:WaitForChild("RequestProgression")
local notifyEvent = ReplicatedStorage:WaitForChild("MissionNotify")
local updateEvent = ReplicatedStorage:WaitForChild("UpdateProgression")

local RARITY_COLOR = {
	comun = Color3.fromRGB(190, 190, 180),
	poco_comun = Color3.fromRGB(120, 200, 120),
	raro = Color3.fromRGB(90, 160, 255),
	epico = Color3.fromRGB(190, 110, 255),
	legendario = Color3.fromRGB(255, 190, 60),
}

local RANURAS = {
	{ id = "shield", name = "Escudos", emoji = "\u{1F6E1}" },
	{ id = "victory", name = "Victoria", emoji = "\u{1F451}" },
	{ id = "ringout", name = "Ring-out", emoji = "\u{1F4A7}" },
}

local catalogo = {}      -- lo que manda el servidor
local miCartera = {}     -- owned
local miEquipado = {}    -- eq
local ranuraAbierta = "shield"
local filtroTabla = "todos"

local toast = Instance.new("TextLabel")
toast.Name = "Toast"
toast.AnchorPoint = Vector2.new(0.5, 1)
toast.Position = UDim2.new(0.5, 0, 1, -16)
toast.Size = UDim2.fromOffset(300, 34)
toast.BackgroundColor3 = Color3.new(0, 0, 0)
toast.BackgroundTransparency = 1
toast.TextTransparency = 1
toast.Font = Enum.Font.GothamBold
toast.TextSize = 14
toast.Text = ""
toast.ZIndex = 30
toast.TextWrapped = true
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
	task.delay(2.4, function()
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

local function newButton(parent, props)
	local b = Instance.new("TextButton")
	b.BorderSizePixel = 0
	b.ZIndex = 12
	b.Font = Enum.Font.GothamBold
	b.TextSize = 13
	b.TextColor3 = Color3.new(1, 1, 1)
	for k, v in pairs(props) do b[k] = v end
	b.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = b
	return b
end

-- Barra de ranuras: los escudos son lo primero porque es lo que se ha pedido.
-- Va PEGADA AL PANEL, no dentro de la lista: pintar() borra todos los hijos de la lista,
-- y si la barra fuera uno mas se destruiria sola en el primer repintado.
local tabs = Instance.new("Frame")
tabs.Name = "Tabs"
tabs.BackgroundTransparency = 1
tabs.Size = UDim2.new(1, -56, 0, 28)
tabs.Position = UDim2.new(0, 28, 0, 64)
tabs.ZIndex = 12
tabs.Parent = shopPanel

-- La lista baja para dejarle sitio a la barra. Se ajusta en codigo porque el panel se
-- edita a mano en Studio y asi el script manda sobre las medidas de verdad.
shopItems.Position = UDim2.new(0, 28, 0, 98)
shopItems.Size = UDim2.new(1, -56, 1, -190)
do
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.HorizontalAlignment = Enum.HorizontalAlignment.Left
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, 6)
	l.Parent = tabs
end

-- La lista necesita un UIListLayout para APILAR las tarjetas. El ScrollingFrame de
-- Items se edita a mano en Studio y no traia ninguno: sin esto las ocho tarjetas se
-- dibujan unas encima de otras en (0,0) y solo se ve la ultima pintada.
--
-- Se guarda la referencia porque pintar() borra TODO lo que cuelgue de la lista, y el
-- layout tambien colgaria de ahi: si se destruyera, la segunda vuelta se amontonarian
-- todas otra vez y solo se veria un item.
local listaLayout = shopItems:FindFirstChildOfClass("UIListLayout")
if not listaLayout then
	listaLayout = Instance.new("UIListLayout")
	listaLayout.Name = "ListaLayout"
	listaLayout.FillDirection = Enum.FillDirection.Vertical
	listaLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listaLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listaLayout.Padding = UDim.new(0, 8)
	listaLayout.Parent = shopItems
end
shopItems.AutomaticCanvasSize = Enum.AutomaticSize.Y

local function filtrar()
	local lista = {}
	for _, it in ipairs(catalogo) do
		if it.slot == ranuraAbierta and (filtroTabla == "todos" or it.rarity == filtroTabla) then
			lista[#lista+1] = it
		end
	end
	return lista
end

local function pintar()
	-- Todo lo que cuelgue de la lista es contenido: tarjetas y el aviso de "no hay nada".
	-- Se borra sin mirar la clase; si se filtrara por Frame, el aviso (un TextLabel) se
	-- acumularia uno encima de otro en cada repintado. El layout se salta: es estructura.
	for _, h in ipairs(shopItems:GetChildren()) do
		if h ~= listaLayout then
			h:Destroy()
		end
	end

	local lista = filtrar()
	-- primero los que ya tienes, para no tener que buscarlos
	table.sort(lista, function(a, b)
		local fa, fb = miCartera[a.id] and 0 or 1, miCartera[b.id] and 0 or 1
		if fa ~= fb then return fa < fb end
		if a.price ~= b.price then return a.price < b.price end
		return a.id < b.id
	end)

	if #lista == 0 then
		newLabel(shopItems, {
			Name = "Vacio", Position = UDim2.new(0, 8, 0, 44), Size = UDim2.new(1, -16, 0, 30),
			Font = Enum.Font.Gotham, TextSize = 14, TextColor3 = Color3.fromRGB(160, 170, 150),
			Text = "No hay nada en esta ranura todavia.", TextWrapped = true,
		})
		return
	end

	for i, item in ipairs(lista) do
		local tinte = RARITY_COLOR[item.rarity] or RARITY_COLOR.comun
		local mio = miCartera[item.id] == true
		local puesto = miEquipado[item.slot] == item.id

		-- ALTURA_CARD: cabe el texto de la habilidad, que es lo que mas crece. Con 168 el
		-- precio se metia debajo del boton; con 212 habia medio cartel de hueco.
		local ALTO = 176

		local card = Instance.new("Frame")
		card.Name = item.id
		card.LayoutOrder = i
		card.BackgroundColor3 = Color3.fromRGB(38, 46, 32)
		card.BorderSizePixel = 0
		card.ZIndex = 11
		card.Size = UDim2.new(1, -8, 0, ALTO)
		card.Parent = shopItems
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 14)
		corner.Parent = card
		local stroke = Instance.new("UIStroke")
		stroke.Color = tinte
		stroke.Thickness = puesto and 3 or 1.5
		stroke.Transparency = 0.5
		stroke.Parent = card

		-- Icono a la izquierda, con el nombre y la rareza a su derecha: gasta menos alto
		-- que un icono centrado encima de todo.
		-- El color lo trae el escudo; si no lo tienes puesto, sale en gris.
		local iconColor = item.color or tinte
		newLabel(card, { Name = "Icon", Position = UDim2.new(0, 10, 0, 12), Size = UDim2.new(0, 44, 0, 44),
			Font = Enum.Font.GothamBold, TextSize = 30,
			TextColor3 = puesto and iconColor or Color3.fromRGB(150, 155, 145),
			Text = item.slot == "shield" and "\u{1F6E1}" or (item.slot == "victory" and "\u{1F451}" or "\u{1F4A7}") })

		newLabel(card, { Name = "Name", Position = UDim2.new(0, 60, 0, 14), Size = UDim2.new(1, -68, 0, 22),
			Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = Color3.new(1, 1, 1),
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = item.name, TextTruncate = Enum.TextTruncate.AtEnd })

		newLabel(card, { Name = "Raridad", Position = UDim2.new(0, 60, 0, 38), Size = UDim2.new(1, -68, 0, 16),
			Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = tinte,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = (item.rarity or "comun"):gsub("^%l", string.upper) })

		-- La habilidad, si la tiene. El texto lo genera ShieldAbilities desde los numeros,
		-- asi que si se cambia un numero de equilibrio el texto cambia solo.
		newLabel(card, { Name = "Hab", Position = UDim2.new(0, 12, 0, 64), Size = UDim2.new(1, -24, 0, 42),
			Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = Color3.fromRGB(190, 200, 175),
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = item.abilityText or item.desc or "", TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top })

		-- Precio o estado. Centrado a proposito: va encima de un boton del mismo ancho.
		newLabel(card, { Name = "Precio", Position = UDim2.new(0, 10, 0, 108), Size = UDim2.new(1, -20, 0, 18),
			Font = Enum.Font.GothamBold, TextSize = 13,
			TextColor3 = mio and OK_COLOR or GOLD,
			Text = puesto and "EN USO" or (mio and "EN CARTERA" or ("\u{1F4B0} " .. item.price)) })

		local boton
		if puesto then
			boton = newButton(card, { Name = "Btn", AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.new(1, -24, 0, 32),
				BackgroundColor3 = Color3.fromRGB(60, 70, 55), Text = "PUESTO", AutoButtonColor = false })
		elseif mio then
			boton = newButton(card, { Name = "Btn", AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.new(1, -24, 0, 32),
				BackgroundColor3 = tinte, Text = "EQUIPAR" })
		else
			boton = newButton(card, { Name = "Btn", AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.new(1, -24, 0, 32),
				BackgroundColor3 = Color3.fromRGB(200, 165, 60), Text = "COMPRAR" })
		end

		bindButton(boton)
		boton.MouseButton1Click:Connect(function()
			if puesto then return end
			-- Solo se manda el id. No se pinta ningun "Enviado": el unico aviso que sale
			-- es el del servidor, que es quien decide si la compra va o no.
			if mio then
				equipEvent:FireServer(item.id)
			else
				purchaseEvent:FireServer(item.id)
			end
		end)
	end

	-- Volver arriba al repintar: si no, cambiar de pestaña te deja a media lista y parece
	-- que falten items.
	shopItems.CanvasPosition = Vector2.new(0, 0)
end

-- Las pestañas se reparten el ancho de la barra. Se guardan para poder resaltar la
-- activa: sin esto el usuario no sabe de que ranura esta viendo los items.
local pestanas = {}
local TAB_TONO = Color3.fromRGB(45, 55, 40)
local TAB_ACTIVA = Color3.fromRGB(96, 116, 70)

local function marcarPestana()
	for _, r in ipairs(RANURAS) do
		local b = pestanas[r.id]
		if b then
			local activa = (r.id == ranuraAbierta)
			b.BackgroundColor3 = activa and TAB_ACTIVA or TAB_TONO
			b.TextColor3 = activa and Color3.new(1, 1, 1) or Color3.fromRGB(175, 185, 165)
			b.TextTransparency = activa and 0 or 0.35
		end
	end
end

for i, r in ipairs(RANURAS) do
	local b = newButton(tabs, { Name = r.id, LayoutOrder = i,
		Size = UDim2.new(1 / #RANURAS, -4, 1, 0), BackgroundColor3 = TAB_TONO,
		Text = r.emoji .. "  " .. r.name })
	pestanas[r.id] = b
	bindButton(b)
	b.MouseButton1Click:Connect(function()
		ranuraAbierta = r.id
		filtroTabla = "todos"
		marcarPestana()
		pintar()
	end)
end
marcarPestana()

-- Escuchar al servidor: el catalogo, la cartera y el resultado de comprar/equipar
notifyEvent.OnClientEvent:Connect(function(kind, data)
	if kind == "catalog" and type(data) == "table" and data.items then
		catalogo = data.items
		pintar()
	elseif kind == "shop" and type(data) == "table" then
		showToast(data.text or "", data.ok and OK_COLOR or ERR_COLOR)
	end
end)

updateEvent.OnClientEvent:Connect(function(d)
	if type(d) == "table" and type(d.cosm) == "table" then
		miCartera = d.cosm.owned or {}
		miEquipado = d.cosm.eq or {}
		pintar()
	end
end)

-- Pide estado y catalogo, con reintentos.
--
-- Por que reintentar: un RemoteEvent disparado antes de que el otro extremo este escuchando
-- se PIERDE, no se guarda. En Studio no hay DataStore, asi que el servidor termina de
-- cargar el progreso en milisegundos y puede tener todo listo antes de que este script
-- arranque. Con un solo disparo, la tienda se queda en "no hay nada" para siempre.
-- Los reintentos paran en cuanto llega el catalogo, y el servidor limita a 1 s por peticion.
local intentos = 0
local function pedirCatalogo()
	if catalogo and #catalogo > 0 then
		return -- ya llego: no se sigue preguntando
	end
	intentos += 1
	requestEvent:FireServer(true)
	if intentos < 4 then
		task.delay(1.5, pedirCatalogo)
	end
end
pedirCatalogo()


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
