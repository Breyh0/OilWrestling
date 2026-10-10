# Preflight de Luau

No hay compilador de Luau en la máquina, así que un `.luau` con un error de sintaxis se
sincroniza a Studio sin decir absolutamente nada: Rojo lo acepta, el script no compila y
el juego se queda sin esa función **sin ningún error visible**. La única señal llega a
la consola del playtest, y solo si alguien mira.

`tools/lua_preflight.py` cubre ese hueco. No sustituye al playtest: cubre los fallos que
el playtest solo te enseña si ya sabes que mirar.

```powershell
python tools\lua_preflight.py src              # toda la carpeta
python tools\lua_preflight.py src\client\X.luau   # un archivo
```

Sale con código 1 si encuentra algo, así que sirve como puerta en un script.

## Las cinco reglas

| Regla | Qué caza | Por qué importa |
|---|---|---|
| `reservada` | Palabra reservada usada como nombre: `{ until = 0 }`, `{ end = 1 }` | El script entero no compila. Sin efecto, sin error. |
| `adelantada` | Un `local` usado antes de su declaración, **como valor o como llamada** | Leerlo devuelve `nil` **en silencio**; llamarlo da `attempt to call a nil value`. |
| `corchetes` | Cierre sin apertura, o apertura que nunca cierra, en `()` `{}` `[]` | Corta el archivo en el sitio exacto. |
| `bloques` | `function`/`if`/`for`/`while`/`do` sin su `end` | Igual que arriba, pero contado como bloque. |
| `huerfana` | `Instance.new()` usado como hijo y **nunca** con `.Parent` | Sin `Parent` la instancia está fuera del DataModel: no suena, no se lista, no falla. |
| `alfabeto` | Ideogramas, cirílico, japones | Compilan igual. No se ven en el diff ni en la consola. |

## De dónde sale cada regla

Ninguna es teórica. Todas nacieron de bugs reales de este proyecto:

- **`reservada`** — `lane = { prio = 0, until = 0 }` en `SoundDirector` (2026-10-10). El
  director de sonido entero dejó de cargar: no sonaba nada y Rojo no dijo nada. Lo
  destapó la consola del playtest.
- **`adelantada`** — dos veces el mismo día. `pushMusic` llamaba a `fadeTo` declarado más
  abajo (`attempt to call a nil value` en cuanto se cambiaba de pista), y
  `maxSeconds = VICTORY_MAX` con `VICTORY_MAX` declarado más abajo, que valía `nil` en
  silencio y por lo tanto el tope de la fanfarria no se aplicaba nunca.
- **`huerfana`** — el clon 3D de los sonidos colgaba de un `Attachment` al que nunca se
  le puso `.Parent`. Los sonidos con posición no sonaban, no aparecían en ningún
  `GetDescendants()` y no daban ningún error.
- **`alfabeto`** — se colaron ideogramas en comentarios tres veces en una sesión. Compilan
  igual.

## Autotests

Una regla que nunca salta no vale nada, y ya hubo una que no detectaba nada por un typo
(`Instance%.new` en vez de `Instance\.new`). **Cada regla tiene su autotest**: un archivo
mínimo con el fallo plantado, en `tools/preflight_tests/`, y un runner que lo comprueba:

```powershell
python tools\preflight_selftest.py
```

```
== autotests: cada regla debe detectar su fallo ==
  OK    reservada.luau         [reservada]x2
  OK    adelantada.luau        [adelantada]x2
  OK    corchetes.luau         [corchetes]x1 [bloques]x1
  OK    huerfana.luau          [huerfana]x1
  OK    alfabeto.luau          [alfabeto]x1

== el codigo real debe salir limpio ==
  OK    src docs .opencode: archivos: 31 | problemas: 0
```

El runner hace las dos mitades: que cada regla **detecte** su fallo, y que el código real
no llore de más. Si añades una regla, añade su archivo y su entrada en `ESPERADO`.

Los archivos de prueba **no se arreglan**: tienen el fallo a propósito, y la cabecera de
cada uno lo dice.

## Cobertura también de la documentación

`lua_preflight.py` acepta carpetas y revisa los `.md` que encuentra (docs y skills). En
un `.md` solo tiene sentido la regla de alfabeto: las demás describen código que no está
en el archivo. Por eso el comando de la puerta es:

```powershell
python tools\lua_preflight.py src docs .opencode
```


## Falsos positivos conocidos

La regla `huerfana` y la `adelantada` se ajustaron para no llorar con el código normal:

- Un `NumberValue` suelto que se tweeniza y se destruye a mano **no** se cuelga de nada:
  es legal.
- Un nombre que además se usa como variable de bucle (`for k, v in pairs(t)`) es otro
  local, no el mismo.
- Las claves de tabla (`cooldown = 0.18`) no son usos del local `cooldown`.
- Las declaraciones múltiples (`local a, b = x, y`) declaran las dos.
- Los parámetros de función ocultan a los locals del mismo nombre.

## Cuando salte algo

1. **No comentes la línea.** Arregla el orden o el nombre.
2. Si es un falso positivo real y no se puede evitar, no lo silencies con `-- preflight:
   ignore`: el próximo que lea el preflight se cree que la regla no funciona.
3. Si la regla tiene un hueco, se arregla la regla (y su autotest), no el aviso.
