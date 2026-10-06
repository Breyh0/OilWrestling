-- ProgressionSystem (Script, ServerScriptService)
-- Arranca el servicio de progresion: XP/niveles, monedas, misiones diarias y guardado.
-- Toda la logica y el balance estan en ProgressionService (ModuleScript).
local ok, result = pcall(function()
	return require(script.Parent:WaitForChild("ProgressionService"))
end)
if not ok then
	warn("[ProgressionSystem] Error al iniciar el servicio:", result)
end
