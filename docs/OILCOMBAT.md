# OILCOMBAT — mapa técnico del núcleo de combate

> Fuente: `src/server/OilCombat.luau` (**1469 líneas**, leído completo). Balance: `src/shared/OilConfig.luau` (`OilConfig`). Orquestador: `src/server/MatchLoop.server.luau` (`MatchLoop`).
> Todas las referencias `Lxx` son líneas reales del archivo actual de `OilCombat.luau`, salvo que se prefije con otro archivo.

## 1. Propósito + API pública

Núcleo servidor de la lucha en aceite: monta el combate, ejecuta rondas de ring-out por puntos (`PointsToWin = 3`), resuelve golpes/bloqueo/parry/esquiva/agarre, publica estado como atributos y emite eventos a los HUD.

| API | Línea | Qué hace | Quién la llama |
|---|---|---|---|
| `runMatch(defs)` | L1486 | **Bloqueante**: envuelve `runMatchBody` en `pcall` y garantiza la limpieza (bug #1, ver sección 6). Devuelve `{name, player, reason}` o `nil` | `MatchLoop` L123 (solo/IA) y L174 (multi), dentro de `task.spawn`+`pcall` (MatchLoop L208-217) |
| `runMatchBody(defs)` | L1328 | Cuerpo real del combate: arma el match, prepara luchadores, corre rondas hasta 3 puntos o abandono. **Local, no exportada**: puede lanzar errores y quien limpia es `runMatch` | `OilCombat.runMatch` |
| `perform(e, action, aim)` | L845 | Valida y ejecuta una acción (`push/charge/grab/dodge/block/unblock`) | Handler de `OilAction` L967 (cliente) e IA `aiThink` L1100, L1104, L1107, L1116, L1119, L1122 |
| `releaseHold(grabber, victim)` | L437 | Suelta un agarre (limpia `holding`/`heldBy` y los atributos `Held`) | **Local** (declarada adelantada L388, no exportada): `dropHolds` L453/L458, `doGrab` L815 |
| `stopBlock(e, withCooldown)` | L463 | Baja la guardia; opcionalmente arranca `cd.block` (0.55s) | **Local** (L389): L393, L501, L609, L649, L835, L860, L914, L989, L1015, L1256 |
| `resign(player)` | L1431 | Saca al jugador del match (`dropHolds`, `forfeited`, remove, `releaseFighter`, evento `forfeit`) | `MatchLoop` L245 (ReturnToMenu) y L260 (OilResign); `PlayerRemoving` del propio módulo L1466 |
| `abort()` | L1454 | Pone `match.active = false` (corta la ronda en curso) | **Sin llamantes en el repo** (API muerta) |
| `isRunning()` | L1460 | `match ~= nil` | `MatchLoop` L102 (`waitForMatchEnd`) |

Carga del módulo: remotes `OilAction`/`OilEvent`/`OilKnock` (L51-53, creados con `ensureRemote` L41-49) y 3 conexiones permanentes: handler `OilAction` L938, `RunService.Heartbeat` L1024 y `Players.PlayerRemoving` L1465.

## 2. Flujo de `runMatch` (L1291-1427)

1. **Guard**: si ya hay `match` → `nil` (L1292-1294).
2. **Setup de fighters** (L1296-1309): crea entradas `{kind, player, model, name, score, aiNext}` + `resetCombatState` (L177); descarta las que no tienen personaje válido (`partsOf` L81, L1306).
3. **Validación inicial**: `< 2 fighters` o falta `workspace.OilWrestlingRing.OilArena` (buscado en `OilPhysics.getArena`) → `warn` + `nil` (L1310-1313).
4. `m = {fighters, active=true, fighting=false, round=0}`; **`match = m`** (L1315-1316); copia `participants` para progresión (L1317-1320); `workspace.OilMatchActive = true` (L1321); `prepFighter` por cada uno (L1322-1324).
5. `prepFighter` (L365-386): tag `OilFighter` (L370), `slickify` (L371), brillo `SkinShine` guardando `OilOrigRefl` (L372-377), oculta nombres (L378-379), barra `OilBars` (`makeBar` L235-292), atributo `InOilMatch` (L382) o `startAI` (L384 → L1127: `SetNetworkOwner(nil)` L1137, `OilPhysics.attach` L1139, bucle de IA cada 0.1s L1147-1155).
6. `match_start` con `fighterList()` + `PointsToWin` (L1325).
7. **Bucle de rondas** `while m.active and #m.fighters >= 2` (L1329):
   - `placeFighters()` (L1331 → L1159-1187): reset de estado, `cd_ = 0`, limpia atributos, **`Locked = true`** (L1173), `PivotTo(spawnCFrame)` (L1175; spawn en círculo `SpawnRadius = 13`, L154-161), velocidades a cero, `OilPhysics.reset` (IA) o `knock "reset"` (L1182).
   - `countdown(m)` (L1332 → L1198-1208): 3→2→1 (`countdown`) y `go`; aborta si `#fighters < 2` o `not m.active` (L1202) → `break` (L1333).
   - `lockAll(false)` (L1335 → L1189), `spawnInvulnUntil = now + 2.0` (L1337-1339), **`m.fighting = true`** (L1340).
   - `runRound(m)` (L1341 → L1211-1249): bucle con **`task.wait(0.05)` ≈ 20 Hz** (L1215); rampa de resbalón `OilSlick` desde `SlickRampStart = 18s` hasta `RoundTimeout = 45s` (L1219-1222); por luchador: muerte/desaparición → `dropHolds` + `releaseFighter` + remove + evento `roster` (L1225-1233); `#fighters < 2` → `"abort"` (L1238-1240); ring-out → `"out"` (L1234, L1241-1243); timeout → `"timeout"` (L1244-1246).
   - **Ring-out `isOut(root)` (L146-152)**: en espacio objeto de `OilArena`: `|rel.X| > Size.X/2 + RingMargin(0.4)` **o** `|rel.Z| > Size.Z/2 + 0.4` **o** `rel.Y < -3` (altura).
   - `m.fighting = false` (L1342); si `not m.active` → `break` (L1343-1345); `lockAll(true)` (L1346).
   - **Puntos** `handleOut(m, outList)` (L1348 → L1251-1287): marca `out`, suelta holds/bloqueo (L1253-1257); *scorer* = `lastHit` dentro de `AssistWindow = 6s` y sigue vivo (L1261-1263), en 1v1 fallback al rival (L1264-1265); fx `ringout` (L1270); `score += 1` + `RecordRingout` (L1272-1276) o `noscore` (L1279); espera `PostPointPause = 2.6s` (L1282); **`score >= PointsToWin`** y sigue en el match → ganador (L1283-1285).
   - `"timeout"` → evento `draw` + 2.2s (L1353-1355); cualquier otro → `break` (L1356-1357).
8. **Forfait**: sin ganador y queda 1 fighter → `winner`/`reason = "forfeit"` (L1362-1365).
9. **Recompensas**: `RecordMatchEnd` con `participants` (score, forfeited, vsAI, reason) vía `progress()` con `pcall` (L1368-1385; wrapper L32-39).
10. **Limpieza**: `active/fighting = false` (L1387-1388), atributos workspace `OilMatchActive`/`OilSlick` a `nil` (L1389-1390), `lockAll(true)` + cuenta atrás de 5s de `match_end` (L1392-1400), teleport al spawn (L1402-1411), `match_end` final + fx `victory` (L1413-1416), `VictoryPause = 4.5s` (L1417); sin ganador → `match_end` vacío (L1419); **`releaseFighter` de cada uno** (L1422-1424); **`match = nil`** (L1425); devuelve el resultado (L1426).
    `releaseFighter` (L391-434): `released = true`, `stopBlock`, limpia `InOilMatch`/`cd_*`/`Balance`/`Stamina`/`CounterReady`/`OilState` (L395-403), `knock "reset"` (L404), destruye `OilBars` (L406-409), quita tag + `FIGHTER_ATTRS` (L411-414), `slickify(false)` (L415), restaura reflectance (L416-424), `PlatformStand`/`DisplayDistance` (L425-429), `OilPhysics.detach` solo IA (L430-432).

## 3. Máquina de estados del luchador

- **Campos por luchador** (`resetCombatState` L177-201): `out, lastHit, stunUntil, invulnUntil, spawnInvulnUntil, dazedUntil, pushedUntil, brokenUntil, counterUntil, dodgeUntil, dodgeIFramesUntil, dodgeFxFor, holding, heldBy, holdToken, blocking, blockStart, balance, balanceHitAt, stamina, staminaSpentAt, cd{}, state`.
- **Estado derivado** `computeState` (L203-232), prioridad exacta: `invulnerable` (L204) > `grabbed` (L207) > `grabbing` (L210) > `knocked` (L213) > `stunned` (L216) > `dodging` (L219) > `blocking` (L222) > `offbalance` (L225) > `pushed` (L228) > `idle`.
- **Publicación** `publish` (L320-360): en el *character* `State`, `Blocking`, `Dazed`, `Balance` (L327-341); en el `Player` `Balance`, `Stamina`, `CounterReady`, `OilState` (L342-358); barra de equilibrio (`updateBar` L294-317, "¡DESEQUILIBRADO!" L306-310). 10 Hz desde `tickMatch` (L974-1021, gatillado en L1024-1036).
- **Atributos de control** (`FIGHTER_ATTRS` L60): `Locked` → `placeFighters`/`lockAll` (L1173, L1189-1196); `Held` → `setHeld` en agarre (L802-803) y `releaseHold` (L440, L444); `Charging` → `doCharge` (L729, L750); `Act`/`ActT` → `setAct` (L99-102) desde `startBlock` L495, `daze` L504, `resolveHit` L655, `doPush` L700, `doCharge` L728, `doGrab` L766/L805/L819, `doDodge` L836, counter L885.
- **Transiciones clave**: `blocking` se levanta en `startBlock` (L473-496: cd, attrs `Locked/Held/Charging/holding`, stun/daze, `MinStamina = 6`) y cae en `tickMatch` si `heldBy`/stun/daze/`Locked` (L1014-1016) o si la stamina llega a 0 → **guard-break** (L985-997, dura `GuardBreakDaze = 1.3`). **Parry**: dentro de `Parry.Window = 0.22s` y de frente (`frontalTo` L530-538, arco `Block.Arc = 0.1`) → `doParry` (L545-568): `counterUntil` +1.6s (L551), invuln 0.35 (L552), +20 stamina (L553), aturde al atacante (L555-556) y daña su equilibrio (L558). **Desequilibrio**: `applyBalanceDamage` (L509-527) a 0 → `brokenUntil` (L517); el golpe siguiente multiplica fuerza ×2.8 y derriba (`resolveHit` L631-639). **Derribo**: `stun > 0` → `stunUntil` + `invulnUntil` (L652-655, `InvulnAfterStun = 0.7`).

## 4. `perform()` acción por acción (L845-933)

Validaciones de entrada: `match.fighting` (L846), vivo y no `out` (L849-852); `aim` → `flat()` y si su magnitud `< 0.1` usa la mirada (L871-876, esquiva sin dirección = hacia atrás L873-875); attrs `Locked/Held/Charging/holding` (L895-897); stun/daze (L898-900); cooldown (L903-906, el counter lo salta); stamina (L907-911); baja guardia (L914), cancela invuln de aparición (L915-917), cobra stamina (L918), consume counter (L919-921) y arranca cd (L922).

- **`block`** (L855-858) → `startBlock`: cuesta `BlockStart = 6` de stamina, cd `0.55s`.
- **`unblock`** (L859-862) → `stopBlock(true)` (cd 0.55).
- **`push`**: cd 0.9s, 14 stamina, windup 0.12s (`task.delay` L701-722, cancelable si te aturdieron, `canKeepActing` L692-695); cono `Range 7.5 / Cone 0.25` (`targetsInCone` L668-690); fuerza `24 + 0.6·velocidad propia` (L707-708); con counter ×1.7 de fuerza y ×1.5 de daño (L710-713); solo el primer objetivo conectado (L718-720).
- **`charge`**: cd 4.5s, 30 stamina, `Charging` + impulso 34 (L728-730); dura 0.65s y la lleva `tickCharges()` desde el Heartbeat del módulo (`activeCharges`, L692-737): primera comprobación de impacto a los 30ms (como el antiguo bucle), luego una por frame; cono `HitRange 5.2`, `blockCostMult = 2`; al salir rebote/penalización (`finishCharge`).
- **`grab`**: cd 6s, 22 stamina, windup 0.1s (L767-827); valida objetivo en cono `5.8/0.2` (L773-774), i-frames → whiff + daze (L780-788), invuln/ya agarrado → fallo (L789-792), **parry del rival → `doParry`** (L793-795), bloqueo roto (L797-798); agarre con **`holdToken`** (L808-813) y lanzamiento *unblockable* a los 0.75s (L810-826).
- **`dodge`**: cd 1.3s, 20 stamina, `dodgeUntil` 0.4s / i-frames 0.3s / impulso 30 (L837-839); no consume la invuln de aparición (L915-917).
- **Contraataque estando agarrado** (L879-893): `push`/`charge` con `heldBy` → `dropHolds` + golpe *unblockable* (fuerza `CounterForce = 34`, stun 1.0) contra el agarrador y +0.5s de invuln; **sale antes de cobrar cd/stamina** (return L892).
- **Contraataque de parry** (L903-921): `push` dentro de `counterUntil` → gratis y sin comprobar cd, pero sí aplica `startCooldown` después (L922).
- **Handler blindado de `actionRemote`** (L935-971): whitelist `block/unblock/ACTIONS` (L942-944), throttle por jugador+acción **0.08s acciones / 0.02s block·unblock** con tabla weak `actionAt` (L937, L945-953), `aim` debe ser Vector3 **finito** (NaN/inf → `nil`, L954-964), y el jugador debe estar en `match.fighters` (L965-970).

## 5. Puntos, rondas y eventos

`OilEvent` (server→todos): `match_start` L1325 · `countdown` L1200 · `go` L1206 · `roster` L1233 · `point` L1277 · `noscore` L1279 · `draw` L1354 · `forfeit` L1450 · `match_end` L1398/L1413/L1419 · `fx` L119-121 (rafagas). `notice` va solo al jugador (L124-128: nostamina, broken, parry, guardbreak…). `OilKnock`: `knock` L172 (impulso aplicado **por el cliente**) y `reset` L404/L1182.
Consumidores: **OilRoundsHUD** L533-674 (marcador/splash de countdown, go, point, noscore, draw, roster, forfeit, match_end; anti-estados viejos con `matchToken` L546/L633/L668); **OilCombatHUD** L336-340 solo `notice` + lee atributos `Balance/Stamina/OilState` en `RenderStepped` L376+; **OilFighterClient** `fx` L437-442 y `knock` L384.

## 6. Bugs y puntos débiles

| # | Línea(s) | Problema | Sev. | Arreglo (1 línea) |
|---|---|---|---|---|
| 1 | ~~L1316 / L1425~~ | `match` solo se limpiaba al final de `runMatch` | **alta** | **ARREGADO 2026-10-07**: el cuerpo pasó a `runMatchBody` y `OilCombat.runMatch` lo envuelve en `pcall` + `forceCleanup()` (pone `match = nil`, `active/fighting = false`, limpia `OilMatchActive`/`OilSlick` y hace `releaseFighter` de cada uno). Verificado inyectando un error real en `prepFighter`: 0 huérfanos y un combate posterior arranca normal |
| 2 | ~~L735~~ | `doCharge` hacía **busy-wait `task.wait(0.03)`** dentro de `task.spawn` | media | **ARREGADO 2026-10-07**: las embestidas viven en la tabla `activeCharges` y las mueve `tickCharges()`, llamado desde el `Heartbeat` del módulo (una comprobación de impacto por frame, cero despertares extra). Mantiene el retardo de 30ms del primer impacto, así que el balance no cambia |
| 3 | L1024 | Conexión `RunService.Heartbeat` de módulo **nunca se desconecta**: `OilPhysics.step` corre siempre y `tickMatch` se auto-bloquea (L976-978) solo al final; igual las conexiones singleton L938 y L1465 (estas dos sí son intencionales) | baja | Guardar la conexión en un upvalue y `Disconnect()` cuando `match == nil` (o aceptarla como coste fijo y anotarlo) |
| 4 | ~~L391~~ | `releaseFighter` no llamaba `dropHolds(e)` | media | **ARREGADO 2026-10-07**: `releaseFighter` empieza con `dropHolds(e)`. Ningún agarre sobrevive al fin del combate, así que el `task.delay` del lanzamiento ya no puede dispararse después |
| 5 | ~~L701, L731, L767, L810~~ | Callbacks pospuestos leían el global `match` y una `e` de otra generación | media | **ARREGADO 2026-10-07**: cada entrada guarda `e.match = m` al crearse; helper `sameMatch(e, m)` (L708) que exige combate no nulo, `match == m`, `e.match == m` y `not e.released`. Aplicado en: windup de `doPush`, windup y lanzamiento de `doGrab`, `tickCharges`, bucle de IA de `startAI` y `canKeepActing(e, m)` |
| 6 | ~~MatchLoop L127~~ | Carrera con el token `session`: el task viejo podía destruir la IA de la pelea nueva | media | **ARREGADO 2026-10-07**: `clearAIFighters(model)` destruye solo el modelo que creó ese task (`clearAIFighters(ai)`), y `runSoloFight` re-comprueba `mySession == session` justo antes de `spawnAI()` |
| 7 | ~~L1147~~ | Bucle de IA seguía con el global `match` | baja | **ARREGADO 2026-10-07** junto al #5: `while sameMatch(e, m) and match.active` |
| 8 | L371 / L415 | `slickify(char, false)` pone `CustomPhysicalProperties = nil` sin guardar los originales → se pierden las propiedades físicas previas del personaje (a diferencia de `OilOrigRefl`, L373-376) | baja | Guardar/ restaurar el valor previo en un atributo antes de sobrescribir |
| 9 | L1454 | `OilCombat.abort()` **no tiene ningún llamante** en el repo: superficie muerta | baja | Borrarla o llamarla desde `MatchLoop` al cancelar sesión |
| 10 | L902 vs L922 | Comentario "gratis y sin cooldown" del counter: realmente elige el cd de la acción igualmente (solo salta la comprobación L904) | baja | Corregir el comentario (o no arrancar cd si `isCounter`) |

No hay literales `TODO`/`FIXME`/`HACK` en el archivo; la deuda explícita vive en `MEMORY.md` L84-92. **Crecimiento/fugas**: las tablas están acotadas (`actionAt` es weak-key L937; `participants` L1317 se libera al acabar) y los únicos `Instance.new` del módulo son los 3 remotes (L44) y la barra `OilBars` (L244-289, destruida en L406-409); **no crea BodyMovers/Attachments** — los impulsos son velocidades directas (`OilPhysics.knock` L145-175) y `states` de `OilPhysics` se autocurra (OilPhysics L83-87, L317-318). El riesgo de fuga real es indirecto: el camino del bug #1 deja todo lo anterior sin liberar.

## 7. Seguridad

**Superficie entrante tras el blindaje**: desde `OilCombat` solo `OilAction` (L938) — whitelist de acciones (L942-944), throttle 0.08s/0.02s con tabla weak (L945-953), `aim` Vector3 finito (L954-964) y pertenencia a `match.fighters` (L965-970); `perform` revalida estado (`match.fighting` L846, vida/`out` L849-852, attrs L895, stun/daze L898, cd L904, stamina L907). `OilEvent`/`OilKnock` solo salen. El resto de entradas (`StartGame`, `OilResign`, `ReturnToMenu`) viven en `MatchLoop` (whitelist L194, throttle 1s L241/L256). El cooldown real lo pone el servidor (L922), no el cliente.

**Puede quedar pendiente**:
- **`aim` sin clamp direccional** (L871-876): el cliente dicta el cono de golpe completo (giro instantáneo 180°); el servidor solo exige magnitud ≥ 0.1 y normaliza (`unitOr` L876). *Sugerencia: limitar `dir` al cono del `LookVector`/`MoveDirection` reportado por el servidor.*
- **Ring-out y knock basados en el cliente**: `isOut` (L146-152) lee la posición del `HumanoidRootPart` que el cliente posee, y el impulso a jugadores viaja por `OilKnock` para que el propio cliente lo aplique (L163-174) → teleports/ignorar derribos. *Sugerencia: validar desplazamiento máximo por tick en servidor antes de puntuar.*
- Distancia/objetivo entre luchadores **sí** se valida en servidor (`targetsInCone` L668-690: rango + cono), pero no hay coste por paquetes recortados por el throttle (documentado en `MEMORY.md` L81) y `ensureRemote` (L41-49) puede crear remotes duplicados si dos módulos arrancan a la vez.
