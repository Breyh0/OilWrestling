---
name: Flujo de trabajo — Lucha de aceite
description: Reglas duras del equipo para trabajar en este repo (Roblox + Rojo + git + Team Create). Cargar SIEMPRE antes de editar código, sincronizar Rojo, tocar Studio o empezar cualquier sesión de trabajo en el proyecto "Lucha de aceite".
---

# Flujo de trabajo — Lucha de aceite

Juego de lucha en aceite (ring-out, primero a 3). Place `76883498915584`, grupo **Kyubu Studio**, **Team Create activo**, dos IAs conectadas en paralelo por Studio MCP (una por PC). El riesgo aquí **no es el código, es pisarse**: dos sesiones vivas escribiendo sobre el mismo place.

**Fuente de verdad del proyecto: `docs/MEMORY.md` — léelo antes de tocar nada** si no está ya en contexto. Esta skill es el resumen operativo; si algo contradice a `MEMORY.md`, manda `MEMORY.md`.

## Reglas duras (no negociables)

1. **Código → solo en archivos `src/`.** Ni a mano en el editor de scripts de Studio ni vía MCP (`multi_edit`, `execute_luau` con `inst.Source = ...` sobre scripts Rojo). La siguiente sincronización lo sobrescribe **sin aviso**.
2. **Escena y GUI → solo en Studio** (Workspace, frames de `StarterGui`). git no fusiona el `.rbxl`; Team Create sí fusiona escena en vivo.
3. **`git pull` antes de empezar · `git push` al terminar.** Nunca sincronizar Rojo con cambios locales sin pushear: tus archivos pisarían en el place lo que el otro ya hizo.
4. **`src/` es la fuente de verdad de todo código de los servicios Rojo.** Si añades un hijo a mano en ServerScriptService / ReplicatedStorage / StarterPlayerScripts / StarterCharacterScripts, guárdalo también como archivo o el próximo sync lo borra.
5. **Nada de scripts extra en servicios Rojo.** Solo lo declarado en `src/` (más `ServerStorage.FighterTemplate` y el marcador `__Rojo_SessionLock`, que **no se borra**).
6. **Si `git push` rechaza** → `git pull`, resolver el merge (las IAs ayudan con el diff). Es flujo normal.
7. **`session lock` de Rojo** → otra persona tiene el place sincronizado: avisar y desconectar. Sync idempotente con archivos idénticos es inocuo; con divergidos, no.

## Flujo estándar de sesión

```
1. git pull
2. rojo serve (iniciar-rojo.bat) + Connect en Studio   ← terminal abierta todo el rato
3. Trabajar (código en src/ · escena en Studio)
4. git add -A && git commit && git push
5. Verificar place ↔ src (ver abajo) antes de dar por buena una sync
```

> `rojo serve` **no es automático**: es una ventana de terminal. Si Studio dice *"Couldn't connect to the Rojo server"* → no hay serve: abrir `iniciar-rojo.bat` y volver a pulsar **Connect**.

## Antes de sincronizar: verificar place ↔ src

El place cambia en vivo (el compañero edita por su lado). Antes del primer `rojo serve` del día y tras cada sesión larga: **el `#Source` de cada script en el place debe ser byte a byte igual que el archivo en `src/`**. Si hay diferencia, decidir de qué lado viene el cambio y re-extraer **antes** de sincronizar, o los archivos (más viejos) pisan lo hecho en Studio.

Tras una sesión del compañero, **correr el barrido de hashes** antes de tocar nada (lección del incidente 2026-10-07: editó el place directamente y rompió el juego con un solo byte):

```lua
-- execute_luau (Edit) — FNV-1a 32 sobre el Source de cada script Rojo
local function fnv(s)
	local h = 2166136261
	for i = 1, #s do
		h = bit32.bxor(h, string.byte(s, i))
		h = (h * 16777619) % 4294967296
	end
	return h
end
```

Compara contra `Fnv` en PowerShell con `[IO.File]::ReadAllBytes` sobre `src/**`. Mismo algoritmo, mismos bytes → hash igual.

**Duplicados al extraer**: si en Studio existe un script manual homónimo de un archivo nuevo en `src/`, Rojo crea una **SEGUNDA copia** en vez de adoptar la suya. Tras extraer: contar por nombre con `GetChildren()` y conservar la **última** (la de Rojo, la que sigue al archivo).

## Verificación y playtest

- **El test real es el playtest** (`start_stop_play`). Los `require()` de módulos del servidor **fallan en contexto Edit** (`OnServerEvent can only be used on the server`) — es el contexto, no el código.
- **`require()` en contexto Edit cachea**: puede devolver valores viejos. Verificar vía `.Source`, nunca vía `require`.
- **`screen_capture` con `camera_position` devuelve frames caché** (no refleja ediciones). La verificación visual definitiva es **en playtest**.
- Durante un playtest hay **2 sesiones MCP** (edición + juego): pasar `studio_id` explícito y `datamodel_type` correcto (`Client`/`Server`).
- `get_console_output` después de cada playtest: 0 errores antes de dar por cerrado un cambio.
- Input injection (`user_keyboard_input`, `datamodel_type: "Client"`) sirve para playtestear sin manos, pero la latencia entre llamadas supera la duración de un round → **meter todo el flujo de prueba en UNA sola llamada**.

## Síntomas ya diagnosticados (no reinventar)

| Síntoma | Causa real |
|---|---|
| Carga congelada en 0%, `attempt to index nil 'WaitForChild'` | Timeout de `WaitForChild` en cliente — PlayerGui tarda más que el timeout. **Fix aplicado 2026-10-07**: esperas sin timeout en los 4 archivos de `src/client/`. No reintroducir timeouts. |
| `StartGame` no hace nada y sin error | Se rechaza en silencio si `activeMode ~= nil` (partida/intermisión en curso). Confirmar escuchando `MatchUpdate`. |
| Juego no arranca, error de parseo en cascada | Alguien editó el place directamente (no en git). Barrido de hashes. |
| `getNameFromUserIdAsync` devuelve un desconocido con id de grupo | Comprobar `game.CreatorType` antes de leer `CreatorId`. |
| Rojo: `Kicked from Live Scripting Session`, un archivo deja de syncar | Workaround documentado en `MEMORY.md`: escribir `Source` con `execute_luau` y verificar `back == content`; **el disco sigue siendo la fuente de verdad**. |

## Convenciones

- **Comentarios y cabeceras en español**; cada script con cabecera de propósito.
- **Balance centralizado en `OilConfig`** (nunca números mágicos repartidos). Teclas en `OilControls`.
- **UI**: verde oliva oscuro + dorado (RGB 240,200,90), fuentes Gotham. Aplicar consistente.
- Progresión **100% en servidor** (`ProgressionLogic` puro → testeable): nada de lógica de progreso en cliente.
- `StarterGui` no lo gestiona Rojo → la UI se edita en Studio.

## Mapa rápido

Detalle completo en `docs/MEMORY.md` · núcleo de combate en `docs/OILCOMBAT.md`.

- `src/server/` → `MatchLoop` (orquestador), `OilCombat` (núcleo, ~1443 líneas), `ProgressionService/Logic/System`
- `src/shared/` → `OilConfig`, `OilPhysics`, `OilControls`, `OilSplash`, `ProgressionShared` + 10 RemoteEvents (`*.model.json`)
- `src/client/` → input/HUDs/menús/`CharacterAnimator` (animación procedural, 737 líneas)/`OilWinnerCeremony`
- `src/character/` → `Animate` (stub intencional que sustituye al Animate por defecto)
- Escena (solo Studio): `Workspace.OilWrestlingRing`, `OilArena`, coliseo, lobby, `StarterGui`
