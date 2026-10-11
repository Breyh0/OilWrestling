# Memoria del proyecto — Lucha de aceite

> Última actualización: **2026-10-11** (presupuesto de rendimiento: medido de verdad en playtest, con ruido de medición cuantificado — ver `docs/RENDIMIENTO.md` y `tools/medir_fps.luau`. sistema de sonido mergeado a `main`, método de equipo completo, `docs/LECCIONES.md` con los fallos de la IA, bug #1 y #2 de `docs/OILCOMBAT.md` arreglados, 46 tests de `ProgressionLogic`). Reemplaza al antiguo `ServerStorage.ZeroScript.Memory` (ya eliminado — este archivo es la fuente de verdad). **Leer antes de tocar nada.**

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

## Preflight de Luau — obligatorio antes de sincronizar (2026-10-10)

```powershell
python tools\lua_preflight.py src     # sale con codigo 1 si hay problemas
```

No hay compilador de Luau en la máquina, así que esto es lo que sustituye al playtest para los fallos que **no dan error visible**. Salva cinco, todos.Trace:

1. **Palabra reservada usada como nombre** (`lane = { until = 0 }`) → el script entero no compila y **no suena / no hace nada**, sin error en Rojo. Solo lo delata la consola del playtest (`Expected identifier when parsing expression, got 'until'`).
2. **Referencia adelantada**: usar un `local` declarado más abajo → Luau lo busca como global, o sea `nil` en runtime → `attempt to call a nil value`.
3. **Bloques o paréntesis sin cerrar.**
4. **Instancia huérfana**: `Instance.new()` asignado a un local, usado como hijo (`algo = nombre`) y **sin `.Parent` en ningún sitio**. Sin Parent no suena, no sale en ningún `GetDescendants()` y **no da ningún error**. Fue el fallo de los sonidos 3D.
5. **Alfabeto ajeno** (ideogramas, cirílico): compilan igual y no se ven ni en el diff.

Cada regla tiene autotest (archivos con el fallo planted) y hay que pasarlos antes de fiarse de ella: una regla que nunca salta no vale nada, y ya hubo una con un typo (`Instance%.new`) que no detectaba nada.

**Además, antes de dar cualquier cosa por buena: playtest + `get_console_output` con 0 errores.** Sin compile, el preflight es una red, no una garantía.

## Ramas (2026-10-10)

`main` es la versión buena y probada. El trabajo nuevo va a `feature/<nombre>` y **solo
se merges a `main` después de verificarlo en playtest**, con el visto bueno del usuario.
La primera fue `feature/sonidos` (SoundDirector), mergeada con `--no-ff`.

Método completo en `docs/WORKFLOW.md`; skill operativa en `.opencode/skills/lucha-ramas/`.

## Documentación (2026-10-10)

| Documento | Qué guarda |
|---|---|
| `docs/MEMORY.md` | **Fuente de verdad.** Gotchas, estado, reglas del equipo |
| `docs/WORKFLOW.md` | Método de trabajo: ciclo, puerta de calidad, ramas, code review |
| `docs/ESCENA.md` | La capa que no está en git: por qué, cómo se vigila, qué ha encontrado |
| `docs/DATOS.md` | Contrato de datos del jugador: los 4 toques, esquema y migraciones |
| `docs/OILCOMBAT.md` | Mapa técnico del combate |
| `docs/PREFLIGHT.md` | Reglas del preflight de Luau y sus autotests |
| `CHANGELOG.md` | Qué se publica en cada versión |
| `escena/MANIFIEST-ESCENA.md` | Inventario versionado de la escena, con huella |
| `checkpoint/2026-10-10-estado-del-lugar/` | Trabajo del compañero rescatado del place, con hashes |

Skills: `lucha-workflow` (reglas duras), `lucha-qa` (verificación), `lucha-ramas`
(ramas y merges), `lucha-revision` (revisar cambios antes de que entren), `lucha-feature`
(añadir un sistema nuevo de principio a fin).

Puerta automática: `.github/workflows/quality.yml` corre preflight + autotests en cada
push y PR a `main`. **No sustituye al playtest**: los 46 tests de Luau necesitan Roblox y
siguen siendo manuales.

**`main` está protegida** (ruleset `main protegida`, activo y **verificado** el
2026-10-11 con un push de prueba que GitHub rechazó con `GH013`):

| Regla | Efecto |
|---|---|
| `deletion` | Nadie borra `main` |
| `non_fast_forward` | Nadie la reescribe con force-push |
| `pull_request` | Todo cambio entra por PR, con 0 aprobaciones requeridas |
| `required_status_checks` | Los 3 jobs de la CI tienen que pasar antes de mergear |

Bypass list vacía: nadie se salta la regla, ni el dueño. **0 aprobaciones y no 1** porque
GitHub no deja aprobar tu propio PR; con 1 te bloqueabas solo. Cuando el compañero empiece
a trabajar en el repo, se sube a 1.

Consecuencia práctica: **`main` ya no se actualiza con `git push` directo**. Se sube la
rama y se mergea el PR. `gh` (GitHub CLI) está instalado en la máquina y autenticado como
`Breyh0`, así que el PR se puede abrir y mergear con `gh pr`.

Detalle técnico que costó tiempo: los status checks **no bloquean un `git push` directo**
por sí solos. La regla que lo cierra es `pull_request`. Probado: con el ruleset vacío el
push entraba; con las cuatro reglas, rechazado.

Grafo de conocimiento en `graphify-out/` (local, gitignored). Actualizado el 2026-10-10:
**494 nodos, 957 aristas, 40 comunidades**. Se refresca con `/graphify . --update`.

## Escena (2026-10-10)

`Workspace`, `StarterGui` y `SoundService` **no están en git**. El archivo del lugar no se
versiona a propósito: lleva los scripts dentro (dos fuentes de verdad), no se puede
diffear y no tiene merge. `*.rbxl` y `*.rbxlx` están en `.gitignore` para que nadie lo
suba por error.

- **La red de verdad es publicar el place**: el historial de versiones de Roblox. Sin
  publicar, la escena no existe.
- **Para detectarla**: `escena/inventario.luau` genera `escena/MANIFIEST-ESCENA.md`, que sí
  está en git. `python tools\verificar_escena.py` comprueba que nadie lo editó a mano.
- Huella del estado del 2026-10-10: `3218896102`.

Hallazgos del primer inventario, que nadie tenía registrados:

- ⚠️ **El ring se movió al origen**: `OilArena` pasó de `(4, 6.1, -36)` a `(0, 6.1, 0)`, y
  con él `GoldFrame`, `MarbleTier` y `PedestalBase`. **No rompe el juego**: `OilPhysics` y
  `OilCombat` leen el ring dinámicamente y hay un `SpawnLocation` real
  (`BroadcastBooth.BoothSpawn2`), así que el fallback de `getLobbyCFrame()` no se usa.
  **Decidido: dejarlo como está.** El `checkpoint/` del 10 de octubre está desactualizado
  en ese dato.
- **3 `Part` sueltos a ~3000 studs**, con nombre por defecto, sin hijos y sin referencias
  desde ningún script (las 7 apariciones de `"Part"` en el código son `Instance.new`).
  **Borrados** con visto bueno del usuario. Workspace: 5106 → 5103 objetos.

## Sistema de sonido (2026-10-10, `src/client/SoundDirector.client.luau`)

Los **11 sonidos de `SoundService` nunca sonarían**: no había ni una referencia a `Sound` en todo `src/`. Los recursos viven fuera de los servicios que Rojo gestiona (Rojo no los toca), pero el código que los disparaba estaba en un servicio gestionado y se perdió al sincronizar.

- Es **aditivo**: solo escucha `OilEvent`, que el servidor ya emitía. No toca `OilCombat` ni ningún otro archivo.
- **Mezcla por prioridad**: FONDO (impactos, esquiva, embestida) / IMPORTANTE (salpicadura, público) / PROTAGONISTA (cuenta atrás, silbato, victoria). Una sola plaza: entra lo más importante y echa a los demás.
- **Ducking**: la música baja sola mientras suena una pieza y vuelve sola (con token). Es lo que hace que los pitidos de la cuenta atrás se oigan sin subirlos a tope.
- Volúmenes ajustados **en copia**, nunca en los de `SoundService`. `MUSIC_GAIN` al principio del archivo.
- Los tipos de `fx` que emite OilCombat de verdad son: `hit`, `counter`, `throw`, `block`, `parry`, `launch`, `dodge`, `guardbreak`, `grab`, `break`, `dash`, `ringout`, `victory`. `hit`/`counter`/`throw` son los más frecuentes. Sin mapear suenan mudos.

## Limpieza hecha (2026-10-06)

- Eliminado el sistema legacy **PushClient/PushServer/PushEvent** (fijaba un impulso en el MISMO clic izquierdo que el empuje OilAction actual → **bug de doble empuje resuelto**; la pose de empuje la dispara OilFighterClient:279 y hoy la consume CharacterAnimator).
- Eliminados 3× `Workspace.Script` (`print("Hello world!")`) y los 3 `Respaldo_*` de ServerStorage.
- Verificado: 0 referencias a los elementos borrados; servicios gestionados = solo lo declarado en `src/`.
- ⚠️ **Corrección 2026-10-10**: `ZeroScript.Memory` **NO** fue borrado, sigue en el place dentro de `ServerStorage.ZeroScript.Memory` (FNV `1838474336`, 1838 bytes). Esta línea decía lo contrario y el grafo lo detectó como contradicción. **No borrar**: es un marcador conocido.

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

### Rendimiento: MEDIDO el 2026-10-11 (cerrado, con resultados)

Detalle completo en **`docs/RENDIMIENTO.md`**. Resumen para no releer todo:

- Lobby **21,6 ms** (46 fps) · durante un combate **22,2 ms** (45 fps). Pelear cuesta
  **0,5 ms** más que esperar: el peso es la escena, no el combate.
- **Ruido de la medición: 0,72 ms (3 %)** con cinco pasadas idénticas. Cualquier efecto
  menor que eso no es un hallazgo. Por eso existe `tools/medir_fps.luau`, que exige
  superar el ruido de las dos mediciones sumadas antes de afirmar nada.
- **Nada en la escena es un cuello de botella demostrable.** Apagar sombras (0,79 ms) y
  las 54 luces (0,44 ms) queda dentro del ruido combinado (2,61 ms). Poner el coliseo o
  el público a `Transparency = 1` **empeora** el frame time, porque los objetos
  transparentes se siguen dibujando: no es una forma de apagar nada.
- `StreamingEnabled` ya está en `true`. Luces: 54, solo 1 con sombras.
- Presupuesto con números en `RENDIMIENTO.md`. Thresholds de aviso puestos por encima de
  los ~21,9 ms de Studio a propósito, porque Studio no es la referencia.

**Sin medir todavía:** móvil (nada, y es lo que manda), memoria (`Stats.MemoryTotalMb`
no está expuesto en este entorno), cliente publicado, servidor con carga, y el coste de
la GUI (417 objetos, uno de 257 en `MainMenu`).

**Regla nueva:** antes y después de cualquier cambio que afecte al render, medir con
`medir_fps.luau` (4 repeticiones mínimo) y escribir el número en `CHANGELOG.md` solo si
`Comparar` dice DIFERENCIA REAL.


- [x] ~~`OilAction` sin rate-limit ni validación de `aim`~~ → **blindado 2026-10-06** (ver sección Blindaje).
- [x] ~~**Bug alta**: `runMatch` dejaba `match` colgado~~ → **ARREGADO 2026-10-07**: el cuerpo es `runMatchBody` y `OilCombat.runMatch` lo envuelve en `pcall` + `forceCleanup()` (limpia `match`, `OilMatchActive`/`OilSlick` y libera cada luchero). Verificado inyectando un error real: 0 huérfanos y el combate siguiente arranca.
- [x] ~~#4 `releaseFighter` sin `dropHolds`~~ · ~~#5 callbacks pospuestos leían el `match` global~~ · ~~#6 carrera del token `session`~~ · ~~#7 bucle de IA~~ → **TODOS ARREGLADOS 2026-10-07**: cada entrada de luchador guarda `e.match = m` y el helper `sameMatch(e, m)` (OilCombat L708) exige combate no nulo, `match == m`, `e.match == m` y `not e.released`. Lo usan el windup de `doPush`, el windup y el lanzamiento de `doGrab`, `tickCharges`, el bucle de IA y `canKeepActing(e, m)`. `releaseFighter` empieza con `dropHolds(e)`. En `MatchLoop`, `clearAIFighters(ai)` destruye solo el modelo de su propia sesión y `runSoloFight` re-chequea `mySession == session` antes de `spawnAI()`. **Regla para lo nuevo: cualquier `task.delay`/`task.spawn` que toque estado de combate debe llevar `sameMatch(e, m)`.**
- [x] ~~`OilCombat.doCharge`: busy-wait `task.wait(0.03)`~~ → **ARREGADO 2026-10-07**: las embestidas están en `activeCharges` y las mueve `tickCharges()` desde el Heartbeat del módulo (1 chequeo por frame, sin despertares extra). Se conserva el retardo de 30ms del primer impacto: el balance no cambia.
- [ ] Lógica de Tienda y Códigos (UI construida y cableada, `redeem()`/compras = placeholders).
- [ ] IA estática (sin comportamiento real).
- [ ] Mover `ProgressionClient` (StarterGui) a `src/client` con refactor de lookup a `PlayerGui`.
- [ ] Invitar a supergamertth8 al repo (Settings → Collaborators) y que ejecute SETUP.md.
- [ ] Tests automatizados → **parcial 2026-10-07**: `ProgressionLogic` cubierto con 46 casos (`src/server/UnitTest/`). Pendiente: `OilCombat` y `OilPhysics` (dependen del juego → necesitan stubs). ~~Blindaje de seguridad de remotes~~ HECHO 2026-10-06 (ver sección Blindaje). ~~Extracción~~ HECHA: 17 scripts, verificación 1:1 por SHA-256.
