# La escena: la capa que no está en git

`Workspace`, `StarterGui` y `SoundService` **no están en git**. Rojo no los gestiona
(default.project.json solo mapea cuatro servicios) y el `.rbxl` no se versiona. Este
documento explica cómo se vigila esa capa.

## Por qué no se sube el archivo del lugar

Se puede (File → Save to File), pero no.should:

1. **El archivo lleva los scripts dentro.** Habría dos fuentes de verdad para el código:
   `src/` y el `.rbxl`. Rojo sincroniza `src/` → lugar, así que el primer merge
   "restauraría" scripts viejos y desharía el código nuevo. Es la trampa que ya costó
   trabajo.
2. **Los merges son inútiles.** El lugar tiene ~5.500 objetos. Un `.rbxlx` da diffs de
   decenas de miles de líneas que git no sabe resolver; un `.rbxl` es binario y no tiene
   diff ni merge, solo snapshots completos.
3. **Crece sin control.** Cada guardado es un snapshot entero, y el repo se llena de blobs
   que nadie puede leer.

Por eso `.rbxl` y `.rbxlx` están en `.gitignore`, y `*.rbxl` marcado como binario en
`.gitattributes`: para que nadie lo suba por error.

## La red de verdad: publicar

**El historial de versiones de Roblox es el control de versiones de la escena.** El
Creator Dashboard guarda las versiones publicadas y se pueden restaurar. Eso ya existe y
no hay que montarlo.

El problema nunca fue la falta de respaldo: es **no publicar**. Si se cierra Studio sin
guardar, se pierde, y da igual cuántas ramas haya.

Regla: la escena se publica **inmediatamente** después de tocarla. Está en la Definition
de Done de `docs/WORKFLOW.md`.

## El manifiesto: detecta, no restaura

Como la escena no se puede diffear, se **vigila**:

```
escena/inventario.luau      -> genera el inventario (huella + tablas)
escena/MANIFIEST-ESCENA.md  -> el resultado, versionado en git
tools/verificar_escena.py   -> comprueba que el manifiesto no lo editaron a mano
```

### Cómo se usa

1. **Antes** de tocar escena: generar el manifiesto y commitearlo.
2. Tocar la escena en Studio (y publicarla).
3. **Después**: volver a generarlo y commitear el diff.

El `git diff` de ese archivo dice exactamente qué cambió: cuántos objetos, qué parte se
movió, qué sonido cambió de volumen, qué panel del menú aparece o desaparece.

La huella es el FNV-1a de 32 del propio documento. Una sola línea que cambia cuando cambia
cualquier cosa de la lista. Para comprobarla:

```powershell
python tools\verificar_escena.py
```

## Qué ha encontrado esto

La primera vez que se generó (2026-10-10) detectó dos cosas que nadie tenía registradas:

**1. El ring se movió.** `OilArena` estaba en `(4, 6.1, -36)` y ahora está en
`(0, 6.1, 0)`. Todo el anillo (`GoldFrame`, `MarbleTier`, `PedestalBase`) está en el
origen. Nadie lo tenía anotado en ningún sitio, y el `checkpoint/` del 10 de octubre
también está desactualizado en ese dato.

Se comprobó que **no rompe nada**: `OilPhysics` y `OilCombat` leen el ring dinámicamente
(`ring:FindFirstChild("OilArena")`), no hay coordenadas escritas a mano, y existe un
`SpawnLocation` real (`BroadcastBooth.BoothSpawn2`), así que el fallback de
`MatchLoop.getLobbyCFrame()` no se usa. Aun así, cualquier cambio de posición del ring
tiene que acabar en el diff del manifiesto.

**2. Tres `Part` sueltos flotando a ~3.000 studs** de altura, anclados y con colisión.
No rompen el juego (nadie llega ahí), pero son basura de alguna prueba. **No se borran sin
preguntar**: pueden ser del compañero. Aparecen en la sección "Objetos sueltos" del
manifiesto para que no se pierdan de vista.

## La sección "Objetos sueltos en la raíz"

El generador lista lo que no es `Folder`, ni `Model`, ni `Baseplate`, ni `Terrain`, ni un
`SpawnLocation`. No es una lista de basura: es una lista de **preguntas**. Si no sabes qué
es algo, preguntas antes de borrarlo.

## Lo que este mecanismo no cubre

- **Restaurar**: solo puede decirte qué cambió, no devolverlo. Para eso, publicar.
- **Fusionar conflictos de escena** entre dos personas: Team Create lo hace en vivo y este
  mecanismo no interviene.
- **Assets** (sonidos, modelos, texturas): solo se ve su `assetId`, no el archivo.
