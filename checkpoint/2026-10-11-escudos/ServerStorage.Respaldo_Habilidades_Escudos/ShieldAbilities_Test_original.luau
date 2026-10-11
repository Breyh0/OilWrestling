-- ShieldAbilities_Test (ModuleScript, ServerScriptService.UnitTest.Cases)
-- Tests de las habilidades de los escudos: SOLO las raras de caja tienen habilidad, usan efectos conocidos,
-- respetan el tope de su rareza sin agotarlo y ninguna comun se cuela en A.List. Sin DataStore ni red.
-- Se ejecuta con: require(ServerScriptService.UnitTest.RunUnitTest)("ShieldAbilities")

return function(t)
	local RS = game:GetService("ReplicatedStorage")
	local A = require(RS:WaitForChild("ShieldAbilities"))
	local Cosm = require(RS:WaitForChild("CosmeticsShared"))
	local expect = t.expect

	local function boxShields()
		local list = {}
		for _, it in ipairs(Cosm.Items.shield) do
			if it.boxOnly then
				table.insert(list, it)
			end
		end
		return list
	end

	-- Las comunes NO tienen habilidad: son estetica. Si metemos un comun hay que quitarlo de A.List.
	local function raresDeCaja()
		local list = {}
		for _, it in ipairs(boxShields()) do
			if it.rarity ~= "comun" then
				table.insert(list, it)
			end
		end
		return list
	end

	t.test("Solo las cajas de rareza raro o mejor tienen habilidad, y todas la tienen", function()
		local rares = raresDeCaja()
		expect.truthy(#rares > 0)
		for _, it in ipairs(rares) do
			local ab = A.Get(it.id)
			if not ab then
				error(it.id .. " no tiene habilidad en ShieldAbilities.List")
			end
			expect.truthy(type(ab.name) == "string" and #ab.name > 0)
			expect.truthy(next(A.Effects(it.id)) ~= nil)
		end
	end)

	t.test("Los escudos comunes de caja no tienen ninguna habilidad", function()
		for _, it in ipairs(boxShields()) do
			if it.rarity == "comun" then
				expect.equal(A.Get(it.id), nil)
				expect.equal(next(A.Effects(it.id)), nil)
				expect.equal(A.Describe(it.id), nil)
			end
		end
	end)

	t.test("Toda habilidad pertenece a un escudo que existe", function()
		for id in pairs(A.List) do
			local it = Cosm.Get(id)
			if not it or it.slot ~= "shield" then
				error(id .. " no es un escudo de CosmeticsShared")
			end
		end
	end)

	t.test("El Azul Clasico (escudo base) no tiene habilidad", function()
		expect.falsy(A.Get("escudo_azul"))
		expect.equal(next(A.Effects("escudo_azul")), nil)
		expect.equal(A.Describe("escudo_azul"), nil)
	end)

	t.test("Los efectos solo usan claves conocidas y ya vienen dentro de rango", function()
		for id, ab in pairs(A.List) do
			for key, v in pairs(ab.effects) do
				if not A.Keys[key] then
					error(id .. " usa la clave desconocida '" .. tostring(key) .. "'")
				end
				if A.Sanitize(ab.effects)[key] ~= v then
					error(id .. "." .. key .. " = " .. tostring(v) .. " esta fuera de rango")
				end
			end
		end
	end)

	t.test("Presupuesto: ninguna habilidad se pasa del tope de su rareza", function()
		for _, it in ipairs(boxShields()) do
			local budget = A.Budget[it.rarity]
			if not budget then
				error("falta A.Budget para la rareza '" .. it.rarity .. "' (" .. it.id .. ")")
			end
			local s = A.Strength(A.Effects(it.id))
			if s > budget + 1e-9 then
				error(string.format("%s: fuerza %.3f supera el tope %.2f de '%s'", it.id, s, budget, it.rarity))
			end
		end
	end)

	-- Las comunes valen 0, asi que la comparacion util es: las cinco rares estan en la misma banda
	-- (ninguna domina) y ninguna agota su tope. Asi hay sitio para las cajas futuras.
	t.test("Las raras son utiles pero ningun escudo agota su tope de rareza", function()
		local fuerzas = {}
		for _, it in ipairs(raresDeCaja()) do
			local s = A.Strength(A.Effects(it.id))
			expect.truthy(s > 0)
			expect.truthy(s <= A.Budget[it.rarity] + 1e-9)
			expect.truthy(s < A.Budget[it.rarity]) -- margen libre para las cajas futuras
			table.insert(fuertes, s)
		end
		table.sort(fuertes)
		if #fuertes >= 2 then
			-- la mas fuerte no debe ser el triple de la mas floja
			expect.truthy(fuertes[#fuertes] < fuerzas[1] * 3)
		end
	end)

	t.test("Describe genera un texto con el nombre y los numeros reales", function()
		expect.equal(A.Describe("escudo_sol"), "Resplandor: El parry tiene 0,04 s más de margen; un parry te devuelve 8 de stamina.")
		expect.equal(A.Describe("escudo_esmeralda"), nil) -- comun: sin habilidad
		expect.equal(A.Describe("no_existe"), nil)
		for _, it in ipairs(boxShields()) do
			local text = A.Describe(it.id)
			expect.truthy(type(text) == "string" and string.find(text, A.Get(it.id).name, 1, true) == 1)
		end
	end)

	t.test("Sanitize acota valores absurdos y descarta claves raras o NaN", function()
		local s = A.Sanitize({ blockDrain = 0.01, parryWindow = 99, inventado = 5, blockForce = 0 / 0, blockBalance = "x" })
		expect.equal(s.blockDrain, 0.25)
		expect.equal(s.parryWindow, 0.25)
		expect.equal(s.inventado, nil)
		expect.equal(s.blockForce, nil)
		expect.equal(s.blockBalance, nil)
		expect.equal(next(A.Sanitize(nil)), nil)
	end)

	t.test("ForPlayer lee el escudo equipado (CosShield) y es neutro si no hay o es desconocido", function()
		local p = Instance.new("Folder")
		expect.equal(next(A.ForPlayer(p)), nil)
		p:SetAttribute("CosShield", "escudo_tormenta")
		expect.equal(A.ForPlayer(p).reflectBalance, 8)
		p:SetAttribute("CosShield", "escudo_azul")
		expect.equal(next(A.ForPlayer(p)), nil)
		p:SetAttribute("CosShield", "inventado")
		expect.equal(next(A.ForPlayer(p)), nil)
		expect.equal(next(A.ForPlayer(nil)), nil)
		p:Destroy()
	end)
end
