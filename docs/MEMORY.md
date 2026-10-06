# Memoria del proyecto — Lucha de aceite

> Última actualización: 2026-10-06. Reemplaza a `ServerStorage.ZeroScript.Memory` (obsoleta, se borrará en la fase de limpieza). **Leer este archivo antes de tocar nada.**

## Overview

Combate de **lucha en aceite** en un coliseo romano: empujar al rival fuera del ring (ring-out). Primero en llegar a **3 puntos** gana. Modos: **solo** (vs IA "Gladiador IA", estática) y **multi** (hasta 4, matchmaking aleatorio).

## Datos del place

- placeId `76883498915584` · universe `10769662284` · propietario **BrendaRichard38**
- **Team Create activo** — trabajar SIEMPRE sobre la sesión viva, nunca sobre copias locales descargadas.
- Equipo: **Breyh0 + BrendaRichard38**, cada uno con su IA (opencode/Claude) vía Studio MCP.

## Equipo y flujo de trabajo

- **Código → archivos git** (`src/`) y Rojo lo sincroniza a Studio. Nunca editar scripts sincronizados en el editor de Studio (Rojo los pisa).
- **Escena/GUI → Studio** (Workspace, frames de StarterGui). git no fusiona `.rbxl`.
- `git pull` antes de empezar · `git push` al terminar.
- Los servicios mapeados por Rojo (SSS, ReplicatedStorage, StarterPlayerScripts, StarterCharacterScripts) contienen **solo** lo declarado en `src/`: si añades un hijo a mano en esos servicios, guárdalo también como archivo o el próximo sync lo borrará.
- **⚠️ El place cambia en vivo** (equipo en paralelo). Antes del primer `rojo serve` y tras cada periodo largo sin sincronizar: re-verificar que `#Source` de cada script en el place == bytes del archivo en `src/`. Si hay diferencia, **re-extraer ANTES de sincronizar** o los archivos (más viejos) pisarán los cambios hechos en Studio.

## Dónde vive cada cosa

### Código → `src/` (sincronizado por Rojo) — extraído y verificado 1:1 el 2026-10-06 (19 scripts, SHA-256)

- **`src/server/` → ServerScriptService**
  - `MatchLoop` (Script) — orquestador: StartGame(modo) → intermisión 15s → combate. Gestiona lobby, IA (clona `ServerStorage.FighterTemplate`), renuncias (OilResign), volver al menú (ReturnToMenu), token `session` para descartar esperas viejas, `ensureRemote` de sus remotes.
  - `OilCombat` (Module, **1443 líneas — el núcleo**) — API: `runMatch(defs)`, `resign(player)`, `abort()`, `isRunning()`, `perform(e, action, aim)`, `releaseHold`, `stopBlock`. Rondas, ring-out (bounds de `OilArena`), puntos, máquina de estados del luchador (idle, pushed, stunned, knocked, grabbed, grabbing, blocking, dodging, offbalance, invulnerable). Consume progresión: `RecordMatchEnd`, `RecordRingout`, `RecordParry`.
  - `PushServer` (Script) — handler legacy de `PushEvent` (impulso simple, cooldown 1.5s). **¿Sobrevive? candidato a eliminar.**
  - `ProgressionSystem` (Script) — bootstrapper: requiere `ProgressionService` con pcall.
  - `ProgressionService` (Module) — sesiones por jugador, DataStore `Progression_v1` (autosave 30s, cola 7s, retry ×3, PlayerRemoving + BindToClose), remotes RequestProgression (rate-limit 1/s) / UpdateProgression / MissionNotify, leaderstats.
  - `ProgressionLogic` (Module) — reglas **puras** sobre la tabla de datos: `ApplyMatch`, `ApplyEvent`, `Snapshot`, `Reconcile`, `EnsureToday`. SCHEMA=3 con migración v1/v2. Testeable sin juego.
- **`src/shared/` → ReplicatedStorage**
  - `OilConfig` — **fuente única de balance**: PointsToWin=3, RoundTimeout=45, acciones (Push/Charge/Grab), Balance, Stamina, Block/Parry/Dodge, slick ramp.
  - `OilPhysics` — movimiento con inercia sobre aceite. Autoridad: el jugador ejecuta su paso; la IA lo ejecuta el servidor (`slickify`, `knock`, `step`, `getArena`).
  - `OilControls` — fuente única de keybinds + BindableEvents locales (Request, ResignState) que el HUD y el input comparten.
  - `ProgressionShared` — curva de XP, rangos romanos (Tiro→Imperator), misiones diarias/semanales, cálculo de resets UTC.
  - `*.model.json` — los 11 RemoteEvents declarados (PushEvent, StartGame, MatchUpdate, ReturnToMenu, OilResign, OilAction, OilEvent, OilKnock, UpdateProgression, MissionNotify, RequestProgression). Antes se creaban en runtime con `ensureRemote`; ahora son permanentes.
- **`src/client/` → StarterPlayerScripts**
  - `OilFighterClient` (input + física local + efectos) · `OilCombatHUD` (barras equilibrio/stamina, estados, controles con cooldown, RENUNCIAR — el marcador de rounds se movió a OilRoundsHUD) · `OilRoundsHUD` (marcador de rounds best-of: nombres, círculos dorados, cuenta atrás, ¡LUCHA!, VICTORIA/DERROTA; **solo lee** eventos `OilEvent` — match_start/countdown/go/point/roster/forfeit/match_end — y oculta el FighterGui antiguo durante el combate) · `GameHUDClient` (top bar, countdown, botón MENÚ) · `MainMenuClient` (JUGAR/TIENDA/CODIGOS, modos) · `LoadingScreenClient` · `FighterGuiClient`.
- **`src/character/` → StarterCharacterScripts**
  - `FightIdle` (pose de guardia vía Motor6D C0; **no deshabilitar el Animate por defecto** — ver gotchas) · `PushClient`.

### Escena → solo Studio (NO gestionada por Rojo)

- `Workspace.OilWrestlingRing` (ring; bounds `OilArena` y≈5.6) · `StadiumEnclosure` · `Colosseum`/`ColosseumStructure`/`AmbientacionRomana` · `BroadcastBooth` (booth + 2 SpawnLocation del lobby — MatchLoop toma el primero) · `ActiveFighters` (runtime) · `Baseplate`, `Terrain`.
- `StarterGui`: FighterGui, LoadingScreen, MainMenu (ModePanel/ShopPanel/CodesPanel), GameHUD, ProgressionUI + `ProgressionClient` LocalScript dentro. **Pendiente**: moverlo a `src/client` — usa `local gui = script.Parent` y setea `ResetOnSpawn/DisplayOrder/IgnoreGuiInset/ZIndexBehavior` sobre él, así que al moverlo hay que refactorizar el lookup a `player.PlayerGui:WaitForChild("ProgressionUI")`. No está en git hasta entonces.
- `ServerStorage`: `FighterTemplate` (rig R6 de la IA), `Respaldo_*` (respaldos manuales → reemplazados por git), `ZeroScript.Memory` (borrar al confirmar este archivo).

### Datos

- DataStore `Progression_v1`. Progreso de misiones calculado **100% en servidor** (ApplyEvent/ApplyMatch) → no spoofable desde cliente. XP: victorias solo; ×0.75 vs IA. Monedas: partida 10 / victoria 30 / punto 2 (máx 20) / primera victoria del día 50.

## Convenciones

- UI: verde oliva oscuro + dorado (RGB 240,200,90), fuentes Gotham. Aplicar consistente.
- Balance centralizado en `OilConfig`; teclas en `OilControls` (HUD se auto-actualiza).
- Comentarios en español; cada script con cabecera de propósito.

## Gotchas

- **FightIdle vs Animate**: FightIdle setea C0 de los Motor6D cada Heartbeat como base; las animaciones de andar se superponen encima. Nunca deshabilitar el Animate por defecto (el personaje queda congelado). Entrará en conflicto con futuras animaciones de combate reales.
- Durante un playtest hay 2 sesiones MCP (edición + juego); usar `studio_id` explícito.

## TODO / Known issues

- [ ] `OilAction`: sin rate-limit ni validación de `aim` (solo `type` check) antes de `perform()`.
- [ ] `OilCombat.doCharge`: busy-wait con `task.wait(0.03)` → migrar a Heartbeat.
- [ ] `PushServer`/`PushEvent`/`PushClient`: ¿legacy del sistema anterior a OilCombat? Verificar y eliminar si sobra.
- [ ] 3× `Workspace.Script` = `print("Hello world!")` → borrar.
- [ ] Tienda y Códigos del menú = placeholders (prints).
- [ ] IA estática (sin comportamiento real).
- [ ] Mover `ProgressionClient` (StarterGui) a `src/client` con el refactor de lookup indicado arriba.
- [ ] Borrar `ServerStorage.ZeroScript.Memory` y `Respaldo_*` tras validar este archivo.
- [ ] Blindaje de seguridad de remotes + tests. ~~Extracción~~ **HECHA 2026-10-06**: 19 scripts, verificación 1:1 por SHA-256.
