# 🏛️ Lucha de aceite

Juego de lucha en aceite en Roblox: empuja al rival fuera del ring (ring-out). Primero en llegar a **3 puntos** gana. Modos: **solitario** (vs IA) y **multijugador** (hasta 4).

- **Place**: placeId `76883498915584` · Universe `10769662284`
- **Propietario**: supergamertth8 (grupo **Kyubu Studio**) — place compartido por **Team Create**
- **Equipo**: Breyh0 + supergamertth8, cada uno desde su PC con su propia IA conectada por Studio MCP

## Estructura del repo

| Carpeta | Rojo la sincroniza hacia | Contenido |
|---|---|---|
| `src/server/` | ServerScriptService | `MatchLoop`, `OilCombat`, `ProgressionService/Logic/System` + tests |
| `src/shared/` | ReplicatedStorage | `OilConfig`, `OilPhysics`, `OilControls`, `OilSplash`, `ProgressionShared` + RemoteEvents |
| `src/client/` | StarterPlayerScripts | input, HUDs, menús, `CharacterAnimator`, `SoundDirector` |
| `src/character/` | StarterCharacterScripts | `Animate` (stub que sustituye al de Studio) |
| `docs/` | — | **Empieza por `docs/WORKFLOW.md`** |

`StarterGui` (los ScreenGuis con sus frames) **no** lo gestiona Rojo: la UI se edita en Studio.

## Cómo se trabaja aquí

> `main` es la versión que **funciona**. Todo lo demás vive en una rama hasta que se ha
> probado de verdad. Si `main` está verde, se puede volver a ella en un segundo.

```sh
git checkout main && git pull
git checkout -b feature/<que-hace>
# ... trabajar: código en src/, escena en Studio ...

python tools\lua_preflight.py src docs .opencode   # puerta obligatoria
python tools\preflight_selftest.py                 # si tocaste el preflight
git add -A && git commit -m "qué y por qué" && git push
```

Antes de mergear a `main`: preflight limpio, **46/46 tests** en playtest, **0 errores de
consola**, una partida jugada de principio a fin y el visto bueno del usuario.

**El método completo está en [`docs/WORKFLOW.md`](docs/WORKFLOW.md).**

### Documentos

| Documento | Para qué |
|---|---|
| [`docs/WORKFLOW.md`](docs/WORKFLOW.md) | **El método.** Ciclo, puertas, ramas, code review |
| [`docs/MEMORY.md`](docs/MEMORY.md) | **Fuente de verdad.** Gotchas, estado, reglas del equipo |
| [`docs/DATOS.md`](docs/DATOS.md) | Cómo tocar los datos del jugador sin romperlos |
| [`docs/PREFLIGHT.md`](docs/PREFLIGHT.md) | Qué caza el preflight y de qué bug salió cada regla |
| [`docs/OILCOMBAT.md`](docs/OILCOMBAT.md) | Mapa técnico del combate |
| [`CHANGELOG.md`](CHANGELOG.md) | Qué se publica en cada versión |

### Skills (para las IAs del equipo)

| Skill | Cuándo |
|---|---|
| `lucha-workflow` | Siempre. Reglas duras y anti-conflicto |
| `lucha-qa` | Antes de dar algo por bueno. El playtest es el único veredicto |
| `lucha-ramas` | Al crear una rama, al mergear, al deshacer |
| `lucha-revision` | Al revisar trabajo ajeno antes de que entre al repo |
| `lucha-feature` | Al añadir un sistema nuevo de principio a fin |

## Reglas del equipo

1. **Una rama por tarea.** `main` solo recibe lo verificado.
2. **`git pull` antes de empezar** · `git push` al terminar.
3. **Código → solo en archivos `src/`**. Nunca en el editor de scripts de Studio: Rojo lo pisa sin aviso.
4. **Escena y GUI → solo en Studio**, y **publicar el place**: git no las guarda.
5. **Puerta antes de commitear**: preflight limpio. Antes de mergear: 46/46 tests y 0 errores de consola.

### Anti-conflictos (equipo)

1. **Flujo**: `git pull` → `Connect` (Rojo) → trabajar → `commit` + `push`. Nunca sincronizar Rojo con cambios locales sin pushear: tus archivos pisarían en el place lo que el otro ya hizo.
2. **El código se escribe en `src/`** — ni a mano ni con la IA *dentro* de Studio (ni vía MCP `multi_edit`): la siguiente sincronización lo sobrescribiría **sin aviso**. Lo sí válido: tu IA edita los archivos directamente (conectarán al instante en Studio si el plugin está conectado) y usa el MCP para **leer** el place, ejecutar Luau y trabajar la escena.
3. **Si `git push` rechaza** → `git pull`, resolver el merge (las IAs ayudan con el diff). Es el flujo normal, no pasa nada.
4. **Error "session lock" de Rojo** → otra persona tiene el place sincronizado: avisar al otro y desconectar. Ambos sincronizando con archivos idénticos es inocuo (el sync es idempotente); con archivos divergidos, no.
5. **Escena/GUI = solo Studio** (Team Create los fusiona en vivo). Código = solo archivos.

## Comandos

```sh
rojo serve                              # o: doble clic en iniciar-rojo.bat
git pull                                # traer cambios del compañero
git add -A && git commit -m "qué hice"  # registrar
git push                                # compartir
```

> ⚠️ `rojo serve` **no es un servicio automático**: es una ventana de terminal que debe estar abierta mientras se programa, y el plugin de Studio solo se conecta a ella. Si Studio dice *"Couldn't connect to the Rojo server"* → el serve no está corriendo: abre `iniciar-rojo.bat` y vuelve a pulsar **Connect** en Studio.

## Primera vez aquí

1. [`docs/WORKFLOW.md`](docs/WORKFLOW.md) — el método. Esto primero.
2. [`SETUP.md`](SETUP.md) — instalar Rojo y conectar Studio.
3. [`docs/MEMORY.md`](docs/MEMORY.md) — gotchas y estado del proyecto.
