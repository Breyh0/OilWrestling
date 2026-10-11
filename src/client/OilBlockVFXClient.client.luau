-- OilBlockVFXClient (cliente)
-- Conduce el OilBlockVFX: se engancha a cada luchador, avanza el animador cada frame y
-- le pasa los eventos fx del bloqueo. Es lo unico que hay en el cliente de este sistema:
-- el modulo dibuja y este script decide a quien y cuando.
--
-- RECONSTRUIDO el 2026-10-11. El modulo OilBlockVFX se rescue del lugar verificado byte a
-- byte (ver checkpoint/2026-10-11-escudos), pero el cliente que lo consume no estaba en
-- ningun respaldo: sin el, el modulo estaba ahi y nadie lo llamaba, y los escudos no se
-- veian. Esto no es una copia: se ha escrito leyendo la cabecera del propio modulo, que
-- decia "Lo usa StarterPlayerScripts.OilBlockVFXClient".
--
-- De donde salen los datos (todo esto ya lo publica el combate, no se anade nada):
--   OilCombat marca el personaje con la etiqueta "OilFighter" (CollectionService)
--   OilCombat pone los atributos Blocking / Act / ActT en el personaje
--   OilCombat manda los eventos fx por OilEvent: "block", "parry" y "guardbreak"
-- Por eso este script no necesita ningun remoto propio ni saber nada de la partida.
--
-- El color del escudo sale del atributo CosShield del personaje, que ShieldAbilities ya
-- sabe leer en el servidor. Todavia nadie lo fija (la tienda no existe todavia), asi que
-- sale el del escudo base. En cuanto la tienda escriba ese atributo, aqui se refleja solo.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local VFX = require(ReplicatedStorage:WaitForChild("OilBlockVFX"))
local Cosmetics = require(ReplicatedStorage:WaitForChild("CosmeticsShared"))

local eventRemote = ReplicatedStorage:WaitForChild("OilEvent")

local TAG = "OilFighter"

-- El escudo base, para cuando el jugador no lleva ninguno equipado.
local baseSkin = Cosmetics.ShieldSkin(Cosmetics.Defaults.shield)
local baseColor = baseSkin and baseSkin.color or nil

-- El color con el que se pinta el escudo de este luchador.
local function colorDe(char)
	local id = char:GetAttribute("CosShield")
	if type(id) ~= "string" then
		return baseColor
	end
	local skin = Cosmetics.ShieldSkin(id)
	return (skin and skin.color) or baseColor
end

local function ponerTinte(char)
	local c = VFX.get(char)
	if not c or not c.setTint then
		return
	end
	c:setTint(colorDe(char))
end

local function enganchar(char)
	if not char:IsA("Model") then
		return
	end
	local c = VFX.attach(char)
	ponerTinte(char)
	-- Si el servidor cambia el escudo en pleno combate, el color cambia al instante.
	char:GetAttributeChangedSignal("CosShield"):Connect(function()
		ponerTinte(char)
	end)
	return c
end

-- Los luchadores se etiquetan al entrar en combate, asi que basta con escuchar la senal.
-- Tambien se recorre lo que ya este etiquetado: si este script carga con la partida ya
-- empezada (respawn, recarga en caliente), no se queda sin ningun luchador.
CollectionService:GetInstanceAddedSignal(TAG):Connect(enganchar)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(char)
	VFX.detach(char)
end)
for _, char in ipairs(CollectionService:GetTagged(TAG)) do
	enganchar(char)
end

-- Los eventos fx del combate. OilFighterClient tambien escucha este remoto, pero para
-- otros tipos de golpe; aqui solo interesan los tres de la defensa, y el modulo ya
-- descarta el resto, asi que los dos pueden escuchar sin pisarse.
eventRemote.OnClientEvent:Connect(function(kind, a, b)
	if kind ~= "fx" then
		return
	end
	VFX.onFx(a, b)
end)

-- Un paso por frame para todos los controladores. El modulo se encarga de soltar los
-- personajes que ya no estan en el mundo.
RunService.RenderStepped:Connect(function()
	VFX.step()
end)