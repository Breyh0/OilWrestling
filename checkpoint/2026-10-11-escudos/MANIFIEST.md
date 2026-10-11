# Checkpoint de escudos y cosmeticos — 2026-10-11

Rescate del trabajo de `supergamertth8` sobre **escudos, cajas y cosmeticos**, que vivia
solo dentro del lugar (en `ServerStorage`) y **no estaba en git**. Se creo esta carpeta
porque hasta ahora no se habia podido extraer: el MCP se colgaba en cuanto intentaba
leer `ShieldAbilities`.

> Esta carpeta **no la lee Rojo** (ver `../2026-10-10-estado-del-lugar/MANIFIEST.md`).
> Es archivo muerto a proposito: son copias de referencia, no codigo vivo.

---

## 1. Que se ha rescatado y verificado

| Archivo | FNV | Bytes | Estado |
|---|---|---|---|
| `ServerStorage.Respaldo_Habilidades_Escudos/ShieldAbilities_original.luau` | `3684004711` | 9489 | **RESCATADO y verificado byte a byte** |
| `ServerStorage.Respaldo_Habilidades_Escudos/ShieldAbilities_Test_original.luau` | `2089202569` | 5284 | **RESCATADO y verificado byte a byte** |

Es lo que faltaba. Todas las copias se comprueban con:

```powershell
python tools\verificar_rescate.py checkpoint\2026-10-11-escudos
```

Un **hash que no coincide significa que la copia no sirve**, aunque compile y aunque se
lea bien. Por eso la verificacion es automatica y no una mirada.

### Las codificaciones estan mezcladas

| Archivo | Codificacion | Como se nota |
|---|---|---|
| `ShieldAbilities_original` | **Latin-1** | la `i` acentuada de "Guia" es un byte `0xED` |
| `ShieldAbilities_Test_original` | **UTF-8** | la `a` acentuada de "mas" son dos bytes `0xC3 0xA1` |

Asi que **no se puede asumir nada**: hay que mirar cada archivo. Por eso la verificacion
es por hash y no por "tiene los mismos bytes".

## 2. Que queda por rescatar

Mismo origen, mismo riesgo. Cuando se_extraigan, la lista de arriba va creciendo:

| Archivo en el lugar | FNV | Bytes | Notas |
|---|---|---|---|
| `Respaldo_Tienda_Cajas.OilBlockVFX_original` | `3743230225` | 19140 | el aspecto del escudo en pantalla |
| `Respaldo_Tienda_Cajas.OilCombat_original` | `1511816891` | 50433 | OilCombat con ganchos `cosmetic*` |
| `Respaldo_Tienda_Cajas.CosmeticsShared_original` | `825101627` | 3331 | ya rescatado en el checkpoint del 2026-10-10, sin escudos |

`OilCombat_original` es el menos urgente: el `src/server/OilCombat.luau` vivo ya tiene el
bloqueo completo. Del backup interesan los ganchos `cosmetic*`, no el archivo entero.

---

## 2bis. Un valor del test esta desfasado (y se demuestra por que)

El test, linea 139, espera esto:

```lua
p:SetAttribute("CosShield", "escudo_tormenta")
expect.equal(A.ForPlayer(p).reflectBalance, 8)
```

Pero el modulo rescatado tiene **`reflectBalance = 6`** para ese escudo. **El test falla
asi como esta.** Y no es un error de copia: con los numeros del `OilConfig` actual, 6 es
el valor que cabe y 8 no.

Calculando `A.Strength` con el balance de `src/shared/OilConfig.luau`
(`Parry.Window = 0.22`, `Stamina.Max = 100`, `Balance.Max = 100`,
`Balance.Damage.push = 24`, `Parry.CounterWindow = 1.6`):

| Escudo | Como se calcula | Fuerza | Tope 0,40 |
|---|---|---|---|
| `escudo_sol` | `0.04/0.22 + 8/100` | 0,262 | correcto |
| `escudo_laureles` | `0.08 + 20/100` | 0,280 | correcto |
| `escudo_tormenta` | `0.07 + 6/24` | **0,320** | correcto |
| `escudo_tormenta` *(con el 8 del test)* | `0.07 + 8/24` | **0,403** | **se pasa** |
| `escudo_constelacion` | `0.35/1.6 + 0.10` | 0,319 | correcto |
| `escudo_espectral` | `0.08 + 0.30` | **0,380** | correcto |

Dos cosas salen de esa tabla:

1. **`escudo_espectral` da exactamente 0,38**, que es lo que dice el comentario de
   `A.List`: *"el tope es 0.40 y el mas fuerte llega a 0.38"*. El balance rescued es
   coherente con el `OilConfig` que hay hoy, y el margen para las cajas futuras existe.
2. **Con 8, el Downloads se iria a 0,403 y romperia el tope.** El valor se bajo de 8 a 6
   precisamente para respetarlo, y el test no se actualizo.

Al reconectar esto habra que cambiar esa linea del test a `6`. En la copia se deja tal
cual: un rescate es una copia literal y no se arregla nada dentro de `checkpoint/`.

## 2ter. El test del original NUNCA PASO (encontrado al ejecutarlo 2026-10-11)

Al portar el test a `src/` y ejecutarlo por primera vez, revienta:

```
[FAIL] ShieldAbilities_Test > Las rares son utiles pero ningun escudo agota su tope
       | ShieldAbilities_Test:111: invalid argument #1 to 'insert' (table expected, got nil)
```

No es un error de la copia: **esta en el original, en la linea 106**:

```lua
local fuerzas = {}              -- se declara con Z
table.insert(fuertes, s)        -- se usa con T
```

En Luau un nombre no declarado **no da error**: vale `nil` en silencio, y revienta mas
tarde, cuando ya se usa. Por eso el preflight no lo ve (el programa es Luau valido) y por
eso el trabajo de los escudos se quedo parado sin que nadie supiera por que: **ese test
llevo tiempo fallando y nadie lo ejecutaba.**

Por cierto, el preflight tiene una regla llamada `adelantada` que avisa de referenciar un
`local` declarado mas abajo. Esta vez es al reves (typo en vez de orden), asi que no la
cogio. **Un nombre mal escrito es un global, y un global es `nil`: mismo peligro, otra
regla.**

La copia del checkpoint se queda con la erre. En el codigo vivo
(`src/server/UnitTest/Cases/ShieldAbilities_Test.luau`) esta corregido, y lo mismo con el
`reflectBalance` de 8 a 6. Los dos cambios estan explicados en la cabecera del archivo.

Con las dos cosas corregidas: **68 tests en verde** (46 previos + 22 nuevos).

## 3. Ids de escudo recovered

De los dos archivos rescatados salen mas ids de los que creiamos:

| Id | Que se sabe |
|---|---|
| `escudo_sol` | Resplandor · raro · con habilidad |
| `escudo_laureles` | Laureles · raro · con habilidad |
| `escudo_tormenta` | Descarga · raro · con habilidad |
| `escudo_constelacion` | Guia Astral · raro · con habilidad |
| `escudo_espectral` | Llama Fantasma · raro · con habilidad |
| `escudo_azul` | **Azul Clasico** · el escudo base · SIN habilidad |
| `escudo_esmeralda` | **comun** · SIN habilidad |

Ademas el test delata el nombre del slot: **`Cosm.Items.shield`**, y que los escudos de
caja se marcan con `it.boxOnly`.

El "**las cinco rares**" del comentario del test cuadra con la lista: cinco raros. Las
comunes (como `escudo_esmeralda`) y el Azul Clasico quedan fuera de `A.List` a proposito.

---

## 3. El agujero: falta el catalogo `CosShield`

`ShieldAbilities` y su test **leen `CosShield`**, que deberia ser el catalogo de escudos
con su aspecto (`ShieldSkins`), su rareza, su precio y la caja de la que salen
(`boxOnly`, `box`). **`CosShield` no esta en ningun respaldo.**

La unica copia de `CosmeticsShared` que se ha salvado es la version vieja (3.331 bytes):
tiene 6 gestos de victoria y 6 efectos de ring-out, y **ni una linea de escudos**.

O sea: esta guardado el motor y se perdio el contenido. Los precios, las cajas y la
lista de colores hay que reconstruirlos.

Lo que si se conserva del diseno, y alcanza para reconstruirlo:

- **5 escudos** con habilidad, con sus ids y sus numeros (ver `A.List` en el archivo
  rescatado): `escudo_sol` (Resplandor), `escudo_laureles` (Laureles), `escudo_tormenta`
  (Descarga), `escudo_constelacion` (Guia Astral), `escudo_espectral` (Llama Fantasma).
- **Solo los raros tienen habilidad.** El propio archivo lo dice: *"la rareza tiene que
  notarse tambien en la pelea, no solo en el color"*. Los comunes son estetica pura.
- **Tope por rareza** (`A.Budget`): `comun = 0.25`, `raro = 0.40`. Los raros estan
  calibrados para no pasar de 0.40 de fuerza, y el mas fuerte llega a 0.38, dejando
  sitio a las cajas futuras (epico, legendario) sin retocar estos.
- **14 claves de efecto** entre bloqueo y parry, cada una con su `min`/`max`.
- El texto del jugador **se genera desde los numeros** (`A.Describe`), asi que no puede
  quedar desajustado del valor real.

## 4. Estado: esto NO está conectado al combate

El propio `ShieldAbilities` lo avisa en su cabecera:

> OJO: ESTO AUN NO ESTA CONECTADO AL COMBATE. OilCombat lee
> `CFG.Stamina.BlockDrainPerSec` y `CFG.Parry.Window` directamente y no consulta este
> modulo, asi que ninguna habilidad cambia nada en la pelea todavia.

Lo que **si** hay, en `src/server/OilCombat.luau` (el nucleo vivo): el bloqueo existe y
funciona (`e.blocking`, `e.bar`, `block` en `ACTION_LIST`, `e.brokenUntil`). Falta la
capa de cosmetica encima, no la mecanica.

El enganche esta previsto: `A.ForPlayer(jugador)` lee el atributo `CosShield` del
jugador, que deberia fijar el servidor. Ese es el punto por donde habria que empezar.

## 5. Trampa: los archivos del lugar estan en Latin-1

Los scripts guardados desde Studio **no estan en UTF-8**: las tildes, la `ñ` y la `¡` y
la `¿` ocupan **un byte**, no dos. En `ShieldAbilities` la palabra "Guia" lleva `í` como
byte `0xED` suelto.

Dos consecuencias praticas:

1. Al copiar el texto a un archivo UTF-8 "normal", el hash **no coincide** aunque se lea
   exactamente igual. Hay que convertir a Latin-1.
2. `tools/lua_preflight.py` reventaba con `UnicodeDecodeError` al leer estos archivos, y
   con ello **tumbaba el control de los otros 45**. Corregido: lee bytes y cae a
   Latin-1, y lo marca con `[Latin-1]` sin romper la puerta.

Y un detalle que casi hizo pasar por buena una copia falsa: un archivo con el `í` en
UTF-8 (2 bytes) y **sin** salto de linea final tiene **exactamente los mismos 9489
bytes** que el original con el `í` en Latin-1 (1 byte) y **con** salto de linea final.
Mismo numero de bytes, contenido distinto. Por eso el hash, y no el tamano.

## 6. El MCP y los caracteres no-ASCII

`execute_luau` **se cuelga** al devolver texto con bytes por encima de 127. No es un
error: es un timeout sin mensaje. Workaround: filtrar antes de devolver
(`l:gsub("[\\128-\\255]", function(c) return "<N" .. string.byte(c) .. ">" end)`) y
reconstruir despues.

`script_read` si aguanta, pero **no llega a `ServerStorage` en modo Play** (si en modo
Edit, y solo para algunos scripts).

Este MCP da menos de si de lo que parece con archivos grandes: se leyó en 4 tramos de
55, 75 y 87 lineas, con el filtro de no-ASCII delante.