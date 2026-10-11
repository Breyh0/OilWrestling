# Rendimiento: lo que se ha medido y lo que no

Fecha de la medición: **2026-10-11**. Todos los datos de aquí salieron de playtests
reales, no de suposiciones. Lo que no se pudo medir está escrito como tal al final.

---

## Resumen primero

**Ningún elemento de la escena es hoy un cuello de botella demostrable.** Se quitaron o
apagaron miles de objetos y las diferencias salieron **dentro del ruido de la medición**.

| Medición en Studio (PC, playtest) | Resultado |
|---|---|
| Lobby | 46 fps · 21,6 ms de frame time |
| Durante un combate | 45 fps · 22,2 ms |
| Diferencia entre estar en el lobby y pelear | **0,5 ms** |
| Ruido de la propia medición (5 vueltas idénticas) | **0,72 ms (3 %)** |

La pelea cuesta lo mismo que el lobby: lo que pesa es la escena en sí, no el combate. Pero
la escena tampoco es la causa, porque apagarla casi entera tampoco cambia nada. Los ~21 ms
de partida son coste fijo del editor más del motor.

**Esto significa que hoy no hay una emergencia de rendimiento**, y también que **cualquier
optimización que se haga ahora mismo sería adivinar**. La prioridad correcta es medir
bien, no tocar cosas.

---

## Cómo se midió

Con `RunService.RenderStepped` acumulando deltas durante varias ventanas y luego sacando
media, percentiles y la peor. Cada ventana de 5 a 10 segundos, siempre con repeticiones.

La metodología completa está en `tools/medir_fps.luau`, que es lo que se debe usar a
partir de ahora.

---

## El ruido: lo más importante de esta página

Medir **una vez** es no medir nada. Se hizo la prueba de control: cinco mediciones
**idénticas**, sin cambiar absolutamente nada:

```
vuelta 1:  21,94 ms
vuelta 2:  22,17 ms
vuelta 3:  21,46 ms
vuelta 4:  22,11 ms
vuelta 5:  21,70 ms
                   ruido = 0,72 ms (3 %)
```

Si con el escenario **igual** se obtienen 0,72 ms de diferencia, cualquier efecto de 0,5
o 0,9 ms que aparezca en un único par de mediciones **no es un hallazgo**: es ruido con
disfraz de hallazgo.

Por eso `Comparar` en la herramienta no compara una medición con otra, sino que exige que
la diferencia supere **el ruido de las dos sumados**. La prueba real:

```
estado actual        media 21,75 ms   ruido 1,57 ms
sin sombras globales media 20,96 ms   ruido 1,04 ms
diferencia 0,79 ms | ruido combinado 2,61 ms  ->  DENTRO DEL RUIDO
```

Con cuatro repeticiones por variante, **apagar las sombras no se puede afirmar que
impromente nada**. Con una sola medición parecía un 4 % de mejora, y era ruido.

---

## Variantes probadas

Todas en playtest, con 5 segundos por variante y restaurando el estado después de cada
una. **Nada de esto toca el lugar**: Play descarta los cambios al parar.

| Variante | media (una sola pasada) | Diferencia contra la base |
|---|---|---|
| 1. Todo como está | 21,39 ms | — |
| 2. Sin sombras globales | 20,46 ms | −0,93 ms |
| 3. Sin las 54 luces | 20,95 ms | −0,44 ms |
| 4. ColosseumStructure a transparente (2.311 objetos) | 20,85 ms | −0,54 ms |
| 5. OilWrestlingRing a transparente (774 objetos) | 21,21 ms | −0,18 ms |
| 6. ArenaCrowd a transparente (120 figuras) | 23,70 ms | **+2,31 ms** |

Dos cosas que hay que leer aquí:

- **Las diferencias son todas menores que el ruido** salvo la última.
- **La variante 6 empeoró.** Poner `Transparency = 1` **no quita objetos del render**: los
  sigue dibujando. Por eso "ocultar" así el público cuesta más, no menos. Apagar por
  `Enabled = false` en las luces y sombras sí es apagar de verdad; poner algo transparente
  no lo es.

**Conclusión: no hay ningún candidato a Bottleneck.** Borrar el público, el coliseo o el
ring sería un trabajo grande para un beneficio que no se puede demostrar.

---

## Estado medido de la escena

```
StreamingEnabled      true          (la palanca grande ya está puesta)
ModelStreamingMode    Default
GlobalShadows         true
Brightness            3
Bloom                 Intensity 0,35 · Size 24
Atmosphere            Density 0,30 · Haze 0
ParticleEmitters      9
Luces                 54  (52 PointLight, 1 SpotLight, 1 SurfaceLight) — solo 1 con Sombras
Decals y texturas     122
Objetos en Workspace  5.103
Instancias en cliente 54.332 – 54.433
```

Reparto de los 5.103 objetos:

| Carpeta | Objetos |
|---|---|
| `ColosseumStructure` | 2.311 |
| `ArenaCrowd` | 1.561 |
| `OilWrestlingRing` | 774 |
| `AmbientacionRomana` | 413 |

Lo razonable con 54 luces y solo 1 con sombras activadas es que **el coste está en el
número de instancias y no en la iluminación**. Pero, otra vez: quitar 3.085 objetos del
coliseo no ha movido la aguja. Ese camino no está justificado ahora mismo.

---

## Lo que NO se ha medido

Esto es importante para no dar por bueno lo que no está comprobado:

- **Móvil.** Nada. Es la plataforma que manda y es la primera que se cae. El simulador de
  dispositivos del MCP (`rbx-device-simulator-lua`) puede usarse, pero no se ha usado.
- **Memoria.** Las propiedades `MemoryTotalMb`, `MeshMemoryMb`, `TextureMemoryMb` del
  servicio `Stats` no están expuestas en este entorno. Solo `InstanceCount` respondió.
- **Cliente publicado.** Todo esto es Studio, que tiene su propio coste. Un cliente
  publicado irá distinto, casi siempre mejor.
- **Servidor.** No se ha medido el frame time del servidor ni con 2, 6 o 20 jugadores.
- **Coste de la GUI.** 417 objetos en `StarterGui`, uno de ellos 257 en el `MainMenu`.

---

## El presupuesto

Números concretos, para que "va lento" sea una discusión medible y no una opinión:

| Métrica | Verde | Aviso | Actuación |
|---|---|---|---|
| Frame time cliente (mediana, 5 s) | ≤ 16,7 ms | > 22 ms | > 28 ms |
| FPS cliente | 60 | < 45 | < 35 |
| Objetos en Workspace | ≤ 5.100 | > 6.000 | > 8.000 |
| Instancias en cliente | ≤ 55.000 | > 65.000 | > 80.000 |
| Frame time del servidor | ≤ 16,7 ms | > 22 ms | > 28 ms |

El umbral de aviso está puesto **por encima** de los ~21,9 ms que da Studio, a propósito:
Studio no es el objetivo. Si un cambio en Studio deja la mediana claramente por debajo de
21 ms, es que ha hecho algo; si se queda en 21-22 ms, no se puede saber.

## Regla para no volver a caer en el ruido

1. Antes de tocar nada, `M.Medir({ repeticiones = 4, segundos = 5 })`.
2. Después de tocar, otra vez con los mismos parámetros.
3. `M.Comparar(antes, despues)`. Si dice "DENTRO DEL RUIDO", **no se afirma nada** y se
   sigue.
4. Si dice "DIFERENCIA REAL", se escribe el número en `CHANGELOG.md`.

Con tres pasos menos, cualquier mejora se puede volver a perder en la siguiente sesión.

---

## Cómo continuar

Lo siguiente no es optimizar, es **medir donde de verdad importa**:

1. **Móvil primero.** Con `rbx-device-simulator-lua` del MCP: perfil bajo y medir con el
   mismo `medir_fps.luau`. Si algo cae por debajo de 30 fps, eso manda sobre cualquier
   número de PC.
2. **Cliente publicado**, no Studio. La red del lugar es `File > Publish to Roblox`, y ahí
   sí se mide lo que ve el jugador.
3. **Coste de la GUI**, que son 417 objetos y no se ha mirado. Es lo más probable que
   crezca sin que nadie lo note, porque la tienda por capas está por empezar.
4. **Servidor con carga**, que es lo único que falta y lo que más se nota cuando haya
   gente jugando.

Hasta que esas cuatro estén hechas, este documento debe decir "no se ha medido" en
ellas. Y si alguien cita un número de rendimiento, que venga de aquí.