# Skill: Añadir un sistema nuevo — Lucha de aceite

El flujo para meter una feature completa (tienda, cajas, habilidades, un modo de juego).
Cargar **antes** de empezar una feature, no después.

**Fuente de verdad: `docs/WORKFLOW.md`, `docs/DATOS.md`, `docs/OILCOMBAT.md`.**

## La regla que decide cómo se parte una feature

> Si el sistema no tiene **ningún** camino de ejecución, es unaLibrary: se mete **entera y separada**.
> Si toca el núcleo, se mete **por capas**, empezando por la que no puede romper el arranque.

Tienda y cajas: empiezan por `CosmeticsShared` (catálogo, datos puros, cero riesgo) y
continue. El día que haya que tocar `OilCombat` para enganchar una habilidad, eso es una
rama aparte con su propio playtest largo.

Motivo: un sistema a medias enseñado en la interfaz es **peor que no tenerlo**. El jugador
pulsa y no pasa nada, y el bug se atribuye al sistema entero.

## Checklist de las nueve capas

Cada capa se commitea por separado y se puede revertir por separado.

### 1. Los datos puros (sin nada de Roblox)
El catálogo, las reglas, los precios. Un módulo que solo devuelve tablas y funciones, sin
`Instance`, sin servicios, sin eventos. **Es la única capa que se puede testear de verdad**,
así que es la que más tests merece.

```
src/shared/CosmeticsShared.luau   -- Slots, Rarities, Items, Get(id), IsValid(slot, id)
```

Un módulo así se puede testear sin entrar a Roblox. Si al añadir una feature el módulo
"necesita" un `Sound` o un `Instance`, es que está mezclando responsabilidades: sepáralo.

### 2. Los tests, ANTES de la lógica
```lua
-- src/server/UnitTest/Cases/<Modulo>_Test.luau
```
Primero el test que falla, luego la función. Si no se puede testear, es que está en la
capa equivocada.

### 3. Los datos del jugador
Si el sistema guarda algo, ver `docs/DATOS.md`: **cuatro toques obligatorios**
(`DefaultData`, `Reconcile`, `Snapshot`, test del jugador viejo). La compra con monedas
solo es segura si el descuento lo hace el servidor.

### 4. El servidor
Validación, precios, propiedad. **Nunca confíes en lo que envía el cliente.** El cliente
pide; el servidor decide y responde.

### 5. El remoto
Nuevo remoto → `src/shared/<Nombre>.model.json`, con **throttle y whitelist** como el
resto. Un remoto sin whitelist es una puerta abierta.

### 6. El cliente
Solo pinta. Escucha el remoto, actualiza la interfaz. Cero lógica de negocio: si el
cliente calcula un precio, hay un bug.

### 7. La GUI
En Studio (Rojo no gestiona `StarterGui`). **Publicar el place**: si no, no existe.
Los `WaitForChild` sin timeout, por la regla dura del proyecto.

### 8. Los efectos
Si hay sonidos: `SoundDirector` ya tiene el mapa. **Un tipo de evento nuevo sin mapear
sale mudo**, y nadie se da cuenta hasta que se juega. Si hay VFX: `OilSplash` para el
aceite, `Debris` para limpiar, y `CanCollide = false`.

### 9. La documentación
En el **mismo commit** del código, no después:
- `docs/MEMORY.md`: qué se añadió y qué gotcha tiene
- `docs/OILCOMBAT.md` si toca el combate
- `CHANGELOG.md`: una línea de lo que ve el jugador

## La Definition of Done

Una feature está terminada cuando **todo** esto es cierto:

- [ ] Rama `feature/<nombre>`, nunca `main`
- [ ] `python tools\lua_preflight.py src docs .opencode` → 0
- [ ] `python tools\preflight_selftest.py` → TODO OK
- [ ] Tests nuevos para la capa de datos, **más** los 46 existentes en verde
- [ ] 0 errores de consola en playtest
- [ ] Probado con datos viejos (si toca progresión)
- [ ] Probado en horizontal de PC **y** en móvil (ver `lucha-qa`)
- [ ] La GUI publicada en el place
- [ ] Documentación actualizada en el mismo commit
- [ ] Visto bueno del usuario

## Antes de tocar el núcleo

`OilCombat` tiene 1575 líneas y es donde vive todo. Si la feature lo necesita:

1. Rama propia, solo para eso.
2. El cambio más pequeño que funcione, no el rediseño que debería.
3. Playtest largo: tres partidas seguidas sin que se cuelgue nada.
4. `git diff main...rama` leído entero, línea por línea, con calma.
5. Si el cambio es de más de ~50 líneas en `OilCombat`, parar y hablarlo antes.

## Señales de que te has pasado de complejo

- El módulo "de datos" necesita `Instance` o servicios → partió capas.
- El test necesita un servidor → la lógica está en el sitio equivocado.
- El cliente calcula un precio → hay un bug de seguridad esperando.
- La interfaz enseña algo que aún no funciona → quitálo hasta que esté.
- Son 6 archivos tocados y ninguna capa se puede probar sola → sobra algo.
