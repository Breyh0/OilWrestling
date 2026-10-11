-- inventario.luau — genera el manifiesto de la escena.
--
-- La escena (Workspace, StarterGui, SoundService) NO esta en git: Rojo no la gestiona
-- y nadie la versiona. Esto no la respalda, la **vigila**: saca una huella y un
-- inventario para que cualquier cambio se note en el diff de git.
--
-- Uso:
--   1. Pegar este archivo en un Script de Studio y darle a Run, o pedir a la IA que
--      lo ejecute con execute_luau en contexto Edit.
--   2. El texto sale por consola (o el MCP lo devuelve). Guardarlo en
--      escena/MANIFIEST-ESCENA.md.
--   3. Commit. A partir de ahi, cada cambio de escena se ve como un diff.
--
-- NO va en src/: Rojo sincroniza src/ hacia el juego y crearia un script que no debe
-- existir en el lugar.

local function mul32(x, y)
	local xl, xh = x % 65536, (x - x % 65536) / 65536
	local yl, yh = y % 65536, (y - y % 65536) / 65536
	local ll = xl * yl
	local lh = xl * yh + xh * yl
	local hh = xh * yh
	return (ll + (lh % 65536) * 65536 + (hh % 65536) * 4294967296) % 4294967296
end

local function fnv(s)
	local h = 2166136261
	for i = 1, #s do
		h = bit32.bxor(h, string.byte(s, i))
		h = mul32(h, 16777619)
	end
	return h
end

local function cuenta(o)
	local n = 0
	local f
	f = function(x)
		n = n + 1
		for _, c in ipairs(x:GetChildren()) do
			f(c)
		end
	end
	f(o)
	return n
end

local L = {}
local function add(s)
	table.insert(L, s)
end

-- Fila de ancho variable: las tablas salen con exactamente las columnas que se pasan.
local function fila(...)
	local n = select("#", ...)
	local celdas = {}
	for i = 1, n do
		local v = select(i, ...)
		celdas[i] = tostring(v == nil and "-" or v)
	end
	add("| " .. table.concat(celdas, " | ") .. " |")
end

local function cabecera(...)
	local celdas = {}
	for i = 1, select("#", ...) do
		celdas[i] = tostring((select(i, ...)))
	end
	add("| " .. table.concat(celdas, " | ") .. " |")
	add("|" .. string.rep("---|", #celdas))
end

local function ordenados(padre)
	local hijos = {}
	for _, c in ipairs(padre:GetChildren()) do
		table.insert(hijos, c)
	end
	table.sort(hijos, function(a, b)
		return a.Name < b.Name
	end)
	return hijos
end

local SG = game:GetService("StarterGui")
local SS = game:GetService("SoundService")

add("# Manifiesto de escena")
add("")
add("Generado con `escena/inventario.luau`. **La escena no esta en git**: esto la vigila,")
add("no la respalda. Para restaurar de verdad hay que publicar el place.")
add("")
add("Huella: `(se calcula al final)`")
add("")
add("La huella es el FNV-1a de 32 de este mismo documento con la linea de la huella")
add("sustituida por `(se calcula al final)`. Se puede comprobar en cualquier momento:")
add("")
add("```")
add("python -c \"d=open('escena/MANIFIEST-ESCENA.md','rb').read(); h=2166136261; [None for b in d if not (h:=((h^b)*16777619)%4294967296)]; print(h)\"")
add("```")
add("")

-- ------------------------------------------------------------------ Workspace
add("## Workspace (raíz)")
add("")
cabecera("Objeto", "Clase", "Objetos", "Notas")
for _, o in ipairs(ordenados(workspace)) do
	local notas = ""
	if o:IsA("Model") then
		local partes, humans, anims = 0, 0, 0
		for _, d in ipairs(o:GetDescendants()) do
			if d:IsA("BasePart") then
				partes = partes + 1
			end
			if d:IsA("Humanoid") then
				humans = humans + 1
			end
			if d:IsA("Animation") or d:IsA("AnimationController") then
				anims = anims + 1
			end
		end
		if partes > 0 then
			notas = string.format("%d partes, %d Humanoid, %d Animation", partes, humans, anims)
		end
	end
	fila(o.Name, o.ClassName, cuenta(o), notas)
end
add("")
add("**Total en Workspace: " .. #workspace:GetDescendants() .. " objetos**")
add("")

-- ---------------------------------------------------------------- El ring
local ring = workspace:FindFirstChild("OilWrestlingRing")
if ring then
	add("## OilWrestlingRing")
	add("")
	cabecera("Parte", "Clase", "Tamaño", "Posición", "Material / Color", "Texturas")
	for _, p in ipairs(ordenados(ring)) do
		if p:IsA("BasePart") then
			local tex = 0
			for _, c in ipairs(p:GetChildren()) do
				if c:IsA("Texture") or c:IsA("Decal") then
					tex = tex + 1
				end
			end
			fila(
				p.Name,
				string.format("%s %s", p.ClassName, tostring(p.Shape):gsub("Enum%.PartType%.", "")),
				string.format("%.1f × %.1f × %.1f", p.Size.X, p.Size.Y, p.Size.Z),
				string.format("%.0f, %.1f, %.0f", p.Position.X, p.Position.Y, p.Position.Z),
				string.format("%s / %s", tostring(p.Material):gsub("Enum%.Material%.", ""), tostring(p.Color)),
				tex > 0 and (tex .. " textura(s)") or "ninguna"
			)
		end
	end
	add("")
end

-- ---------------------------------------------------------------- La GUI
add("## StarterGui")
add("")
cabecera("ScreenGui", "Elementos", "Habilitado")
for _, g in ipairs(ordenados(SG)) do
	if g:IsA("ScreenGui") then
		fila(g.Name, cuenta(g), tostring(g.Enabled))
	end
end
add("")
add("**Total en StarterGui: " .. #SG:GetDescendants() .. " objetos**")
add("")

-- La MainMenu es la que más cambia: sus hijos directos, uno a uno.
local menu = SG:FindFirstChild("MainMenu")
local fondo = menu and menu:FindFirstChild("Background")
if fondo then
	add("### MainMenu > Background (hijos directos)")
	add("")
	cabecera("Nombre", "Clase", "Tamaño", "Visible")
	for _, c in ipairs(ordenados(fondo)) do
		local vis, tam = "-", "-"
		if c:IsA("GuiObject") then
			vis = tostring(c.Visible)
			tam = string.format("%.0f × %.0f", math.abs(c.Size.X.Offset), math.abs(c.Size.Y.Offset))
		end
		fila(c.Name, c.ClassName, tam, vis)
	end
	add("")
end

-- ---------------------------------------------------------------- Sonidos
add("## Sonidos (SoundService)")
add("")
cabecera("Ruta", "SoundId", "Volumen", "Looped")
local function listaSonidos(padre, prefijo)
	for _, c in ipairs(ordenados(padre)) do
		local ruta = (prefijo == "" and c.Name) or (prefijo .. "/" .. c.Name)
		if c:IsA("Sound") then
			fila(ruta, tostring(c.SoundId), string.format("%.2f", c.Volume), tostring(c.Looped))
		elseif c:IsA("SoundGroup") then
			fila(ruta .. " (grupo)", "-", string.format("%.2f", c.Volume), "-")
			listaSonidos(c, ruta)
		elseif c:IsA("Folder") then
			fila(ruta .. " (carpeta)")
			listaSonidos(c, ruta)
		end
	end
end
listaSonidos(SS, "")
add("")

-- ---------------------------------------------------------------- Plantilla
local ft = game:GetService("ServerStorage"):FindFirstChild("FighterTemplate")
if ft then
	add("## FighterTemplate (hitbox)")
	add("")
	cabecera("Parte", "Tamaño", "Colisión", "Contacto")
	for _, p in ipairs(ordenados(ft)) do
		if p:IsA("BasePart") then
			fila(p.Name, string.format("%.1f × %.1f × %.1f", p.Size.X, p.Size.Y, p.Size.Z), tostring(p.CanCollide), tostring(p.CanTouch))
		end
	end
	add("")
end

-- ---------------------------------------------------------------- Sospechosos
local sospechosos = {}
for _, c in ipairs(ordenados(workspace)) do
	local conocido = c:IsA("Folder") or c:IsA("Model") or c.Name == "Baseplate"
		or c.Name == "Terrain" or c:IsA("SpawnLocation") or c:IsA("Camera")
	if not conocido then
		sospechosos[#sospechosos + 1] = string.format("  %s (%s) en %s", c.Name, c.ClassName, tostring(c.Position))
	end
end
if #sospechosos > 0 then
	add("## Objetos sueltos en la raíz (revisar)")
	add("")
	add("No son Folder ni Model, y no son Baseplate ni Terrain. Si no sabes qué son,")
	add("pregunta antes de borrarlos: pueden ser de alguien.")
	add("")
	for _, s in ipairs(sospechosos) do
		add(s)
	end
	add("")
end

-- La huella se calcula sobre el propio documento, con la linea de la huella sustituida
-- por su marcador. Asi cualquiera puede verificarla contra el archivo, sin Studio.
--
-- OJO: find con plain=true, no gsub. Los parentesis de MARCA son caracteres magicos
-- en un patron de Lua: con gsub no casaba y la huella se quedaba sin poner.
local function reemplaza(texto, de, a)
	local i = texto:find(de, 1, true)
	if not i then
		return texto
	end
	return texto:sub(1, i - 1) .. a .. texto:sub(i + #de)
end

local MARCA = "(se calcula al final)"
local texto = table.concat(L, "\n")
local limpio = reemplaza(texto, "`" .. MARCA .. "`", MARCA)
local h = fnv(limpio)
texto = reemplaza(texto, "`" .. MARCA .. "`", "`" .. string.format("%d", h) .. "`")
print(texto)
return texto
