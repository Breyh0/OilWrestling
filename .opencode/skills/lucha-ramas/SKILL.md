# Skill: Ramas y releases — Lucha de aceite

Complemento operativo de `lucha-workflow`. Cargar **antes** de crear una rama, antes de
mergear y cuando haya que deshacer algo.

**Fuente de verdad: `docs/WORKFLOW.md`.** Si esta skill contradice a ese documento,
manda `docs/WORKFLOW.md`.

## La idea

`main` es la versión que funciona. Si `main` está verde, se puede volver a ella con un
`git checkout main` y seguir. Ese es el 90% del valor: no se pierde trabajo nunca por
haber tocado código.

```
main ────●──────●──────────────────●──►  (solo lo verificado)
         \      \                /
          \      ●──●──●        /      feature/x: se trabaja, se rompe, se arregla
           feature/x ──────────/        y solo entra en main con el visto bueno
```

## Antes de empezar una tarea

```powershell
git checkout main
git pull
git checkout -b feature/<nombre>
```

- El nombre describe **qué hace**, no quién lo hizo: `feature/tienda-cajas`, no
  `feature/supergamertth8`.
- **Una rama, un tema.** Un arreglo de sonido y una tienda nueva van en ramas
  separadas. Si una se rompe, la otra se mergea igual.
- Si la tarea es un bug de `main`, se hace una rama de arreglo igualmente. También
  `main` es la red.

## La puerta

```powershell
python tools\lua_preflight.py src docs .opencode
```

Antes de **cada** commit. Sin excepción. Está documentado en `docs/PREFLIGHT.md`.

Si cambias una regla del preflight, comprueba que sus autotests siguen pasando:

```powershell
python tools\preflight_selftest.py
```

## Antes de mergear

Las cuatro comprobaciones, en orden. Si una falla, no se mergea:

```powershell
# 1. preflight limpio
python tools\lua_preflight.py src docs .opencode
python tools\preflight_selftest.py

# 2. tests: 46/46 (en playtest, contexto Server -- ver docs/WORKFLOW.md seccion 5)

# 3. 0 errores de consola tras jugar

# 4. el diff, mirado de verdad
git diff main...feature/<nombre> --stat
git diff main...feature/<nombre>
```

En el diff, los cinco puntos donde de verdad se rompe algo:

- ¿Toca `OilCombat`, `OilPhysics` u `OilConfig`? Es el núcleo: mirarlo el doble.
- ¿Añade `require` de algo que no existe? Rompe el arranque.
- ¿Trae remoto nuevo? Tiene que estar en `src/shared/*.model.json`.
- ¿Deja números mágicos? El balance va en `OilConfig`.
- ¿Borró algo? Un `require` hacia lo borrado deja el script calling a nil.

## Mergear

```powershell
git checkout main
git pull
git merge feature/<nombre> --no-ff -m "merge: <que hace>"
# tests otra vez en main: el merge puede cambiar cosas
python tools\lua_preflight.py src
git push
```

**Visto bueno del usuario antes de mergear a `main`.** No es burocracia: él oye los
sonidos y ve la interfaz, y eso no se puede medir desde un script.

El mensaje de merge dice **qué se cambió y cómo se verificó**, no "cambios varios".

## Ramas viejas

Una rama que lleva semanas sin probarse es ruido: hace dudar de cuál es la buena. Se
borra, y si el trabajo importa, se rehace con su contenido (está en el log).

## Deshacer

| Situación | Qué hacer |
|---|---|
| El código está mal, no está en `main` | `git checkout -` y arreglar. Nadie se ha enterado. |
| Está mal y ya está en `main` | Rama de arreglo. **Nunca** `git revert` a ciegas: `git log` para ver qué commit lo introdujo. |
| Rojo no sincroniza tras un cambio | Recordar: `git pull` **antes** de sincronizar, o el archivo local pisa lo del otro. |
| El place quedó con un cambio de escena que no se quiere | Ctrl+Z en Studio y volver a guardar. Escena no está en git: no hay más red que esa. |

## La trampa que más caro sale

Rojo va en una dirección: **archivo → juego**. Si alguien editó un script en Studio y
tú sincronizas sin haber comprobado qué tenía, su trabajo se pierde sin aviso. Antes de
sincronizar tras una sesión en la que otra persona estuvo en el place, comprobar que el
`Source` del script en el lugar coincide con el archivo (barrido de hashes, en
`docs/MEMORY.md`).

## Escena: la capa sin red

Ni `Workspace` ni `StarterGui` están en git. Para esos cambios:

1. Se trabajan en Studio.
2. **Se publica el place** (Ctrl+S). Si no, no existen.
3. Se anota en `docs/MEMORY.md` que hay cambios de escena sin commit.

Una rama protege el código. **No protege el ring, ni la GUI, ni los sonidos.**
