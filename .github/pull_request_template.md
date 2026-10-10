## Qué cambia

<!-- Una o dos frases. Qué problema resuelve, no qué archivos tocaste. -->

## Por qué en rama y no en main

<!-- feature/x. main es la versión que funciona; si esto se rompe, la rama se tira
     y se vuelve a main en un segundo. -->

## Verificación

Marca lo que **has comprobado de verdad**, no lo que esperas que funcione:

- [ ] `python tools\lua_preflight.py src docs .opencode` → 0 problemas
- [ ] `python tools\preflight_selftest.py` → TODO OK (si tocaste el preflight)
- [ ] 46/46 tests de Luau en playtest
- [ ] 0 errores de consola en playtest
- [ ] Una partida jugada de principio a fin
- [ ] Tocado `OilCombat` / `OilPhysics` / `OilConfig` → playtest largo

**Lo que la CI no puede comprobar** (porque necesita a una persona o a Roblox) está
en la lista de arriba. Si algo no lo has comprobado, dilo aquí en vez de darlo por bueno.

## Detalle de lo verificado

<!-- Números concretos, no "funciona". Ejemplos válidos:
     - fx ringout → SD_SplashSlip 0.60, una vez, y 0 efectos al abrir el menú
     - 3 rondas completas, 0 errores
     - preflight: 0 problemas en 23 archivos -->

## Qué NO he verificado

<!-- Lo que queda pendiente y por qué. Un informe que exagera la cobertura hace que
     el compañero deje de fiarse, que es peor que no informar. -->

## Riesgo y reversión

<!-- Qué es lo que puede romperse aunque todo lo anterior esté en verde.
     ¿Se puede deshacer con un revert, o hay que tocar el place a mano?
     Si toca OilCombat, dilo aquí: es el núcleo. -->

## Impacto en datos de jugador

<!-- Solo si añade o cambia campos de la progresión: ver docs/DATOS.md.
     ¿Toca DefaultData? ¿Reconcile? ¿Snapshot? ¿La versión del esquema?
     ¿Hay algún jugador con datos viejos que se queden fuera? -->

## Escena o GUI

<!-- Si el cambio es de escena (ring, HUD, sonidos, modelos): NO está en git.
     ¿Está el place publicado? Sin publicar, este cambio no existe para nadie más. -->
