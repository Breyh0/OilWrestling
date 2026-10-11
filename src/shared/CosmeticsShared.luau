-- CosmeticsShared (ModuleScript, ReplicatedStorage)
-- Catalogo de cosmeticos de Oil Wrestling: gestos de victoria, efectos de ring-out y ESCUDOS.
-- Lo leen el servidor (precios, validacion), el cliente (efectos, tienda) y la animacion.
-- El id es la clave: se guarda en los datos del jugador.
--
-- MODULO PURO: no usa servicios, no crea Instances y no toca el juego. Por eso se puede
-- testear entero sin entrar a Roblox (ver UnitTest/Cases/CosmeticsShared_Test).
--
-- ESCUDOS (reconstruido 2026-10-11)
--   Los ids, los nombres, las rarezas y el reparto raridad/habilidad NO son inventados:
--   salen de ShieldAbilities (rescatado del lugar, verificado byte a byte) y de su test.
--   Lo que SI se perdio y hay que volver a decidir son los PRECIOS y el nombre de las cajas.
--   estan marcados con "-- PROPUESTA" y son lo primero que hay que revisar.
--
--   La regla de diseno que se respeta: SOLO los escudos de rareza raro o mejor tienen
--   habilidad (esta en A.List de ShieldAbilities). Los comunes y el escudo base son
--   estetica pura. El test lo comprueba, asi que anadir un comun con efecto rompe el test.

local Shared = {}

Shared.Slots = { "victory", "ringout", "shield" }
Shared.SlotNames = {
	victory = "Gesto de victoria",
	ringout = "Efecto de ring-out",
	shield = "Escudo de bloqueo",
}

Shared.Rarities = {
	comun = { name = "Común", color = Color3.fromRGB(190, 190, 180) },
	poco_comun = { name = "Poco común", color = Color3.fromRGB(120, 200, 120) },
	raro = { name = "Raro", color = Color3.fromRGB(90, 160, 255) },
	epico = { name = "Épico", color = Color3.fromRGB(190, 110, 255) },
	legendario = { name = "Legendario", color = Color3.fromRGB(255, 190, 60) },
}

Shared.Items = {
	victory = {
		{ id = "ave_cesar", name = "¡Ave, César!", price = 0, rarity = "comun", dur = 3.6,
			desc = "El saludo romano clásico: brazo en alto, puño al pecho y reverencia." },
		{ id = "flex_campeon", name = "Flexión de Campeón", price = 150, rarity = "poco_comun", dur = 4.0,
			desc = "Doble bíceps, giros de torso y pose de campeón." },
		{ id = "rugido_gladiador", name = "Rugido de Gladiador", price = 300, rarity = "raro", dur = 4.2,
			desc = "Brazos al cielo, rugido y dos saltos de furia con ondas de choque." },
		{ id = "giro_aceitoso", name = "Giro Aceitoso", price = 450, rarity = "raro", dur = 4.2,
			desc = "Doble pirueta resbaladiza que salpica aceite a su paso." },
		{ id = "laurel_triunfal", name = "Laureles Triunfales", price = 650, rarity = "epico", dur = 4.4,
			desc = "Corona de laureles dorados, saltos de triunfo y lluvia de hojas." },
		{ id = "pulgar_emperador", name = "Veredicto del Emperador", price = 900, rarity = "legendario", dur = 4.8,
			desc = "Saluda a la multitud bajo una columna de luz dorada." },
	},
	ringout = {
		{ id = "splash_clasico", name = "Salpicadura Clásica", price = 0, rarity = "comun",
			desc = "Gotas de aceite que salen volando cuando sacas a tu rival." },
		{ id = "geiser_aceite", name = "Géiser de Aceite", price = 200, rarity = "poco_comun",
			desc = "Una columna de aceite brota del suelo con onda expansiva." },
		{ id = "rayo_olimpo", name = "Rayo del Olimpo", price = 350, rarity = "raro",
			desc = "Un rayo cae desde el cielo y deja el suelo chamuscado." },
		{ id = "llamarada_coliseo", name = "Llamarada del Coliseo", price = 500, rarity = "raro",
			desc = "Una columna de fuego con brasas y humo." },
		{ id = "lluvia_laureles", name = "Lluvia de Laureles", price = 700, rarity = "epico",
			desc = "Laureles verdes y dorados caen flotando sobre la arena." },
		{ id = "fuegos_arena", name = "Fuegos de la Arena", price = 950, rarity = "legendario",
			desc = "Tres fuegos artificiales y confeti sobre el rival derrotado." },
	},
	shield = {
		-- El escudo base: se lleva siempre, no cuesta nada y NO tiene habilidad.
		{ id = "escudo_azul", name = "Azul Clásico", price = 0, rarity = "comun",
			boxOnly = false,
			desc = "El escudo de serie del gladiador. Sin habilidad: es el que llevas al entrar." },

		-- Comunes de caja. Estetica pura, a proposito: la rareza tiene que notarse en la pelea.
		{ id = "escudo_esmeralda", name = "Esmeralda", price = 200, rarity = "comun", -- PROPUESTA de precio
			boxOnly = true, box = "caja_comun",
			desc = "Piedra verde pulida. Bonito, pero igual de duro que el de serie." },
		{ id = "escudo_granito", name = "Granito Rosa", price = 200, rarity = "comun", -- PROPUESTA de precio
			boxOnly = true, box = "caja_comun",
			desc = "Mármol rosado pulido, de las canteras del monte." },

		-- Raros: estos si tienen habilidad (A.List en ShieldAbilities).
		{ id = "escudo_sol", name = "Escudo Solar", price = 300, rarity = "raro", -- PROPUESTA de precio
			boxOnly = true, box = "caja_rara",
			desc = "Latón con un sol grabado. El parry aguanta y devuelve algo de stamina." },
		{ id = "escudo_laureles", name = "Laureles", price = 350, rarity = "raro", -- PROPUESTA de precio
			boxOnly = true, box = "caja_rara",
			desc = "Ramas doradas entrelazadas. Bloquear sale más barato." },
		{ id = "escudo_tormenta", name = "Descarga", price = 400, rarity = "raro", -- PROPUESTA de precio
			boxOnly = true, box = "caja_rara",
			desc = "Placas de cobre con chispas. Devuelve algo de equilibrio al atacante." },
		{ id = "escudo_constelacion", name = "Guía Astral", price = 450, rarity = "raro", -- PROPUESTA de precio
			boxOnly = true, box = "caja_rara",
			desc = "Piedra negra con constelaciones. El contraataque dura y pega más." },
		{ id = "escudo_espectral", name = "Llama Fantasma", price = 500, rarity = "raro", -- PROPUESTA de precio
			boxOnly = true, box = "caja_rara",
			desc = "Brasas que no queman. Mantener la guardia sale barato y atormenta al rival." },
	},
}

-- Cajas. Los ids de aqui son los que usan los escudos en su campo `box`.
-- PROPUESTA: el sistema de cajas no se ha recuperado, asi que solo se declaran los ids
-- que necesitan los escudos. El dia que se monte la tienda, esto se amplia.
Shared.Boxes = {
	caja_comun = { name = "Caja Común", rarity = "comun" },
	caja_rara = { name = "Caja Rara", rarity = "raro" },
}

-- ASPECTO de los escudos. Lo lee OilBlockVFX para pintar la guardia; ShieldAbilities NO lo
-- toca (solo lee Numbers, nunca colores).
--
-- Reconstruido 2026-11 sin el original delante: los colores son una PROPUESTA. La estructura
-- (`ShieldSkins` con color, brillo y material) es la que espera OilBlockVFX segun su
-- cabecera; si al recuperar OilBlockVFX los nombres no cuadran, se ajusta aqui y solo aqui.
Shared.CosShield = {
	escudo_azul = {
		ShieldSkins = {
			{ name = "Azul Clásico", color = Color3.fromRGB(70, 110, 190), brillo = 0.25, material = "Metal" },
		},
	},
	escudo_esmeralda = {
		ShieldSkins = {
			{ name = "Esmeralda", color = Color3.fromRGB(50, 180, 110), brillo = 0.45, material = "Metal" },
		},
	},
	escudo_granito = {
		ShieldSkins = {
			{ name = "Granito Rosa", color = Color3.fromRGB(210, 150, 150), brillo = 0.30, material = "Slate" },
		},
	},
	escudo_sol = {
		ShieldSkins = {
			{ name = "Solar", color = Color3.fromRGB(240, 200, 90), brillo = 0.85, material = "Metal" },
		},
	},
	escudo_laureles = {
		ShieldSkins = {
			{ name = "Laureles", color = Color3.fromRGB(190, 200, 80), brillo = 0.70, material = "Metal" },
		},
	},
	escudo_tormenta = {
		ShieldSkins = {
			{ name = "Descarga", color = Color3.fromRGB(90, 160, 255), brillo = 0.95, material = "Metal" },
		},
	},
	escudo_constelacion = {
		ShieldSkins = {
			{ name = "Guía Astral", color = Color3.fromRGB(120, 90, 200), brillo = 0.80, material = "Neon" },
		},
	},
	escudo_espectral = {
		ShieldSkins = {
			{ name = "Llama Fantasma", color = Color3.fromRGB(120, 220, 200), brillo = 1.00, material = "Neon" },
		},
	},
}

Shared.Defaults = {
	victory = "ave_cesar",
	ringout = "splash_clasico",
	shield = "escudo_azul",
}

-- Índices para consultar por id
Shared.ById = {}
for _, slot in ipairs(Shared.Slots) do
	for _, it in ipairs(Shared.Items[slot]) do
		it.slot = slot
		Shared.ById[it.id] = it
	end
end

function Shared.Get(id)
	return Shared.ById[id]
end

function Shared.IsValid(slot, id)
	local it = Shared.ById[id]
	return it ~= nil and it.slot == slot
end

-- Escudos de una caja concreta, en el orden en que se declararon.
function Shared.ShieldsOfBox(boxId)
	local list = {}
	for _, it in ipairs(Shared.Items.shield) do
		if it.boxOnly and it.box == boxId then
			list[#list+1] = it
		end
	end
	return list
end

-- Escudos de caja que NO son comunes: los unicos que pueden tener habilidad.
function Shared.RareShields()
	local list = {}
	for _, it in ipairs(Shared.Items.shield) do
		if it.boxOnly and it.rarity ~= "comun" then
			list[#list+1] = it
		end
	end
	return list
end

-- El aspecto de un escudo, o nil si no tiene. Devuelve la tabla congelada.
function Shared.ShieldSkin(id)
	local entry = Shared.CosShield[id]
	if not entry then
		return nil
	end
	return entry.ShieldSkins and entry.ShieldSkins[1] or nil
end

return Shared