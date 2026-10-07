---
name: QA y verificación — Lucha de aceite
description: Cómo verificar cambios en Roblox Studio antes de darlos por buenos - playtest, capturas, consola, pruebas de UI en móvil y cuándo usar cada skill del MCP de Roblox. Cargar al terminar cualquier cambio de código, GUI, escena o balance que necesite estar comprobado.
---

# QA y verificación — Lucha de aceite

Antes de esta skill, carga **`lucha-workflow`**: define dónde se escribe el código y qué reglas anti-conflicto existen. Esta skill es el **capa de verificación**.

Principio: **el playtest es el único veredicto válido**. Todo lo demás son pistas.

## Ciclo de verificación estándar

```
1. execute_luau   → comprobaciones programáticas (estado, sizes, flags)
2. start_stop_play → entrar en juego
3. screen_capture  → evidencia visual
4. get_console_output → 0 errores
5. start_stop_play → salir
```

Nunca cerrar un cambio sin el paso 4. **0 errores de consola** es el criterio de aceptación.

## Cuándo usar cada skill del MCP de Roblox

| Situación | Herramienta |
|---|---|
| Bug que solo aparece jugando | `start_stop_play` + `get_console_output` + skill **`rbx-debug`** (breakpoints reales, inspección de hilos) |
| UI que se ve bien en PC y mal en móvil | skill **`rbx-device-simulator-lua`** → `execute_luau` (cambiar dispositivo) + `screen_capture` |
| Duda sobre una API de Roblox | skill **`rbx-docs-search`** → `http_get` sobre `create.roblox.com/docs`. **Nunca escribir una API de memoria** |
| Frame-time, memory leaks, quedas de FPS | skill **`rbx-perf-profiling`** (MicroProfiler) o **`rbx-scene-analysis`** (instances sin parentear, memoria) |
| Lógica pura que quieres blindar | skill **`rbx-unit-test`** (tests de ModuleScripts) |
| Contexto de gameplay que hay que identificar rápido | subagente **`explore`** |

## Verificación visual: las trampas conocidas

- **`screen_capture` con `camera_position` devuelve frames CACHÉ**: no reflejan ediciones. En crudo es live, pero con retardo. La prueba definitiva es en playtest.
- **Elementos con `Visible=false` no aparecen** en captura. Si "falta" algo, primero comprueba `Visible` por `execute_luau`.
- **UI construida por script**: en modo Edit puede verse vacía y ser correcta en juego. Si `StarterGui` está vacío o todo `Visible=false`, la captura es inútil → pasa a playtest.

## Medir en vez de suponer

Nunca estimar posiciones o tamaños a ojo. Consultarlos:

```lua
-- execute_luau (Edit) - posiciones reales de StarterGui en pixeles de viewport
local vp = workspace.CurrentCamera.ViewportSize
local out = { string.format("VIEWPORT|%.0fx%.0f", vp.X, vp.Y) }
for _, sg in game:GetService("StarterGui"):GetChildren() do
	if sg:IsA("ScreenGui") and sg.Enabled then
		local function walk(o, path)
			if o:IsA("GuiObject") and o.Visible then
				local p, s = o.AbsolutePosition, o.AbsoluteSize
				out[#out + 1] = string.format("%s|%.0f,%.0f,%.0f,%.0f", path, p.X, p.Y, p.X + s.X, p.Y + s.Y)
			end
			for _, c in o:GetChildren() do if c:IsA("GuiBase2d") then walk(c, path .. "." .. c.Name) end end
		end
		walk(sg, sg.Name)
	end
end
return table.concat(out, "\n")
```

Checks sobre esas coordenadas: **recorte** (fuera del viewport), **solape** (rectángulos que se pisan), **texto truncado** (`TextFits == false` en playtest), **targets pequeños** (`<44x44` px en móvil).

## Probar en móvil (UI)

Este juego es de lucha en ring: la UI está diseñada en horizontal, y en móvil **aparece el doble de contenido en el mismo hueco**.

1. Skill `rbx-device-simulator-lua`. Los setters **fallan en PlayServer**: configura el dispositivo **antes** de `start_stop_play`.
2. El juego es `LandscapeSensor` (horizontal) → prueba siempre en landscape. Portrait solo si lo pide.
3. Arquetipos: móvil reciente, **móvil de gama baja (menor resolución del listado)**, tablet. Ignora consola/VR salvo que se pida.
4. Tras cada cambio: `task.wait(0.2)` antes de capturar (el viewport se actualiza de forma asíncrona), luego `screen_capture`, luego `get_console_output`.
5. **Termina siempre revirtiendo**: `StopSimulationAsync()` y avisa de que el viewport vuelve al tamaño por defecto. Si no, el compañero hereda un Studio en un móvil de 360px.

## Probar lógica de juego sin manos

Existe input injection: `user_keyboard_input` / `user_mouse_input` (`datamodel_type: "Client"`).

⚠️ **La latencia entre llamadas (~30-60s) supera la duración de un round.** Meter todo el flujo en **una sola llamada** `execute_luau`: esperar la partida, pulsar, y sondear el resultado. Si se hace en pasos separados, la partida ya ha acabado cuando llega la siguiente tecla.

Para scripts de servidor que el cliente no expone, usar `execute_luau` con `datamodel_type: "Server"` en playtest.

## Qué mirar en cada tipo de cambio

| Cambio | Verificar |
|---|---|
| `OilConfig` (balance) | Que el HUD refleja los valores nuevos (barras, cooldowns); aceite menos/más resbaladizo; **el resto de IAs no rompidas** |
| `OilPhysics` | Deslizamiento en giros bruscos, `slick` ciclando, caída por `stepOne` sin NaN |
| `OilCombat` (acciones, rondas) | Ring-out suma punto correcto; estados de luchador; **crash de `runMatch` deja `match` colgado** (bug #1 conocido: si lanza error, el servidor deja de iniciar partidas) |
| Progresión | XP/monedas/misiones; que todo siga en servidor (nada de lógica de progreso en cliente) |
| `OilSplash` / efectos | Que no salpique en el lobby (gate `isOverArena`); que las gotas se limpien con `Debris` |
| Remotes | Que sigue siendo 5 la superficie entrante; throttle y whitelist intactos |
| GUI (`StarterGui`) | **Se edita en Studio, no en git** → avisar al equipo de que hay cambios de escena sin commit |

## Reportar

Cierra con el formato de abajo para que el otro teammate sepa qué está verificado y qué no:

```
Verificado en playtest 2026-10-07:
- 0 errores de consola
- <observación concreta, con números>
Pendiente: <lo que no se pudo comprobar>
```

Sé honesto con los límites: si solo verificaste en landscape de PC, dilo. Un informe que exagera la cobertura es peor que ninguno, porque el compañero deja de fiarse.