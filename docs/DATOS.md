# Contrato de datos del jugador

Los datos de progresión son lo más caro que tiene este juego: si `Reconcile` se equivoca,
un jugador pierde XP, monedas o misiones, y **no hay copia local de la que volver**. Un
error de interfaz se arregla en un minuto; uno de datos, no.

Por eso los datos tienen su propio documento y sus propias reglas.

## Dónde vive

| Pieza | Archivo | Qué hace |
|---|---|---|
| Defaults | `ProgressionLogic.DefaultData()` | La forma de un jugador nuevo |
| Saneado y migración | `ProgressionLogic.Reconcile(data)` | Convierte lo que llega de DataStore en algo válido |
| Reglas puras | `ProgressionLogic` (resto) | XP, monedas, misiones, rachas |
| Transporte | `ProgressionService` | Carga, guarda, reintenta, manda el snapshot |
| Contrato con el cliente | `ProgressionShared` + `Logic.Snapshot(d)` | Lo que el cliente ve |

## Regla 1: nunca se confía lo que viene de DataStore

`Reconcile` se ejecuta **siempre** al cargar, antes de usar nada. Por eso todo lo que se
añada a los datos tiene que pasar por ahí. La regla que ya se aplica a los contadores:

```lua
local n = data.stats[k]
if type(n) ~= "number" then
    data.stats[k] = v          -- vuelve al valor por defecto
else
    data.stats[k] = math.max(0, math.floor(n))
end
```

Ni negativos, ni decimales, ni `nil` que reviente a 200 líneas de distancia.

## Regla 2: añadir un campo son **cuatro** toques, no uno

Añadir `skins` al jugador obliga a tocar estos cuatro sitios. Si se olvida uno, el campo
aparece a medio hacer y el fallo aparece días después, en el juego de otro.

| # | Dónde | Qué |
|---|---|---|
| 1 | `DefaultData()` | El valor por defecto del jugador nuevo |
| 2 | `Reconcile()` | Qué hacer con un jugador que **no** tiene el campo (y con uno que lo tiene corrupto) |
| 3 | `Snapshot(d)` | Solo si el cliente lo necesita. **Lo que no esté aquí, el cliente no lo ve** |
| 4 | `ProgressionLogic_Test.luau` | Un test que cubra el caso "jugador viejo sin el campo" |

El punto 4 no es opcional: es el que atrapa el olvido del punto 2.

## Regla 3: toda forma nueva sube la versión del esquema

`data.schema` es un número. Ya hay una migración real de la v1 y la v2 a la v3 (los
contadores `m_*` pasaron a `mp`).

```lua
-- dentro de Reconcile, antes de escribir schema
if (oldSchema or 0) < 4 then
    -- los jugadores que aun siguen en v3 no tienen este campo: se les da el default
    data.skins = data.skins or {}
end
data.schema = 4
```

Reglas al migrar:

- **Una versión por cambio incompatible**, no uno por commit. Migrar a 4, 5, 6...
- **El default es mejor que un error.** Un jugador al que le falte un campo debe jugar
  igual, no Romper.
- **No se borra un campo viejo en la misma versión que se añade el nuevo.** Primero se
  rellena el nuevo, y el viejo se limpia una versión después, cuando sepas que todo el
  mundo ha pasado por ahí.
- La migración se escribe en `Reconcile`, que ya se ejecuta en cada carga: no hace falta
  ningún proceso aparte para los que ya han entrado.

## Regla 4: el servidor es la única fuente de la verdad

Las monedas, el XP y las compras se calculan **siempre en el servidor**. El cliente pinta,
nunca decide.

Cuando llegue la tienda (o las cajas), esto significa: el botón del cliente pide, el
servidor comprueba precio y catálogo, el servidor descuenta y el servidor responde. Un
precio en el cliente es una invitación a regalar objetos.

Además: `CONFIG.MaxCoins` es un techo (`Reconcile` lo aplica). Cualquier sistema de
monedas necesita un techo, o un bug de guardado puede producir un `1e308`.

## Regla 5: guardar es caro y puede fallar

`ProgressionService` guarda con reintentos y avisa con `unsaved`. Consequences prácticas:

- Los datos se guardan **al sair** y en momentos críticos, no en cada frame.
- Si `unsaved` está activo, la interfaz lo avisa al jugador. **No quitar ese aviso**: es
  la diferencia entre "perdía la partida" y "sabía que podía perderla".
- Un cambio en el formato de datos **obliga** a revisar el guardado, no solo la carga.

## Checklist para añadir un campo

- [ ] `DefaultData()` con su default
- [ ] `Reconcile()` con el caso "no existe" y el caso "está corrupto"
- [ ] `data.schema` subido, con la migración de los que no lo tienen
- [ ] `Snapshot()` si el cliente lo necesita
- [ ] Test en `ProgressionLogic_Test.luau` para el jugador viejo
- [ ] 46/46 tests en verde
- [ ] Probado con un jugador que tenga datos de antes (no solo uno nuevo)
