-- ShieldAbilities (ModuleScript, ReplicatedStorage)
-- HABILIDADES de los escudos (tecla R). Solo las RARAS tienen habilidad; las comunes son estetica pura.
-- Cada habilidad describe que efecto tendria ese escudo sobre el bloqueo o el parry. El texto que ve
-- el jugador sale de A.Describe, generado a partir de los numeros, asi que nunca se desajusta.
--
-- OJO: ESTO AUN NO ESTA CONECTADO AL COMBATE. OilCombat lee CFG.Stamina.BlockDrainPerSec y
-- CFG.Parry.Window directamente y no consulta este modulo, asi que ninguna habilidad cambia nada en la
-- pelea todavia. Para que sirvan de algo habria que aplicar A.ForPlayer(jugador) dentro de OilCombat.
--
-- COMO FUNCIONA UN EFECTO
--   Hay dos tipos (ver A.Keys): "mul" multiplica el valor base de OilConfig (0.85 = 15 % menos, 1.15 = 15 % mas)
--   y "add" suma una cantidad (segundos, stamina o equilibrio). Los combatientes solo conocen las claves
--   de A.Keys; cualquier otra se ignora y los valores se acotan en Sanitize, asi que un error de dedo nunca
--   rompe el combate.
--
-- ANADIR UNA HABILIDAD O UN RANGO NUEVO DE CAJAS
--   1. Crea el escudo en CosmeticsShared (boxOnly = true, box = "<id de la caja>", rarity = "...").
--   2. Anade aqui su entrada en A.List SOLO si la rareza es raro o mejor: name + effects.
--   3. Si es una rareza nueva (poco_comun, epico, legendario...) anade su tope en A.Budget, mas alto.
--   El test ShieldAbilities_Test comprueba que solo las raras tienen habilidad, que usan claves conocidas,
--   que ninguna se pasa del tope de su rareza y que ninguna lo agota.
--
-- Nota: OilBlockVFX solo lee CosShield para el ASPECTO (ShieldSkins). No lee ningun valor de habilidad.
--
-- ORIGEN: rescatado del lugar el 2026-10-11 (checkpoint/2026-10-11-escudos, FNV 3684004711,
-- verificado byte a byte). La logica es la del original sin tocar ni una linea. Lo unico que
-- cambio es la codificacion (el original estava en Latin-1 y aqui va en UTF-8) y estas lineas.
--
-- VALOR CORREGIDO: el original de escudo_tormenta traia reflectBalance = 8, que con el
-- OilConfig actual da una fuerza de 0.403 y se pasa del tope de 0.40. Este archivo ya trae
-- el 6. El test rescatado.EXPECTaba 8 y fallaba; el test de UnitTest usa 6. Ver el MANIFEST
-- del checkpoint para la tabla completa.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CFG = require(ReplicatedStorage:WaitForChild("OilConfig"))

local A = {}

-- Efectos que entiende el combate. min/max acotan el valor; norm da la escala para medir su fuerza.
local function mul()
	return { kind = "mul", min = 0.25, max = 2.5 }
end
local function add(max, norm)
	return { kind = "add", min = 0, max = max, norm = norm }
end

A.Keys = {
	-- Bloqueo
	blockDrain = mul(),      -- stamina que gasta SOSTENER la guardia (x)
	blockHitCost = mul(),    -- stamina que cuesta cada golpe bloqueado (x)
	blockStartCost = mul(),  -- stamina que cuesta levantar la guardia (x)
	blockForce = mul(),      -- empuje que recibes estando en guardia (x)
	blockBalance = mul(),    -- equilibrio que pierdes al bloquear (x)
	blockCooldown = mul(),   -- espera para volver a levantar la guardia tras soltarla (x)
	guardBreakDaze = mul(),  -- aturdimiento al romperse la guardia (x)
	-- Parry
	parryDaze = mul(),       -- aturdimiento que provoca tu parry al atacante (x)
	counterForce = mul(),    -- fuerza del contraataque tras el parry (x)
	parryWindow = add(0.25, function(c) return c.Parry.Window end),             -- margen del parry (+segundos)
	counterWindow = add(2, function(c) return c.Parry.CounterWindow end),       -- duracion del contraataque (+segundos)
	parryStamina = add(50, function(c) return c.Stamina.Max end),               -- stamina que devuelve el parry (+)
	parryBalance = add(60, function(c) return c.Balance.Max end),               -- equilibrio que devuelve el parry (+)
	-- Contraataque pasivo
	reflectBalance = add(30, function(c) return c.Balance.Damage.push end),     -- equilibrio que pierde el atacante cuando bloqueas (+)
}

-- Orden fijo para generar los textos
A.Order = {
	"blockDrain", "blockHitCost", "blockStartCost", "blockForce", "blockBalance", "blockCooldown", "guardBreakDaze",
	"parryWindow", "parryStamina", "parryBalance", "parryDaze", "counterWindow", "counterForce", "reflectBalance",
}

-- Tope de fuerza total (A.Strength) por rareza. Solo aplica a los escudos que tienen habilidad.
-- comun se queda por si una caja futura mete alguna comun con un efecto leve; hoy ninguna la tiene.
-- Para una caja con mejores habilidades, anade aqui su rareza con un tope mayor.
A.Budget = {
	comun = 0.25,
	raro = 0.40,
}

-- ===== Habilidades =====
-- Solo los escudos RAROS tienen habilidad. Los comunes de la caja (y el Azul Clasico) se quedan en
-- estetica: la rareza tiene que notarse tambien en la pelea, no solo en el color.
A.List = {
	-- Raros: uno o dos efectos, utiles pero medidos. El tope es 0.40 y el mas fuerte llega a 0.38,
	-- de forma que las cajas futuras (epico, legendario) puedan subir sin retocar estos.
	escudo_sol = { name = "Resplandor", effects = { parryWindow = 0.04, parryStamina = 8 } },
	escudo_laureles = { name = "Laureles", effects = { blockHitCost = 0.92, parryBalance = 20 } },
	escudo_tormenta = { name = "Descarga", effects = { blockForce = 0.93, reflectBalance = 6 } },
	escudo_constelacion = { name = "Guía Astral", effects = { counterWindow = 0.35, counterForce = 1.10 } },
	escudo_espectral = { name = "Llama Fantasma", effects = { blockDrain = 0.92, guardBreakDaze = 0.70 } },
}

-- ===== Utilidades =====
local NONE = table.freeze({})

-- Deja solo claves conocidas, numeros validos y dentro de rango
function A.Sanitize(effects)
	local out = {}
	if type(effects) ~= "table" then
		return out
	end
	for key, spec in pairs(A.Keys) do
		local v = effects[key]
		if type(v) == "number" and v == v then -- v == v descarta NaN
			out[key] = math.clamp(v, spec.min, spec.max)
		end
	end
	return out
end

-- Efectos ya saneados de cada habilidad (se calculan una vez)
local resolved = {}
for id, ab in pairs(A.List) do
	resolved[id] = table.freeze(A.Sanitize(ab.effects))
end

function A.Get(id)
	return A.List[id]
end

-- Efectos del escudo "id" (tabla vacia si no tiene habilidad). Solo lectura.
function A.Effects(id)
	return resolved[id] or NONE
end

-- Efectos del escudo que lleva equipado el jugador (atributo CosShield, fijado por el servidor)
function A.ForPlayer(player)
	if typeof(player) ~= "Instance" then
		return NONE
	end
	local id = player:GetAttribute("CosShield")
	if type(id) ~= "string" then
		return NONE
	end
	return A.Effects(id)
end

-- "Fuerza" total de unos efectos, comparable con A.Budget. Un multiplicador cuenta |1 - x|;
-- una suma cuenta lo que supone respecto a su valor base de OilConfig.
function A.Strength(effects)
	local total = 0
	for key, spec in pairs(A.Keys) do
		local v = effects and effects[key]
		if v then
			if spec.kind == "mul" then
				total += math.abs(1 - v)
			else
				total += v / spec.norm(CFG)
			end
		end
	end
	return total
end

-- ===== Texto para el jugador (generado desde los numeros) =====
local function pct(v)
	return math.floor(math.abs(1 - v) * 100 + 0.5)
end

local function lessMore(v)
	return v < 1 and "menos" or "m" .. string.char(0xE1) .. "s"
end

-- 0.05 -> "0,05"   0.5 -> "0,5"   1 -> "1"
local function num(v)
	local s = string.format("%.2f", v)
	s = (s:gsub("(%.%d-)0+$", "%1"))
	s = (s:gsub("%.$", ""))
	return (s:gsub("%.", ","))
end

local PHRASE = {
	blockDrain = function(v) return string.format("sostener la guardia gasta %d %%%% %s stamina", pct(v), lessMore(v)) end,
	blockHitCost = function(v) return string.format("bloquear un golpe cuesta %d %%%% %s stamina", pct(v), lessMore(v)) end,
	blockStartCost = function(v) return string.format("levantar la guardia cuesta %d %%%% %s stamina", pct(v), lessMore(v)) end,
	blockForce = function(v) return string.format("el bloqueo te empuja %d %%%% %s", pct(v), lessMore(v)) end,
	blockBalance = function(v) return string.format("bloquear te quita %d %%%% %s equilibrio", pct(v), lessMore(v)) end,
	blockCooldown = function(v)
		if v < 1 then
			return string.format("vuelves a levantar la guardia %d %%%% antes", pct(v))
		end
		return string.format("tardas %d %%%% m" .. string.char(0xE1) .. "s en volver a levantar la guardia", pct(v))
	end,
	guardBreakDaze = function(v)
		if v < 1 then
			return string.format("si te rompen la guardia te recuperas %d %%%% antes", pct(v))
		end
		return string.format("la guardia rota te aturde %d %%%% m" .. string.char(0xE1) .. "s", pct(v))
	end,
	parryDaze = function(v) return string.format("tu parry aturde %d %%%% %s", pct(v), lessMore(v)) end,
	counterForce = function(v)
		if v >= 1 then
			return string.format("el contraataque tras un parry es %d %%%% m" .. string.char(0xE1) .. "s fuerte", pct(v))
		end
		return string.format("el contraataque tras un parry es %d %%%% m" .. string.char(0xE1) .. "s d" .. string.char(0xE9) .. "bil", pct(v))
	end,
	parryWindow = function(v) return string.format("el parry tiene %s s m" .. string.char(0xE1) .. "s de margen", num(v)) end,
	counterWindow = function(v) return string.format("el contraataque tras un parry dura %s s m" .. string.char(0xE1) .. "s", num(v)) end,
	parryStamina = function(v) return string.format("un parry te devuelve %d de stamina", math.floor(v + 0.5)) end,
	parryBalance = function(v) return string.format("un parry te devuelve %d de equilibrio", math.floor(v + 0.5)) end,
	reflectBalance = function(v) return string.format("cada golpe bloqueado resta %d de equilibrio al rival", math.floor(v + 0.5)) end,
}

-- "Aguante: Sostener la guardia gasta 15 % menos stamina."  (nil si el escudo no tiene habilidad)
function A.Describe(id)
	local ab = A.List[id]
	if not ab then
		return nil
	end
	local fx = A.Effects(id)
	local parts = {}
	for _, key in ipairs(A.Order) do
		if fx[key] and PHRASE[key] then
			table.insert(parts, PHRASE[key](fx[key]))
		end
	end
	if #parts == 0 then
		return ab.name
	end
	local text = table.concat(parts, "; ")
	return ab.name .. ": " .. text:sub(1, 1):upper() .. text:sub(2) .. "."
end

return A