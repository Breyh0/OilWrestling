-- CosmeticsShared (ModuleScript, ReplicatedStorage)
-- Catalogo de cosmeticos de Oil Wrestling: gestos de victoria y efectos de ring-out.
-- Lo leen el servidor (precios, validacion), el cliente (efectos, tienda) y la animacion.
-- "dur" = duracion en segundos del gesto. El id es la clave: se guarda en los datos del jugador.

local Shared = {}

Shared.Slots = { "victory", "ringout" }
Shared.SlotNames = { victory = "Gesto de victoria", ringout = "Efecto de ring-out" }

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
}

Shared.Defaults = { victory = "ave_cesar", ringout = "splash_clasico" }

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

return Shared
