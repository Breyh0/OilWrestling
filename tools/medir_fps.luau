-- medir_fps.luau — mide frame time de verdad y, sobre todo, el RUIDO de la medicion.
--
-- Por qué el ruido va primero: si mides una vez, cualquier diferencia pequeña parece
-- un hallazgo. El 2026-10-11 se desactivaron las sombras y "ganó" 0.93 ms; con cinco
-- mediciones idénticas el ruido resultó ser 0.72 ms, así que la mitad de las cosas que
-- parecían ganar no ganaban nada.
--
-- Uso (dentro de un playtest, contexto Client):
--   local m = require(... o pegar ...)  -- es un script, se pega y se ejecuta
--   local r = medir.Medir({ repeticiones = 5, segundos = 6 })
--
-- No se toca nada del lugar: solo mide. Para comparar variantes hay que cambiar la
-- escena a mano y medir DESPUÉS de cada cambio, restaurando antes de la siguiente.
--
-- OJO: medir en Studio tiene un suelo de ruido alto y un coste propio del editor. Para
-- decidir sobre rendimiento real hay que medir en un cliente publicado. Ver
-- docs/RENDIMIENTO.md.

local M = {}

local function ordenar(t)
	table.sort(t)
	return t
end

local function percentil(ordenada, q)
	local n = #ordenada
	if n == 0 then
		return 0
	end
	return ordenada[math.max(1, math.floor(n * q))]
end

-- Una pasada: devuelve fps, media, p50, p90, p99, peor y numero de frames.
function M.UnaPasada(segundos)
	local RunService = game:GetService("RunService")
	local muestras = {}
	local conexion = RunService.RenderStepped:Connect(function(dt)
		table.insert(muestras, dt)
	end)
	local t0 = os.clock()
	task.wait(segundos)
	conexion:Disconnect()
	local transcurrido = os.clock() - t0
	ordenar(muestras)

	local n = #muestras
	local suma, peor = 0, 0
	for _, v in ipairs(muestras) do
		suma = suma + v
		if v > peor then
			peor = v
		end
	end
	return {
		fps = n / transcurrido,
		frames = n,
		segundos = transcurrido,
		media = (n > 0 and suma / n or 0) * 1000,
		p50 = percentil(muestras, 0.5) * 1000,
		p90 = percentil(muestras, 0.9) * 1000,
		p99 = percentil(muestras, 0.99) * 1000,
		peor = peor * 1000,
	}
end

-- Repite la misma medicion y calcula el ruido. Sin esto, no se puede afirmar nada.
function M.Medir(opciones)
	local o = opciones or {}
	local repeticiones = o.repeticiones or 5
	local segundos = o.segundos or 6

	local pasadas = {}
	for i = 1, repeticiones do
		pasadas[i] = M.UnaPasada(segundos)
	end

	local medias = {}
	for _, p in ipairs(pasadas) do
		medias[#medias+1] = p.media
	end
	ordenar(medias)

	local minimo, maximo = medias[1], medias[#medias]
	local suma = 0
	for _, v in ipairs(medias) do
		suma = suma + v
	end
	local media = suma / #medias
	local ruido = maximo - minimo

	-- Cuantos frames por debajo de 60 fps hubo de media, en la pasada tipica
	local tipica = pasadas[math.ceil(repeticiones / 2)]

	return {
		pasadas = pasadas,
		media = media,
		minimo = minimo,
		maximo = maximo,
		ruido = ruido,
		ruidoPct = (media > 0 and ruido / media * 100 or 0),
		tipica = tipica,
	}
end

-- Compara contra una medicion previa y dice si la diferencia sale del ruido.
function M.Comparar(antes, despues)
	local diferencia = antes.media - despues.media
	-- El umbral es el ruido de LAS DOS mediciones sumados: cada una por separado ya
	-- fluctua, asi que exigirse el maximo de una sola seria demasiado optimista.
	local ruidoCombinado = antes.ruido + despues.ruido
	local sale = math.abs(diferencia) > ruidoCombinado
	local texto
	if sale then
		texto = string.format("DIFERENCIA REAL: %.2f ms (%.1f%%) | ruido combinado %.2f ms",
			diferencia, (antes.media > 0 and diferencia / antes.media * 100 or 0), ruidoCombinado)
	else
		texto = string.format("DENTRO DEL RUIDO: %.2f ms | hace falta mas de %.2f ms para afirmarlo",
			diferencia, ruidoCombinado)
	end
	return sale, diferencia, ruidoCombinado, texto
end

function M.Informe(r, titulo)
	local out = {}
	local t = titulo or "medicion"
	out[#out+1] = string.format("=== %s ===", t)
	out[#out+1] = string.format("  repeticiones : %d x %.0f s", #r.pasadas, r.pasadas[1].segundos)
	out[#out+1] = string.format("  frame time  : media %.2f ms | min %.2f | max %.2f", r.media, r.minimo, r.maximo)
	out[#out+1] = string.format("  tipica (p50): %.2f ms | p90 %.2f | p99 %.2f | peor %.2f",
		r.tipica.p50, r.tipica.p90, r.tipica.p99, r.tipica.peor)
	out[#out+1] = string.format("  fps         : %.1f", r.tipica.fps)
	out[#out+1] = string.format("  RUIDO       : %.2f ms (%.1f%%) -- nada por debajo de esto es un hallazgo",
		r.ruido, r.ruidoPct)
	return table.concat(out, "\n")
end

return M
