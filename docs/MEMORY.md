# Memoria del proyecto — Lucha de aceite

> Última actualización: 2026-10-07 (noche: 2 skills del repo (`lucha-workflow`, `lucha-qa`) + 46 tests de `ProgressionLogic` + `Reconcile` clampea `stats` como xp/coins; antes: suelo aceitoso + resbalón + salpicaduras + fix de GUI con `WaitForChild` con timeout). Reemplaza al antiguo `ServerStorage.ZeroScript.Memory` (ya eliminado — este archivo es la fuente de verdad). **Leer antes de tocar nada.**

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

### Código → `src/` (sincronizado por Rojo) — extraído y verificado 1:1 (19 scripts → 17 tras limpieza → 18 tras el cambio de animación → 19 con OilWinnerCeremony → **20 con OilSplash**)

- **`src/server/` → ServerScriptService**
  - `MatchLoop` (Script) — orquestador: StartGame(modo) → intermisión 15s → combate. Gestiona lobby, IA (clona `ServerStorage.FighterTemplate`), renuncias (OilResign), volver al menú (ReturnToMenu), token `session` para descartar esperas viejas, `ensureRemote` de sus remotes.
  - `OilCombat` (Module, **1443 líneas — el núcleo**) — API: `runMatch(defs)`, `resign(player)`, `abort()`, `isRunning()`, `perform(e, action, aim)`, `releaseHold`, `stopBlock`. Rondas, ring-out (bounds de `OilArena`), puntos, máquina de estados del luchador. Consume progresión: `RecordMatchEnd`, `RecordRingout`, `RecordParry`.
  - `ProgressionSystem` (Script) — bootstrapper: requiere `ProgressionService` con pcall.
  - `ProgressionService` (Module) — sesiones por jugador, DataStore `Progression_v1` (autosave 30s, cola 7s, retry ×3, PlayerRemoving + BindToClose), remotes RequestProgression (rate-limit 1/s) / UpdateProgression / MissionNotify, leaderstats.
  - `ProgressionLogic` (Module) — reglas **puras**: `ApplyMatch`, `ApplyEvent`, `Snapshot`, `Reconcile`, `EnsureToday`. SCHEMA=3 con migración v1/v2. Testeable sin juego.
- **`src/shared/` → ReplicatedStorage**
  - `OilConfig` — **fuente única de balance**: PointsToWin=3, RoundTimeout=45, acciones (Push/Charge/Grab), Balance, Stamina, Block/Parry/Dodge, slick ramp.
  - `OilPhysics` — inercia sobre aceite. Autoridad: el jugador ejecuta su paso; la IA lo ejecuta el servidor.
  - `OilSplash` — salpicaduras **cosméticas y locales** (gotas balísticas + onda en el charco, sin remotes): `splash(pos, power, {dir, ripple})`, `land(pos, impact)`, `knock(pos, dir)`. Lo usan CharacterAnimator (aterrizar/derribar) y OilFighterClient (impactos `fx`).
  - `OilControls` — fuente única de keybinds + BindableEvents locales (Request, ResignState) que HUD e input comparten.
  - `ProgressionShared` — curva de XP, rangos romanos (Tiro→Imperator), misiones D/S, resets UTC.
  - `*.model.json` — **10 RemoteEvents** declarados (StartGame, MatchUpdate, ReturnToMenu, OilResign, OilAction, OilEvent, OilKnock, UpdateProgression, MissionNotify, RequestProgression). *(PushEvent eliminada en la limpieza.)*
- **`src/client/` → StarterPlayerScripts**
  - `OilFighterClient` (input + física local + efectos; setea `PushStartTime` para la pose de empuje de FightIdle) · `OilCombatHUD` (barras equilibrio/stamina, estados, controles con cooldown, RENUNCIAR) · `OilRoundsHUD` (marcador de rounds best-of: nombres, círculos dorados, cuenta atrás, VICTORIA/DERROTA; solo lee eventos `OilEvent`) · `GameHUDClient` (top bar, countdown, MENÚ) · `MainMenuClient` (menú + tienda/códigos: UI cableada, **lógica aún placeholder**) · `LoadingScreenClient` (barra + tips aleatorios + fade) · `FighterGuiClient` · **`CharacterAnimator`** (737 líneas — animación **procedural para TODOS** los luchadores; lee State/Act/Blocking/Dazed/Held/Charging del servidor, poses sin assets, gestos en lobby; consume `PushStartTime`; ojo: el comentario de OilFighterClient:279 aún dice "FightIdle") · **`OilWinnerCeremony`** (336 líneas — ceremonia animada del ganador al recibir `OilEvent match_end`: rayos giratorios, confeti, corona, nombre con brillo, cuenta atrás; oculta si `match_start` vuelve o si vuelves al menú).
- **`src/character/` → StarterCharacterScripts**
  - `Animate` (stub **intencionalmente vacío** que reemplaza al Animate por defecto de Roblox, con `PlayEmote` falso; las poses las hace CharacterAnimator). *(FightIdle y PushClient eliminados — FightIdle lo reemplazó el sistema de animación del compañero.)*

### Escena → solo Studio (NO gestionada por Rojo)

- `Workspace.OilWrestlingRing` (ring; bounds `OilArena` y≈5.6) · `StadiumEnclosure` · `Colosseum`/`ColosseumStructure`/`AmbientacionRomana` · `BroadcastBooth` (booth + 2 SpawnLocation del lobby) · `ActiveFighters` (runtime) · `Baseplate`, `Terrain`. *(Los 3 scripts `Hello World` fueron borrados.)*
- `StarterGui` — **rediseño de front hecho en Studio (2026-10-06)**:
  - `MainMenu`: panel Title+Subtitle+Divider, botones Play/Shop/Codes estilizados; ModePanel con tarjetas ricas (Icon/Name/Desc/Tag) Solo/Multi; **ShopPanel con Items (grid)** y **CodesPanel con CodeInput/RedeemBtn/Message** — UI construida y cableada, lógica de compra/canje pendiente.
  - `LoadingScreen`: Title con pulso + Tagline + barra con Shine + **Tip** (tips aleatorios) + **Particles** + **Vignette**.
  - `GameHUD`: TopBar (Status/Accent/ModeChip/TimerLabel), MenuBtn con **HoverScale**, Countdown con **Pop**.
  - `FighterGui`, `ProgressionUI` (+`ProgressionClient` LocalScript dentro — **pendiente**: moverlo a `src/client` refactorizando el lookup a `PlayerGui`).
- `ServerStorage`: `FighterTemplate` (rig R6 de la IA) + `__Rojo_SessionLock` (**marcador del plugin de Rojo — no borrar**) + `Respaldo_Animacion` (creado por supergamertth8 el 2026-10-06 con `FightIdle_original` — **pendiente de decisión**: FightIdle ya está en el historial de git, candidato a borrar). *(Se eliminaron `ZeroScript.Memory` y las3 carpetas `Respaldo_*` antiguas.)*

### Datos

- DataStore `Progression_v1`. Progreso **100% en servidor** (ApplyEvent/ApplyMatch) → no spoofable. XP: victorias solo; ×0.75 vs IA. Monedas: partida 10 / victoria 30 / punto 2 (máx 20) / primera victoria del día 50.

## Convenciones

- UI: verde oliva oscuro + dorado (RGB 240,200,90), fuentes Gotham. Aplicar consistente.
- Balance centralizado en `OilConfig`; teclas en `OilControls` (HUD se auto-actualiza).
- Comentarios en español; cada script con cabecera de propósito.

## Gotchas

- **Animación (desde 2026-10-06)**: FightIdle ya **NO existe** — lo reemplazaron `CharacterAnimator` (procedural, anima a todos los luchadores) + `Animate` stub que **sustituye** al Animate por defecto **a propósito**. `PushStartTime` lo setea OilFighterClient:279 y lo consume CharacterAnimator (L386/L492).
- **⚠️ Duplicados al extraer**: si en Studio existe un script **manual** homónimo de un archivo que acaba de aparecer en `src/`, el plugin de Rojo crea una **SEGUNDA copia** en vez de adoptar la suya (no comparten metadata). Tras extraer scripts nuevos: contar por nombre con `GetChildren()` y deduplicar — conservar la **última** (la de Rojo, es la que sigue al archivo).
- Durante un playtest hay 2 sesiones MCP (edición + juego); usar `studio_id` explícito.
- **⏱️ Los 4 clientes se morían con `attempt to index nil 'WaitForChild'`** (LoadingScreen:13 / FighterGui:9 / GameHUD:12 / MainMenu:11): NO era ruido transitorio de compilación — hacían `WaitForChild(..., 10/20)` y en este place pesado PlayerGui tarda **más que el timeout** en poblarse → script muerto → carga congelada en 0% para siempre. **FIX 2026-10-07**: timeouts eliminados (espera infinita, patrón estándar) en los 4 archivos de `src/client`. Si vuelve el síntoma, revisar que no se hayan reintroducido timeouts.
- **Los `require()` de módulos del servidor fallan en contexto Edit** con `OnServerEvent can only be used on the server` / "Requested module experienced an error while loading" — es del contexto (plugin ≠ servidor), **no** es error de código. El test real es el playtest.
- `getNameFromUserIdAsync` con un id de **grupo** devuelve un usuario homónimo — comprobar siempre `game.CreatorType` antes de leer `CreatorId` (de ahí salió el "BrendaRichard38" falso).
- **📸 `screen_capture` con `camera_position` devuelve frames CACHÉ** (no refleja ediciones — el "misterio del suelo azul" era esto); en bruto es live pero puede ir con retardo tras editar. La verificación visual definitiva es **en playtest**, no por capturas de edición.
- **🔌 Rojo puede "kick"ear la sesión live** (`Kicked from Live Scripting Session: Server received illegal atomic operation`, stack `RbxDom.customProperties` ×3): puede dejar de syncear **un solo archivo** (2026-10-07: OilPhysics) mientras los demás siguen subiendo. Síntoma: `Source` del place viejo con archivo nuevo en disco. **Workaround**: escribir el `Source` directamente con `execute_luau` (`inst.Source = contenido` funciona desde el contexto de comando) y verificar `back == content`; el disco sigue siendo la fuente de verdad.
- **🧊 `require()` en contexto Edit cachea**: puede devolver valores VIEJOS si el módulo ya se cargó en la sesión (OilConfig nuevo devolvía Traction=2.6 con Source ya en 2.15). Verificar vía `.Source`, no vía `require`. El playtest carga fresco ✓.
- **🔇 `StartGame` se rechaza en silencio si `activeMode ~= nil`** (partida/intermisión en curso) — síntoma: nada pasa y sin error. Confirmar escuchando `MatchUpdate` (evento `intermission/N` = aceptado). Intermisión = 15s; IA en `ServerStorage.FighterTemplate`.
- **🎮 Hay input injection**: `user_keyboard_input` / `user_mouse_input` (acciones `keyDown`/`keyUp`/`keyPress`/`wait`, `datamodel_type: "Client"`) — sirve para playtestears sin manos. OJO: la latencia entre llamadas del modelo (~30-60s) **supera la duración de un round** → meter TODO el flujo de prueba (esperar partida + teclas + sondeos) en **UNA sola llamada** `execute`.

## Limpieza hecha (2026-10-06)

- Eliminado el sistema legacy **PushClient/PushServer/PushEvent** (fijaba un impulso en el MISMO clic izquierdo que el empuje OilAction actual → **bug de doble empuje resuelto**; la pose de empuje la dispara OilFighterClient:279 y hoy la consume CharacterAnimator).
- Eliminados 3× `Workspace.Script` (`print("Hello world!")`), `ZeroScript.Memory` y los 3 `Respaldo_*` de ServerStorage.
- Verificado: 0 referencias a los elementos borrados; servicios gestionados = solo lo declarado en `src/`.

## Sincronización place → repo (2026-10-06, cambios de supergamertth8)

- **Nuevo sistema de animación**: `CharacterAnimator` (SPS, 737 líneas — procedural para TODOS, lee el estado que publica el servidor) + `Animate` stub (SCS) — **reemplazan a FightIdle** (eliminado del place en todo el DataModel). Compat verificada: consume `PushStartTime` ✓.
- Extraído 1:1 (31476 y 520 bytes, comparación carácter a carácter con relectura doble); duplicados creados por Rojo al aparecer los archivos → deduplicados (conservada la copia de Rojo); `FightIdle` borrado de `src/` para que el próximo sync no lo recree.

## Incidente: daño de la IA del compañero (2026-10-07)

- **Síntoma**: el juego no arrancaba — `ReplicatedStorage.OilPhysics:1: Expected identifier when parsing expression, got '/'` → cascada: OilCombat:22, MatchLoop:12, OilFighterClient:17 no cargaban.
- **Causa**: la IA de supergamertth8 editó `OilPhysics` **directamente en el place** (no en git) y le añadió un `/` delante de la cabecera (`/-- OilPhysics...` — artefacto markdown). Un solo byte, cero cambios intencionales (verificado por FNV32: place−`/` == archivo byte a byte).
- **Reparación**: `/` eliminada vía MCP en el place. Barrido FNV32 de los19 scripts place↔`src/`: **todos idénticos** — no hubo otro daño. Playtest limpio18s ✓.
- **Lección**: las IAs del compañero **editan el place directamente**. Tras cada sesión de él: correr el barrido de hashes (execute_luau FNV en place + `Get-ChildItem src` FNV en archivos) antes de sincronizar o tocar nada.
- **Nuevo script suyo**: `OilWinnerCeremony` (SPS,10417 B) — extraído1:1 a `src/client/OilWinnerCeremony.client.luau` (FNV548097969 ✓) y deduplicado el clone que Rojo creó al aparecer el archivo.

## Blindaje de remotes (2026-10-06)

- Superficie entrante (cliente→servidor) =5 handlers: `StartGame` (validado: whitelist de modo + guard `activeMode`), `OilResign` (throttle 1s), `ReturnToMenu` (throttle 1s — **añadido**), `OilAction` (**blindado**), `RequestProgression` (throttle 1s + tabla weak). `OilEvent`/`OilKnock`/`MatchUpdate`/`UpdateProgression`/`MissionNotify` = solo server→client.
- `OilAction` (OilCombat): whitelist (`ACTIONS` + block/unblock, todo lo demás se descarta), throttle por jugador+acción con tabla weak (0.08s acciones — igual que el cliente legítimo — y 0.02s block/unblock), `aim` debe ser Vector3 finito (NaN/inf→nil, si no perform usa la mirada), y solo si el player está en `match.fighters`.
- El cooldown `cd_` lo pone **el servidor**: un paquete recortado por el throttle no cobra cooldown — el jugador puede reintentar enseguida.
- Mapa completo del núcleo: `docs/OILCOMBAT.md`.

## Sesión 2026-10-07 (tarde): suelo aceitoso + resbalón + salpicaduras

- **`OilConfig`**: Traction 2.6→**2.15**, Glide 1.35→**0.95** (más derrape), SlickMax 2.0→**2.3**, nuevos `TurnSlick=1.1`, `TurnSlickMax=1.8`, `TurnSlickDecay=4.5`.
- **`OilPhysics`**: **turn-slip** en `stepOne` — si la intención cambia brusca (dot<0.98 con la del frame anterior, `prevIntent` capturado antes de sobreescribir `st.lastIntent`) sube `st.turnSlick` y multiplica el rate de tracción `CFG.Traction / (slick * (1 + turnSlick))`; decae exponencial (`TurnSlickDecay`). Campo `turnSlick` inicializado en `attach`.
- **`CharacterAnimator`**: pose **`POSE.slip`** (tras `skid`; peso `slip` = velocidad × |yawRate|; molinete procedural con `S.slipPhase` — piernas alternas, torso y brazos balanceados), `busy += W.slip*0.7`, y **ganchos de salpicadura**: aterrizaje (`impact>6` + **gate `OilPhysics.isOverArena`** — no salpica en el lobby) y borde knocked → `OilSplash.knock(S.floorPos, vel)`. Requiere `OilSplash`/`OilPhysics` con `WaitForChild(10)` + guards.
- **Nuevo `src/shared/OilSplash.luau`** (módulo cosmético local, sin remotes): gotas balísticas (2 tweens sube/cae, 4–13 por ráfaga) + onda disco achatado con TweenService/Debris; APIs `splash(pos, power, {dir, ripple})`, `land(pos, impact)`, `knock(pos, dir)`.
- **`OilFighterClient`**: tabla `FX_SPLASH` (hit .45, counter .6, throw .8, launch 1, grab .5, dodge .3, dash .3, break .7, ringout 1) → `OilSplash.splash` en el handler `fx`.
- **Fix GUI (crítico)**: sin timeouts de `WaitForChild` en LoadingScreenClient/FighterGuiClient/GameHUDClient/MainMenuClient (ver Gotchas).
- **Verificado en playtest 2026-10-07**: 0 errores de juego; `OilSlick` ciclando (1.117); gotas vistas **153** en pelea real / **121** splash directo / **117** tras knock simulado; onda = **8–9 muestras** a 0.05s (exactamente 1 vida útil ✓); knock → `PlatformStand=true` → splash ✓; gate de lobby ✓; suelo ámbar con borde dorado y sheen en vivo ✓.

## Skills y tests del repo (2026-10-07, noche)

Las IAs de los dos compañeros cargan estas skills automáticamente desde el repo (`git pull` para tenerlas):

- **`.opencode/skills/lucha-workflow/SKILL.md`** (`lucha-workflow`) — reglas duras del equipo: código solo en `src/`, escena/GUI solo en Studio, flujo `git pull` → Rojo → push, verificación place↔src por hashes FNV, tabla de síntomas ya diagnosticados. **Es la versión corta y operativa de esta memoria**: si algo contradice a este archivo, manda este.
- **`.opencode/skills/lucha-qa/SKILL.md`** (`lucha-qa`) — capa de verificación: playtest → captura → consola (0 errores), cuándo usar cada skill del MCP de Roblox, medir posiciones reales en vez de suponer, probar UI en móvil y revertir el simulador de dispositivos al terminar.

**Tests unitarios** (`src/server/UnitTest/`, sincronizado por Rojo a `ServerScriptService.UnitTest`):

- `RunUnitTest.luau` — arnés propio (sin TestEZ ni Wally). Descubre `Cases/`, ejecuta cada caso aislado con timeout y resume por consola.
- `Cases/ProgressionLogic_Test.luau` — **46 casos en verde**: `Reconcile` (saneo + migración v1/v2→v3), `EnsureToday`, `AddCoins`, `AddXP`, `ApplyEvent` (misiones y bonos), `ApplyMatch` (balance, abandono, racha, multiplicador IA), `Snapshot`. Deterministas: el reloj se inyecta con una marca fija, nunca `os.time`.
- Ejecutar: `require(ServerScriptService.UnitTest.RunUnitTest)("ProgressionLogic")` con `execute_luau` en `Server` durante un playtest; resultados en la consola (`[PASS]`/`[FAIL]`/`[SUMMARY]`). Parcial: solo `ProgressionLogic` — `OilCombat` y `OilPhysics` siguen sin cubrir (dependen del juego).
- Regla: si un test falla porque el módulo contradice su contrato, **el test se queda rojo y se reporta**; nunca se relaja la expectativa para poner la suite en verde.

**Arreglo 2026-10-07**: `Reconcile` ya clampea `stats` igual que `xp`/`coins` (`math.max(0, math.floor(n))`); antes solo sustituía valores no numéricos, así que un save corrupto con `wins = -5` conservaba el negativo y llegaba a los leaderstats.

**Grafo de conocimiento** (graphify, `graphify-out/` va en `.gitignore`): 318 nodos / 621 aristas / 38 comunidades. Preguntas de arquitectura ("qué llama a OilCombat.perform", "qué toca el suelo aceitoso") → responder con `graphify query "..."` en vez de releer 1400 líneas. `OILCOMBAT.md` es el puente documental→código (3 de sus 6 aristas cruzan de comunidad).

## TODO / Known issues


- [x] ~~`OilAction` sin rate-limit ni validación de `aim`~~ → **blindado 2026-10-06** (ver sección Blindaje).
- [ ] **Bug alta**: si `runMatch` lanza un error interno, `match` queda ≠ `nil` para siempre → servidor deja de iniciar partidas (docs/OILCOMBAT.md, bug #1). Ver también #4 (`releaseFighter` sin `dropHolds`) y #6 (carrera con token `session` en MatchLoop).
- [ ] `OilCombat.doCharge`: busy-wait con `task.wait(0.03)` → migrar a Heartbeat (docs/OILCOMBAT.md, bug #2).
- [ ] Lógica de Tienda y Códigos (UI construida y cableada, `redeem()`/compras = placeholders).
- [ ] IA estática (sin comportamiento real).
- [ ] Mover `ProgressionClient` (StarterGui) a `src/client` con refactor de lookup a `PlayerGui`.
- [ ] Invitar a supergamertth8 al repo (Settings → Collaborators) y que ejecute SETUP.md.
- [ ] Tests automatizados → **parcial 2026-10-07**: `ProgressionLogic` cubierto con 46 casos (`src/server/UnitTest/`). Pendiente: `OilCombat` y `OilPhysics` (dependen del juego → necesitan stubs). ~~Blindaje de seguridad de remotes~~ HECHO 2026-10-06 (ver sección Blindaje). ~~Extracción~~ HECHA: 17 scripts, verificación 1:1 por SHA-256.
