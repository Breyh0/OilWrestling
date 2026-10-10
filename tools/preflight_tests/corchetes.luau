-- AUTOTEST de las reglas "corchetes" y "bloques" (ver docs/PREFLIGHT.md).
-- Este archivo TIENE fallos a proposito: no los arregles.
-- Falta el cierre de la tabla y falta el end de la ultima funcion.

local sinCerrar = {
	a = 1,
	b = 2,

local function sinEnd()
	return 1
end

local function conEndSinCerrar()
	return 2

return sinCerrar, sinEnd, conEndSinCerrar
