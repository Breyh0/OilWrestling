-- AUTOTEST de la regla "huerfana" (ver docs/PREFLIGHT.md).
-- Este archivo TIENE un fallo a proposito: no lo arregles.
-- Motivo real (2026-10-10): en SoundDirector el clon 3D colgaba de un Attachment al
-- que nunca se le puso Parent. Sin Parent la instancia esta fuera del DataModel: el
-- sonido no sonaba, no aparecia en ningun GetDescendants() y no daba ningun error.

local function reproducir(entrada, pos)
	local s = entrada:Clone()
	if pos then
		local ancla = Instance.new("Attachment")
		ancla.WorldPosition = pos
		s.Parent = ancla -- el ancla nunca recibe Parent: el sonido queda huerfano
	else
		s.Parent = workspace
	end
	return s
end

return reproducir
