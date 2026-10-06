-- OilControls (ModuleScript, ReplicatedStorage)
-- Fuente única de verdad de los controles: la usan el input (OilFighterClient) y el HUD (OilCombatHUD).
-- Para cambiar una tecla, edita 'keys' aquí y el HUD se actualiza solo (ajusta también 'keyLabel').

local M = {}

M.Bindings = {
	{ id = "push",   name = "Empujón",   keyLabel = "CLIC IZQ.", keys = { Enum.UserInputType.MouseButton1 }, hint = "Resta equilibrio al rival" },
	{ id = "charge", name = "Embestida", keyLabel = "Q",         keys = { Enum.KeyCode.Q }, hint = "Derriba; si fallas, quedas expuesto" },
	{ id = "grab",   name = "Agarre",    keyLabel = "F",         keys = { Enum.KeyCode.F }, hint = "Rompe el bloqueo y lanza al rival" },
	{ id = "block",  name = "Bloqueo",   keyLabel = "R",         keys = { Enum.KeyCode.R }, hint = "Mantén. Tocar justo antes del golpe = PARRY", hold = true },
	{ id = "dodge",  name = "Esquiva",   keyLabel = "E",         keys = { Enum.KeyCode.E }, hint = "Invulnerable un instante" },
	{ id = "lock",   name = "Fijar cámara", keyLabel = "SHIFT IZQ.", keys = { Enum.KeyCode.LeftShift }, hint = "Fija la cámara en el rival (otra vez = soltar)" },
	{ id = "resign", name = "Renunciar", keyLabel = "X",         keys = { Enum.KeyCode.X }, hint = "Pulsa 2 veces para confirmar" },
}

M.ByAction = {}
for _, b in ipairs(M.Bindings) do
	M.ByAction[b.id] = b
end

-- Eventos locales (cada cliente tiene los suyos): el HUD pide acciones, el input las ejecuta
M.Request = Instance.new("BindableEvent")      -- :Fire(actionId, isDown)
M.ResignState = Instance.new("BindableEvent")  -- :Fire("armed" | "reset" | "sent")

return M
