-- RunUnitTest (ModuleScript, ServerScriptService.UnitTest)
-- Arnes de tests unitarios del proyecto. Descubre los casos bajo UnitTest.Cases,
-- ejecuta cada uno aislado con un limite de tiempo y resume por consola.
-- No se ejecuta solo (es un ModuleScript): se invoca a mano desde la IA con
-- execute_luau en Server durante un playtest, o desde un Script deshabilitado.
--
-- Uso: require(ServerScriptService.UnitTest.RunUnitTest)(filtro, timeout)
--   filtro  opcional; solo ejecuta casos cuyo nombre lo contenga
--   timeout opcional; segundos por caso (por defecto 5)

local ServerScriptService = game:GetService("ServerScriptService")
local Cases = ServerScriptService:WaitForChild("UnitTest"):WaitForChild("Cases")

local function fmt(v)
	if type(v) == "string" then
		return string.format("%q", v)
	end
	return tostring(v)
end

local expect = {}

function expect.equal(actual, expected)
	if actual ~= expected then
		error(string.format("se esperaba %s, se obtuvo %s", fmt(expected), fmt(actual)), 2)
	end
end

function expect.truthy(value)
	if not value then
		error(string.format("se esperaba truthy, se obtuvo %s", fmt(value)), 2)
	end
end

function expect.falsy(value)
	if value then
		error(string.format("se esperaba falsy, se obtuvo %s", fmt(value)), 2)
	end
end

function expect.near(actual, expected, tolerance)
	tolerance = tolerance or 1e-6
	if type(actual) ~= "number" or math.abs(actual - expected) > tolerance then
		error(string.format("se esperaba %s +- %s, se obtuvo %s", fmt(expected), fmt(tolerance), fmt(actual)), 2)
	end
end

function expect.throws(fn)
	local ok, err = pcall(fn)
	if ok then
		error("se esperaba que la funcion lanzase un error, pero fue correcta", 2)
	end
	return err
end

function expect.deepEqual(actual, expected)
	local function eq(a, b)
		if a == b then
			return true
		end
		if type(a) ~= "table" or type(b) ~= "table" then
			return false
		end
		for k, v in pairs(a) do
			if not eq(v, b[k]) then
				return false
			end
		end
		for k in pairs(b) do
			if a[k] == nil then
				return false
			end
		end
		return true
	end
	if not eq(actual, expected) then
		error("las tablas no son profundamente iguales", 2)
	end
end

-- Ejecuta un caso aislado con limite de tiempo. El limite solo acota casos que
-- ceden el hilo: un bucle infinito sincrono no se puede interrumpir.
local function runOne(fn, timeout)
	local done, ok, err = false, false, nil
	local cpuStart = os.clock()
	task.spawn(function()
		ok, err = pcall(fn)
		done = true
	end)
	local waited = 0
	while not done and waited < timeout do
		waited += task.wait()
	end
	local elapsed = waited > 0 and waited or (os.clock() - cpuStart)
	if not done then
		return "timeout", elapsed, string.format("excedio %.1fs", timeout)
	elseif ok then
		return "pass", elapsed, nil
	end
	return "fail", elapsed, tostring(err)
end

return function(filter, timeout)
	timeout = timeout or 5
	local totals = { run = 0, passed = 0, failed = 0 }
	local sessionStart = os.clock()

	for _, module in ipairs(Cases:GetDescendants()) do
		if module:IsA("ModuleScript") and (filter == nil or string.find(module.Name, filter, 1, true)) then
			local okRequire, caseFn = pcall(require, module)
			if not okRequire or type(caseFn) ~= "function" then
				totals.run += 1
				totals.failed += 1
				warn(string.format("[FAIL] %s | el caso no devolvio una funcion: %s", module.Name, tostring(caseFn)))
			else
				local t = { expect = expect }
				function t.test(name, fn)
					totals.run += 1
					local status, elapsed, message = runOne(fn, timeout)
					if status == "pass" then
						totals.passed += 1
						print(string.format("[PASS] %s > %s (%.3fs)", module.Name, name, elapsed))
					else
						totals.failed += 1
						warn(string.format("[%s] %s > %s (%.3fs) | %s", string.upper(status), module.Name, name, elapsed, message))
					end
				end
				local okRun, runErr = pcall(caseFn, t)
				if not okRun then
					totals.run += 1
					totals.failed += 1
					warn(string.format("[FAIL] %s | error al construir los casos: %s", module.Name, tostring(runErr)))
				end
			end
		end
	end

	print(string.format("[SUMMARY] %d ejecutados, %d ok, %d fallidos, %.3fs", totals.run, totals.passed, totals.failed, os.clock() - sessionStart))
	return totals
end