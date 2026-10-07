# 🏛️ Lucha de aceite

Juego de lucha en aceite en Roblox: empuja al rival fuera del ring (ring-out). Primero en llegar a **3 puntos** gana. Modos: **solitario** (vs IA) y **multijugador** (hasta 4).

- **Place**: placeId `76883498915584` · Universe `10769662284`
- **Propietario**: supergamertth8 (grupo **Kyubu Studio**) — place compartido por **Team Create**
- **Equipo**: Breyh0 + supergamertth8, cada uno desde su PC con su propia IA conectada por Studio MCP

## Estructura del repo

| Carpeta | Rojo la sincroniza hacia | Contenido |
|---|---|---|
| `src/server/` | ServerScriptService | MatchLoop, OilCombat, PushServer, progresión |
| `src/shared/` | ReplicatedStorage | OilConfig, OilPhysics, OilControls, ProgressionShared + RemoteEvents |
| `src/client/` | StarterPlayerScripts | input, HUDs, menús, loading |
| `src/character/` | StarterCharacterScripts | FightIdle, PushClient |
| `docs/MEMORY.md` | — | **Memoria del proyecto: leer antes de tocar nada** |

`StarterGui` (los ScreenGuis con sus frames) **no** lo gestiona Rojo: la UI se edita en Studio.

## Reglas del equipo

1. **`git pull` antes de empezar** · `git push` al terminar — nada de cambios locales olvidados.
2. **Código → solo en archivos** (editor o tu IA). Nunca en el editor de scripts de Studio: Rojo lo pisa.
3. **Escena y GUI → solo en Studio** (modelos, terreno, frames). git no fusiona el `.rbxl`.
4. Programar con `rojo serve` corriendo + plugin de Rojo conectado en Studio.
5. Los cambios de escena se guardan en Roblox normal (Team Create).

## Comandos

```sh
rojo serve                              # o: doble clic en iniciar-rojo.bat
git pull                                # traer cambios del compañero
git add -A && git commit -m "qué hice"  # registrar
git push                                # compartir
```

> ⚠️ `rojo serve` **no es un servicio automático**: es una ventana de terminal que debe estar abierta mientras se programa, y el plugin de Studio solo se conecta a ella. Si Studio dice *"Couldn't connect to the Rojo server"* → el serve no está corriendo: abre `iniciar-rojo.bat` y vuelve a pulsar **Connect** en Studio.

## Primera vez aquí

→ [SETUP.md](SETUP.md) para instalar todo, → [docs/MEMORY.md](docs/MEMORY.md) para entender el proyecto.
