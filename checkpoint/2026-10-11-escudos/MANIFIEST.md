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

Es el que faltaba. Todas las copias se comprueban con:

```powershell
python tools\verificar_rescate.py checkpoint\2026-10-11-escudos
```

Un **hash que no coincide significa que la copia no sirve**, aunque compile y aunque se
lea bien. Por eso la verificacion es automatica y no una mirada.

## 2. Que queda por rescatar

Mismo origen, mismo riesgo. Cuando se_extraigan, la lista de arriba va creciendo:

| Archivo en el lugar | FNV | Bytes | Notas |
|---|---|---|---|
| `Respaldo_Habilidades_Escudos.ShieldAbilities_Test_original` | `2089202569` | 5284 | los 4 invariantes de las habilidades |
| `Respaldo_Tienda_Cajas.OilBlockVFX_original` | `3743230225` | 19140 | el aspecto del escudo en pantalla |
| `Respaldo_Tienda_Cajas.OilCombat_original` | `1511816891` | 50433 | OilCombat con ganchos `cosmetic*` |
| `Respaldo_Tienda_Cajas.CosmeticsShared_original` | `825101627` | 3331 | ya rescatado en el checkpoint del 2026-10-10, sin escudos |

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