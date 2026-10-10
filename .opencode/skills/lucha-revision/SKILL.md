# Skill: Code review — Lucha de aceite

Para revisar cambios **antes** de que entren en el repo. Cargar cuando alguien (un
compañero o una IA) ha hecho trabajo en el place o en una rama y hay que decidir qué se
guarda, qué se arregla y qué se tira.

**Fuente de verdad: `docs/WORKFLOW.md` y `docs/MEMORY.md`.**

## Lo primero: el barrido de hashes

Antes de opinar sobre nada, hay que saber **qué ha cambiado de verdad**. El place y
`src/` se comparan con un FNV-1a de 32 bits del `Source` de cada script.

El hash de Luau **no** se puede calcular con `h = (h * 16777619) % 2^32`: los números de
Luau son dobles, el producto se pasa de 2^53 y pierde precisión, así que da un hash
distinto para el mismo texto. Parece que todos los archivos cambiaron a la vez y se
busca una causa que no existe. Hay que multiplicar en trozos de 16 bits (fórmula entera en
`docs/PREFLIGHT.md` y en `checkpoint/*/MANIFIEST.md`).

Un barrido bien hecho responde de un vistazo a tres preguntas:

- ¿Qué código de Rojo ha cambiado? (casi nunca: si cambia, hay que decidir de qué lado)
- ¿Qué scripts están en el place y **no** en `src/`? (trabajo sin versionar)
- ¿Qué hay en `src/` que no está en el place? (el próximo sync lo crearía)

## Después, la tabla de decisiones

Cada cosa que aparezca va a una de estas tres columnas:

| Columna | Qué es | Qué se hace |
|---|---|---|
| **Vivo y en Rojo** | Código que el juego está ejecutando y que está en `src/` | Va a git tal cual, tras review |
| **Vivo y fuera de Rojo** | Funciona, pero en `StarterGui`, `ServerStorage` o scripts sin archivo | **Se rescata**: a `src/` si es código de cliente, a `checkpoint/` si es un sistema sin integrar |
| **Muerto** | Respaldos, código desactivado, sistemas a medias | Se documenta con hash y ruta. **No se borra sin permiso**: es la red del compañero |

Lo que nunca se hace: borrar el trabajo de otra persona porque "no se está usando". Se
documenta dónde está y qué hash tiene.

## Las cinco preguntas de la review

1. **¿Rompe el arranque?** Un `require` a un módulo que no existe tumba el juego entero.
   Es el fallo más caro y el más fácil de ver: `grep` de los `require` contra el
   inventario real de los servicios.
2. **¿Toca el núcleo?** `OilCombat`, `OilPhysics`, `OilConfig`. Aquí se mira el doble y se
   playtestea más rato. Un cambio de una línea aquí puede ser el que se rompa tres días
   después.
3. **¿Tiene la promesa que hace?** Si dice "cada skin tiene una habilidad", ¿existe el
   camino completo desde el botón hasta el efecto? Un sistema a medias que se enseña en
   la interfaz es peor que no tenerlo: el jugador pulsa y no pasa nada.
4. **¿Los números están centralizados?** El balance va en `OilConfig`. Un `1.5` suelto en
   un cliente es un bug esperando.
5. **¿Está lo que no se puede ver?** Escena, GUI y sonidos no están en git. Si alguien dice
   "añadí 120 figuras con animación", hay que contar los objetos reales y comprobar si hay
   `Animation`, `Animator` o `Humanoid`: 120 modelos posados no son 120 NPCs animados.

## El informe

Al final, siempre con este formato, aunque some lo que no se pudo comprobar:

```
Revisado: <fecha>, <rama o "el place">
- <qué se encontró, con números>
- <decisión tomada por cada cosa>
Pendiente: <lo que no se ha podido verificar>
```

La última línea no es opcional. Si solo se ha mirado el código, se dice. Un informe que
exagera la cobertura hace que el compañero deje de fiarse y es peor que no informar.

## Cuando la review encuentra bugs

Cada bug va a **su propia rama de arreglo**, no al de revuelto con la feature. Una rama
por bug conserva la historia y permite mergearlos por orden de riesgo: primero el que
tumba el arranque, el último el cosmético.
