-- AUTOTEST de la regla "reservada" (ver docs/PREFLIGHT.md).
-- Este archivo TIENE un fallo a proposito: no lo arregles.
-- Motivo real del bug: en SoundDirector, lane = { prio = 0, until = 0 } hizo que el
-- script entero no compilara. No sonaba nada y Rojo no dijo nada.

local lane = { prio = 0, until = 0 }

local function quedaLibre(l)
	if l.until then
		return true
	end
	return false
end

return quedaLibre, lane
