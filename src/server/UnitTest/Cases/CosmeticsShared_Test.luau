-- CosmeticsShared_Test (ModuleScript, ServerScriptService.UnitTest.Cases)
-- Tests del catalogo de cosmeticos, con foco en los escudos (reconstruidos el 2026-10-11).
-- Modulo puro: sin DataStore, sin red y sin tocar el juego.
-- Se ejecuta con: require(ServerScriptService.UnitTest.RunUnitTest)("CosmeticsShared")
--
-- Estos tests miran la COHERENCIA entre el catalogo y ShieldAbilities. Esa coherencia es
-- la que se perdio al perderse el catalogo original, y es la que un jugador nota como bug
-- (un escudo raro sin habilidad, o una caja que no existe).

return function(t)
	local RS = game:GetService("ReplicatedStorage")
	local Cosm = require(RS:WaitForChild("CosmeticsShared"))
	local A = require(RS:WaitForChild("ShieldAbilities"))
	local expect = t.expect

	t.test("El slot shield existe y no esta vacio", function()
		expect.truthy(Cosm.SlotNames.shield ~= nil)
		expect.truthy(#Cosm.Items.shield > 0)
	end)

	t.test("No hay ids repetidos en ningun slot", function()
		local vistos = {}
		for _, slot in ipairs(Cosm.Slots) do
			for _, it in ipairs(Cosm.Items[slot]) do
				if vistos[it.id] then
					error("id repetido en el catalogo: " .. it.id)
				end
				vistos[it.id] = true
			end
		end
	end)

	t.test("Cada id se encuentra con Get y lleva su slot", function()
		for _, slot in ipairs(Cosm.Slots) do
			for _, it in ipairs(Cosm.Items[slot]) do
				local porId = Cosm.Get(it.id)
				expect.truthy(porId ~= nil)
				expect.equal(porId.slot, slot)
				expect.equal(Cosm.IsValid(slot, it.id), true)
				-- un id no vale para otro slot
				if slot ~= "victory" then
					expect.equal(Cosm.IsValid("victory", it.id), false)
				end
			end
		end
		expect.equal(Cosm.Get("no_existe"), nil)
	end)

	t.test("Todo escudo de caja declara una caja que existe", function()
		for _, it in ipairs(Cosm.Items.shield) do
			if it.boxOnly then
				expect.truthy(type(it.box) == "string")
				if not Cosm.Boxes[it.box] then
					error(it.id .. " viene de la caja '" .. it.box .. "', que no esta declarada")
				end
			end
		end
	end)

	t.test("Todo escudo tiene aspecto declarado", function()
		for _, it in ipairs(Cosm.Items.shield) do
			local skin = Cosm.ShieldSkin(it.id)
			if not skin then
				error(it.id .. " no tiene entrada en CosShield")
			end
			expect.truthy(typeof(skin.color) == "Color3")
			expect.truthy(type(skin.name) == "string" and #skin.name > 0)
			expect.truthy(skin.brillo >= 0 and skin.brillo <= 1)
		end
		expect.equal(Cosm.ShieldSkin("no_existe"), nil)
	end)

	t.test("El escudo base existe, no cuesta nada y no viene de caja", function()
		local base = Cosm.Get(Cosm.Defaults.shield)
		expect.truthy(base ~= nil)
		expect.equal(base.id, "escudo_azul")
		expect.equal(base.price, 0)
		expect.equal(base.boxOnly, false)
	end)

	t.test("RareShields devuelve solo los de caja que no son comunes", function()
		local rares = Cosm.RareShields()
		expect.truthy(#rares > 0)
		for _, it in ipairs(rares) do
			expect.equal(it.boxOnly, true)
			expect.truthy(it.rarity ~= "comun")
		end
	end)

	t.test("Coherencia con ShieldAbilities: todo raro del catalogo tiene habilidad", function()
		for _, it in ipairs(Cosm.RareShields()) do
			local ab = A.Get(it.id)
			if not ab then
				error(it.id .. " es " .. it.rarity .. " pero no esta en ShieldAbilities.List")
			end
			expect.truthy(next(A.Effects(it.id)) ~= nil)
		end
	end)

	t.test("Coherencia con ShieldAbilities: ninguna habilidad apunta a un escudo comun", function()
		for id in pairs(A.List) do
			local it = Cosm.Get(id)
			expect.truthy(it ~= nil)
			expect.equal(it.slot, "shield")
			expect.truthy(it.rarity ~= "comun")
			expect.equal(it.boxOnly, true)
		end
	end)

	t.test("Los cinco raros del comentario de ShieldAbilities son cinco de verdad", function()
		-- El comentario de A.List dice "las cinco rares". Si se anade un escudo raro hay que
		-- actualizar el comentario, y este test avisa de que se ha tocado el balance.
		local n = 0
		for _ in pairs(A.List) do
			n = n + 1
		end
		expect.equal(n, 5)
	end)

	t.test("ShieldsOfBox devuelve lo que dice y solo lo de esa caja", function()
		for cajaId in pairs(Cosm.Boxes) do
			local lista = Cosm.ShieldsOfBox(cajaId)
			for _, it in ipairs(lista) do
				expect.equal(it.box, cajaId)
				expect.equal(it.boxOnly, true)
			end
		end
		expect.equal(#Cosm.ShieldsOfBox("caja_que_no_existe"), 0)
	end)

	t.test("El catalogo de victoria y ring-out sigue intacto", function()
		-- Son lo unico que vino del original (FNV 825101627). Este test falla si alguien
		-- los toca sin querer al anadir escudos.
		expect.equal(#Cosm.Items.victory, 6)
		expect.equal(#Cosm.Items.ringout, 6)
		expect.equal(Cosm.Get("ave_cesar").price, 0)
		expect.equal(Cosm.Get("pulgar_emperador").rarity, "legendario")
		expect.equal(Cosm.Get("fuegos_arena").price, 950)
	end)
end