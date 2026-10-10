-- AUTOTEST de la regla "adelantada" (ver docs/PREFLIGHT.md).
-- Este archivo TIENE fallos a proposito: no los arregles.
-- Motivos reales (los dos, el 2026-10-10):
--   1) MAX_SEGUNDOS declarado DESPUES de la tabla que lo usa: al leerlo valia nil en
--      silencio, y el tope de la fanfarria no se aplicaba nunca.
--   2) una funcion llamada antes de declararse: al invocarla daria nil en runtime.

local SONIDOS = {
	victory = { gain = 1.0, maxSeconds = MAX_SEGUNDOS },
}

local function tocar(entrada)
	return entrada.maxSeconds
end

local function tocarTarde()
	return preparar()
end

local MAX_SEGUNDOS = 8.0

local function preparar()
	return "listo"
end

return SONIDOS, tocar, tocarTarde
