# Método de trabajo — Lucha de aceite

Este es el procedimiento del equipo. Está aquí para que cualquier persona (o IA) que toca
el proyecto sepa exactamente qué hacer, en qué orden, y qué le da derecho a decir
"hecho".

**Regla que lo resume todo: `main` es la versión que funciona.** Todo lo demás vive en una
rama hasta que se ha probado de verdad. Si `main` está verde, se puede volver a ella
siempre.

---

## 1. Las tres capas y quién manda en cada una

| Capa | Dónde vive | Cómo se versiona |
|---|---|---|
| **Código** | `src/**.luau` | git (`git push`) |
| **Escena y GUI** | Workspace, `StarterGui` | dentro del place (Ctrl+S / publicar) |
| **Recursos** | `SoundService`, assets | dentro del place |

Dos consecuencias que se pagan caras si se olvidan:

- Una escena nueva **no está a salvo** hasta que se publica el place. git no la guarda.
- Un cambio en `src/` **pisa** lo que alguien haya escrito a mano en el editor de Studio.
  Por eso el código nunca se escribe en Studio.

---

## 2. Ciclo de trabajo de una tarea

```
1. git pull                             # trae lo del otro
2. git checkout -b feature/<nombre>     # una rama por tema
3. rojo serve + Connect                 # sincroniza git -> juego
4. trabajar                             # código en src/, escena en Studio
5. python tools\lua_preflight.py src    # puerta obligatoria
6. tests unitarios (46)                 # en playtest, ver sección 5
7. playtest + 0 errores de consola
8. commit + push de la rama
9. code review de la rama                # ver sección 6
10. merge a main con el visto bueno del usuario
```

La rama se llama `feature/<que-hace>`, en minúsculas y con guiones: `feature/sonidos`,
`feature/tienda-cajas`, `feature/hitbox`.

**Una rama = un tema.** No se mezcla un arreglo de sonido con una tienda nueva: si la
tienda se rompe, la rama del sonido sigue viva y se puede mergear sola.

---

## 3. La puerta: preflight

Antes de cualquier commit o sincronización:

```powershell
python tools\lua_preflight.py src docs .opencode
```

Sale con código 1 si hay problemas. **No hay compilador de Luau en la máquina**, así que
esta herramienta es lo que sustituye al playtest para los fallos que no dejan error
visible. Caza seis clases de fallo:

| Regla | Qué caza |
|---|---|
| `reservada` | Palabra reservada usada como nombre (`until = 0`). El script entero no compila: no hace nada y Rojo no dice nada. |
| `adelantada` | Usar un `local` declarado más abajo. Al llamarlo da `nil` en runtime; al leerlo da `nil` **en silencio**. |
| `corchetes`, `bloques` | Llaves, paréntesis o bloques sin cerrar. |
| `huerfana` | `Instance.new()` usado como hijo y sin `.Parent`: no suena, no aparece en ningún `GetDescendants()` y no da error. |
| `alfabeto` | Ideogramas o cirílico colados: compilan igual y no se ven ni en el diff. |

`adelantada` y `huerfana` no nacieron de la teoría: nacieron de bugs reales de este
proyecto el 2026-10-10, y por eso cada regla tiene su autotest.

Para comprobar que las reglas siguen funcionando:

```powershell
python tools\preflight_selftest.py
```

---

## 4. Verificar antes de decir "hecho"

```
1. execute_luau (Edit)  -> comprobar el estado por medios programáticos
2. start_stop_play      -> jugar de verdad
3. get_console_output   -> 0 errores
```

Criterio de aceptación, en este orden:

1. Preflight con 0 problemas.
2. **46/46 tests unitarios** en verde.
3. **0 errores de consola** en playtest.
4. La observación concreta que se buscaba, con números.
5. Confirmación del usuario de lo que una máquina no puede medir.

El punto 5 no es opcional. Hay cosas que no se pueden verificar con código: cómo suena
una fanfarria, si un botón está bien colocado. Se dice explícitamente **qué se verificó y
qué queda pendiente**. Un informe que exagera la cobertura hace que el otro deje de
fiarse, que es peor que no informar.

---

## 5. Tests unitarios

Con el juego en marcha, en el contexto Server:

```lua
local mod = game:GetService("ServerScriptService")
    :WaitForChild("UnitTest"):WaitForChild("RunUnitTest")
local totales = require(mod)()   -- devuelve { run, passed, failed }
```

El módulo **devuelve una función**, no una tabla con `.run`. Detalle que costó una
llamada perdida.

Cubren `ProgressionLogic` entero: XP, monedas, misiones, rachas, saneado de datos.
Cuando se toca progresión, los tests se amplían **en el mismo commit** del cambio, no
después.

---

## 6. Code review de una rama

Se revisa **la rama contra `main`**, no el repo entero:

```powershell
git diff main...feature/<nombre> --stat
git diff main...feature/<nombre>
```

Los cinco puntos donde de verdad se rompen cosas en este proyecto:

- [ ] ¿Toca `OilCombat`, `OilPhysics` u `OilConfig`? Es el núcleo: mirarlo el doble.
- [ ] ¿Añade `require` de algo que no existe? Rompe el arranque del juego.
- [ ] ¿Trae un remoto nuevo? Tiene que estar en `src/shared/` como `.model.json`.
- [ ] ¿Deja números mágicos? El balance va en `OilConfig`, nunca repartido.
- [ ] ¿Borró código? Un `require` hacia algo eliminado deja el script calling a nil.

---

## 7. Ramas: reglas

- `main` nunca recibe código sin pasar el ciclo entero de la sección 2.
- Los merges van con `--no-ff`, para que queden registrados.
- Una rama que lleva mucho tiempo sin probarse se borra: una rama vieja es ruido que
  hace dudar de cuál es la buena.
- Nunca se edita en `main`. Si se ha hecho, se puede recuperar, pero se ha gastado la red.
- Los cambios de **escena** (ring, GUI) no los protege ninguna rama: se publica el place
  y se anota en `MEMORY.md` que hay cambios de escena sin commit.

### La puerta automática

Hay una CI en `.github/workflows/quality.yml` que corre en cada push y en cada PR a
`main`, y ejecuta el preflight y sus autotests. Corre desde el 2026-10-10.

Lo que comprueba: preflight de código, docs y skills · autotests de las propias reglas ·
que no haya binarios versionados · que el manifiesto de escena no se haya editado a mano.

Lo que **no** puede: **no juega.** Los 46 tests de Luau necesitan Roblox, así que siguen
siendo manuales. Tampoco comprueba cómo suena ni cómo se ve nada. Es una red, no una
garantía.

Además, `main` está **protegido con un ruleset** en GitHub: los status checks son
obligatorios, la bypass list está vacía (nadie se los salta, ni siquiera el dueño) y la
rama no se puede borrar. En la práctica, **`main` ya no se actualiza con `git push`
directo**: hay que ir por pull request.

```sh
git checkout main && git pull
git checkout -b feature/<nombre>
# ... trabajar ...
git push -u origin feature/<nombre>
# Al subir la rama, GitHub ofrece abrir el PR. Se revisa y se mergea.
```

Si un push directo a `main` sale rechazado con un error de *required status checks* o de
*changes must be made through a pull request*, **no es un fallo**: la regla está
funcionando.

### Publicar una versión

1. Rama verificada → merge a `main` con `--no-ff`.
2. **Publicar el place** en Studio. Sin esto, la escena no existe para nadie más.
3. `git tag -a v0.5.0 -m "..." && git push --tags`
4. Una línea en `CHANGELOG.md`, escrita desde el punto de vista de quien juega.

---

## 8. Cuándo algo sale mal

**Un bug no se arregla en `main`.** Rama de arreglo, se arregla, se verifica, se mergea.
Aunque sea un carácter: `main` es la red.

| Síntoma | Dónde mirar primero |
|---|---|
| Un sonido no suena | `SoundDirector`: ¿están mapeados todos los tipos de `fx` que emite `OilCombat`? |
| Un sonido sale en 2D, no posicional | ¿El `Attachment` tiene `.Parent`? Sin él no suena (regla `huerfana`) |
| Se oyen dos sonidos a la vez | La pista de prioridad de `SoundDirector`: `hold` y `cooldown` |
| Un sonido se repite | ¿El servidor manda el evento varias veces? Cercojo por combate |
| La carga se queda en 0% | ¿Timeouts en `WaitForChild`? Regla dura de `MEMORY.md` |
| Error al arrancar | ¿Algún `require` a un módulo que no existe? |
| Rojo no sincroniza un archivo | Gotcha "Kicked from Live Scripting Session" en `MEMORY.md` |
| `screen_capture` no refleja el cambio | Frames caché: la verificación real es el playtest |

---

## 9. Documentación que hay que mantener

| Documento | Qué guarda | Cuándo se toca |
|---|---|---|
| `docs/MEMORY.md` | **Fuente de verdad.** Gotchas, estado, reglas del equipo | En cada merge |
| `docs/WORKFLOW.md` | Este documento | Cuando cambia el método |
| `docs/DATOS.md` | Contrato de los datos del jugador (4 toques, esquema, migraciones) | Cuando se toca la progresión |
| `docs/OILCOMBAT.md` | Mapa técnico del combate | Cuando se toca el núcleo |
| `docs/PREFLIGHT.md` | Reglas del preflight y sus autotests | Cuando se añade una regla |
| `CHANGELOG.md` | Qué se publica en cada versión | Al publicar |
| `checkpoint/` | Trabajo a medias rescatado del place | Cuando hay trabajo sin versionar |

`MEMORY.md` es lo primero que lee cualquiera que llegue. Si un bug no está anotado ahí,
el siguiente que lo pierda pierde una tarde.

---

## 10. La lista corta

Si solo te lees una cosa, esta:

1. Nunca escribas código en el editor de Studio.
2. Nunca trabajes en `main`.
3. `python tools\lua_preflight.py src` antes de commitear.
4. 46/46 tests antes de mergear.
5. Un cambio de escena sin publicar el place **no existe**.
