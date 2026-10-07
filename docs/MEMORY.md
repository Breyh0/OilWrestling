# Memoria del proyecto — Lucha de aceite

> Última actualización: 2026-10-06 (limpieza inicial + **blindaje de remotes**). Reemplaza al antiguo `ServerStorage.ZeroScript.Memory` (ya eliminado — este archivo es la fuente de verdad). **Leer antes de tocar nada.**

## Overview

Combate de **lucha en aceite** en un coliseo romano: empujar al rival fuera del ring (ring-out). Primero en llegar a **3 puntos** gana. Modos: **solo** (vs IA "Gladiador IA", estática) y **multi** (hasta 4, matchmaking aleatorio).

## Datos del place

- placeId `76883498915584` · universe `10769662284` · propiedad del grupo **Kyubu Studio** — propietario: **supergamertth8**
- **Team Create activo** — trabajar SIEMPRE sobre la sesión viva, nunca sobre copias locales descargadas.
- Equipo: **Breyh0 + supergamertth8**, cada uno con su IA (opencode/Claude) vía Studio MCP.

## Equipo y flujo de trabajo

- **Código → archivos git** (`src/`) y Rojo lo sincroniza a Studio. Nunca editar scripts sincronizados en el editor de Studio (Rojo los pisa).
- **Escena/GUI → Studio** (Workspace, frames de StarterGui). git no fusiona `.rbxl`.
- `git pull` antes de empezar · `git push` al terminar.
- Los servicios mapeados por Rojo (SSS, ReplicatedStorage, StarterPlayerScripts, StarterCharacterScripts) contienen **solo** lo declarado en `src/`: si añades un hijo a mano en esos servicios, guárdalo también como archivo o el próximo sync lo borrará.
- **⚠️ El place cambia en vivo** (equipo en paralelo). Antes del primer `rojo serve` y tras cada periodo largo sin sincronizar: re-verificar que `#Source` de cada script en el place == bytes del archivo en `src/`. Si hay diferencia, **re-extraer ANTES de sincronizar** o los archivos (más viejos) pisarán los cambios hechos en Studio.
- Si Studio dice *"Couldn't connect to the Rojo server"* → no hay `rojo serve`: doble clic a `iniciar-rojo.bat` y volver a **Connect** en Studio.

## Dónde vive cada cosa

### Código → `src/` (sincronizado por Rojo) — extraído y verificado 1:1 (19 scripts → 17 tras limpieza)

- **`src/server/` → ServerScriptService**
  - `MatchLoop` (Script) — orquestador: StartGame(modo) → intermisión 15s → combate. Gestiona lobby, IA (clona `ServerStorage.FighterTemplate`), renuncias (OilResign), volver al menú (ReturnToMenu), token `session` para descartar esperas viejas, `ensureRemote` de sus remotes.
  - `OilCombat` (Module, **1443 líneas — el núcleo**) — API: `runMatch(defs)`, `resign(player)`, `abort()`, `isRunning()`, `perform(e, action, aim)`, `releaseHold`, `stopBlock`. Rondas, ring-out (bounds de `OilArena`), puntos, máquina de estados del luchador. Consume progresión: `RecordMatchEnd`, `RecordRingout`, `RecordParry`.
  - `ProgressionSystem` (Script) — bootstrapper: requiere `ProgressionService` con pcall.
  - `ProgressionService` (Module) — sesiones por jugador, DataStore `Progression_v1` (autosave 30s, cola 7s, retry ×3, PlayerRemoving + BindToClose), remotes RequestProgression (rate-limit 1/s) / UpdateProgression / MissionNotify, leaderstats.
  - `ProgressionLogic` (Module) — reglas **puras**: `ApplyMatch`, `ApplyEvent`, `Snapshot`, `Reconcile`, `EnsureToday`. SCHEMA=3 con migración v1/v2. Testeable sin juego.
- **`src/shared/` → ReplicatedStorage**
  - `OilConfig` — **fuente única de balance**: PointsToWin=3, RoundTimeout=45, acciones (Push/Charge/Grab), Balance, Stamina, Block/Parry/Dodge, slick ramp.
  - `OilPhysics` — inercia sobre aceite. Autoridad: el jugador ejecuta su paso; la IA lo ejecuta el servidor.
  - `OilControls` — fuente única de keybinds + BindableEvents locales (Request, ResignState) que HUD e input comparten.
  - `ProgressionShared` — curva de XP, rangos romanos (Tiro→Imperator), misiones D/S, resets UTC.
  - `*.model.json` — **10 RemoteEvents** declarados (StartGame, MatchUpdate, ReturnToMenu, OilResign, OilAction, OilEvent, OilKnock, UpdateProgression, MissionNotify, RequestProgression). *(PushEvent eliminada en la limpieza.)*
- **`src/client/` → StarterPlayerScripts**
  - `OilFighterClient` (input + física local + efectos; setea `PushStartTime` para la pose de empuje de FightIdle) · `OilCombatHUD` (barras equilibrio/stamina, estados, controles con cooldown, RENUNCIAR) · `OilRoundsHUD` (marcador de rounds best-of: nombres, círculos dorados, cuenta atrás, VICTORIA/DERROTA; solo lee eventos `OilEvent`) · `GameHUDClient` (top bar, countdown, MENÚ) · `MainMenuClient` (menú + tienda/códigos: UI cableada, **lógica aún placeholder**) · `LoadingScreenClient` (barra + tips aleatorios + fade) · `FighterGuiClient`.
- **`src/character/` → StarterCharacterScripts**
  - `FightIdle` (pose de guardia vía Motor6D C0; **no deshabilitar el Animate por defecto**). *(PushClient eliminado en la limpieza.)*

### Escena → solo Studio (NO gestionada por Rojo)

- `Workspace.OilWrestlingRing` (ring; bounds `OilArena` y≈5.6) · `StadiumEnclosure` · `Colosseum`/`ColosseumStructure`/`AmbientacionRomana` · `BroadcastBooth` (booth + 2 SpawnLocation del lobby) · `ActiveFighters` (runtime) · `Baseplate`, `Terrain`. *(Los 3 scripts `Hello World` fueron borrados.)*
- `StarterGui` — **rediseño de front hecho en Studio (2026-10-06)**:
  - `MainMenu`: panel Title+Subtitle+Divider, botones Play/Shop/Codes estilizados; ModePanel con tarjetas ricas (Icon/Name/Desc/Tag) Solo/Multi; **ShopPanel con Items (grid)** y **CodesPanel con CodeInput/RedeemBtn/Message** — UI construida y cableada, lógica de compra/canje pendiente.
  - `LoadingScreen`: Title con pulso + Tagline + barra con Shine + **Tip** (tips aleatorios) + **Particles** + **Vignette**.
  - `GameHUD`: TopBar (Status/Accent/ModeChip/TimerLabel), MenuBtn con **HoverScale**, Countdown con **Pop**.
  - `FighterGui`, `ProgressionUI` (+`ProgressionClient` LocalScript dentro — **pendiente**: moverlo a `src/client` refactorizando el lookup a `PlayerGui`).
- `ServerStorage`: solo `FighterTemplate` (rig R6 de la IA) + `__Rojo_SessionLock` (**marcador del plugin de Rojo — no borrar**). *(Se eliminaron `ZeroScript.Memory` y las3 carpetas `Respaldo_*`: su contenido histórico está en el historial de versiones de Studio.)*

### Datos

- DataStore `Progression_v1`. Progreso **100% en servidor** (ApplyEvent/ApplyMatch) → no spoofable. XP: victorias solo; ×0.75 vs IA. Monedas: partida 10 / victoria 30 / punto 2 (máx 20) / primera victoria del día 50.

## Convenciones

- UI: verde oliva oscuro + dorado (RGB 240,200,90), fuentes Gotham. Aplicar consistente.
- Balance centralizado en `OilConfig`; teclas en `OilControls` (HUD se auto-actualiza).
- Comentarios en español; cada script con cabecera de propósito.

## Gotchas

- **FightIdle vs Animate**: FightIdle setea C0 como base cada Heartbeat; las animaciones de andar se superponen. Nunca deshabilitar el Animate por defecto.
- Durante un playtest hay 2 sesiones MCP (edición + juego); usar `studio_id` explícito.
- `getNameFromUserIdAsync` con un id de **grupo** devuelve un usuario homónimo — comprobar siempre `game.CreatorType` antes de leer `CreatorId` (de ahí salió el "BrendaRichard38" falso).

## Limpieza hecha (2026-10-06)

- Eliminado el sistema legacy **PushClient/PushServer/PushEvent** (fijaba un impulso en el MISMO clic izquierdo que el empuje OilAction actual → **bug de doble empuje resuelto**; la pose FightIdle la dispara OilFighterClient:279).
- Eliminados 3× `Workspace.Script` (`print("Hello world!")`), `ZeroScript.Memory` y los 3 `Respaldo_*` de ServerStorage.
- Verificado: 0 referencias a los elementos borrados; servicios gestionados = solo lo declarado en `src/`.

## Blindaje de remotes (2026-10-06)

- Superficie entrante (cliente→servidor) =5 handlers: `StartGame` (validado: whitelist de modo + guard `activeMode`), `OilResign` (throttle 1s), `ReturnToMenu` (throttle 1s — **añadido**), `OilAction` (**blindado**), `RequestProgression` (throttle 1s + tabla weak). `OilEvent`/`OilKnock`/`MatchUpdate`/`UpdateProgression`/`MissionNotify` = solo server→client.
- `OilAction` (OilCombat): whitelist (`ACTIONS` + block/unblock, todo lo demás se descarta), throttle por jugador+acción con tabla weak (0.08s acciones — igual que el cliente legítimo — y 0.02s block/unblock), `aim` debe ser Vector3 finito (NaN/inf→nil, si no perform usa la mirada), y solo si el player está en `match.fighters`.
- El cooldown `cd_` lo pone **el servidor**: un paquete recortado por el throttle no cobra cooldown — el jugador puede reintentar enseguida.
- Mapa completo del núcleo: `docs/OILCOMBAT.md`.

## TODO / Known issues

- [x] ~~`OilAction` sin rate-limit ni validación de `aim`~~ → **blindado 2026-10-06** (ver sección Blindaje).
- [ ] **Bug alta**: si `runMatch` lanza un error interno, `match` queda ≠ `nil` para siempre → servidor deja de iniciar partidas (docs/OILCOMBAT.md, bug #1). Ver también #4 (`releaseFighter` sin `dropHolds`) y #6 (carrera con token `session` en MatchLoop).
- [ ] `OilCombat.doCharge`: busy-wait con `task.wait(0.03)` → migrar a Heartbeat (docs/OILCOMBAT.md, bug #2).
- [ ] Lógica de Tienda y Códigos (UI construida y cableada, `redeem()`/compras = placeholders).
- [ ] IA estática (sin comportamiento real).
- [ ] Mover `ProgressionClient` (StarterGui) a `src/client` con refactor de lookup a `PlayerGui`.
- [ ] Invitar a supergamertth8 al repo (Settings → Collaborators) y que ejecute SETUP.md.
- [ ] Tests automatizados. ~~Blindaje de seguridad de remotes~~ HECHO 2026-10-06 (ver sección Blindaje). ~~Extracción~~ HECHA: 17 scripts, verificación 1:1 por SHA-256.
