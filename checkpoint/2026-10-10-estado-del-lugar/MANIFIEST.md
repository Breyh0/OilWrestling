# Checkpoint del lugar — 2026-10-10

Estado del place (`76883498915584`) en el momento de este commit. Sirve para dos cosas:

1. **Rescatar** lo que vivía solo en Studio y no estaba en git.
2. **Detectar cambios**: cada script tiene su hash FNV-1a de 32 bits. Si un día un hash no coincide con el del lugar, ese script cambió (o se perdió).

> Esta carpeta **no la lee Rojo**. `default.project.json` solo mapea `ReplicatedStorage`,
> `ServerScriptService`, `StarterPlayerScripts` y `StarterCharacterScripts`, así que
> nada de lo que hay aquí se sincroniza al juego ni se pisa con un `rojo serve`.

---

## 1. Código versionado: sin cambios

Los **22 archivos de `src/` son byte a byte idénticos** a los del place. Ningún cambio de
código de Rojo ocurrió desde el commit `4314952`.

## 2. Rescatado en este checkpoint

| Archivo en este repo | Origen en el place | FNV | Bytes | Estado |
|---|---|---|---|---|
| `StarterGui.ProgressionUI/ProgressionClient.client.luau` | `StarterGui.ProgressionUI.ProgressionClient` | `1711502648` | 31232 | **VIVO** (copia verificada byte a byte) |
| `ServerStorage.Respaldo_Tienda_Cajas/CosmeticsShared_original.luau` | `ServerStorage.Respaldo_Tienda_Cajas.CosmeticsShared_original` | `825101627` | 3331 | En respaldo (copia verificada byte a byte) |

## 3. Lo demás que hizo, solo en el place

Estos siguen **dentro del place** (se pierden si alguien limpia `ServerStorage`).
No se extrajeron: el MCP dio timeout dos veces seguidas con `ShieldAbilities` y son
grandes. Los hashes permiten saber si cambian o desaparecen.

| Script en el place | FNV | Bytes | Qué es |
|---|---|---|---|
| `Respaldo_Habilidades_Escudos.ShieldAbilities_original` | `3684004711` | 9489 | Habilidad por skin de bloqueo |
| `Respaldo_Habilidades_Escudos.ShieldAbilities_Test_original` | `2089202569` | 5284 | Tests de las habilidades |
| `Respaldo_Habilidades_Escudos.OilCombat_original` | `1511816891` | 50433 | OilCombat + ganchos `cosmetic*` |
| `Respaldo_Tienda_Cajas.OilBlockVFX_original` | `3743230225` | 19140 | VFX de bloqueo |
| `Respaldo_Tienda_Cajas.ProgressionLogic_original` | `220074352` | 12990 | Lógica con tiendas/cajas |
| `Respaldo_Tienda_Cajas.ProgressionService_original` | `1575331139` | 14421 | Servicio con tiendas/cajas |
| `Respaldo_Tienda_Cajas.MainMenuClient_original` | `2341815890` | 16573 | Menú con tienda |
| `Respaldo_Deslizamiento.CharacterAnimator_original` | `1677207684` | 37013 | Animación de victoria |
| `Respaldo_Deslizamiento.OilConfig_original` | `3549638828` | 4584 | Balance anterior |
| `Respaldo_Deslizamiento.OilPhysics_original` | `1194257643` | 9131 | Física anterior |
| `Respaldo_Animacion.FightIdle_original` | `213184423` | 3170 | Idle de combate |
| `Respaldo_UI_Progresion.ProgressionUI_anterior.ProgressionClient` | `1474751144` | 1111 | Panel de progreso v1 |
| `ZeroScript.Memory` | `1838474336` | 1838 | Marcador conocido, no borrar |

## 4. Escena y GUI (solo en el place, nunca en git)

| Zona | Contenido |
|---|---|
| `StarterGui.MainMenu` | 257 elementos (`Panel`, `ModePanel`, `ShopPanel`, `CodesPanel`, …) |
| `StarterGui.LoadingScreen` | 136 elementos (`Content`, `BarBg`, `BarFill`, `Shine`, `Tip`, …) |
| `StarterGui.GameHUD` | 16 · `FighterGui` 6 · `ProgressionUI` 2 |
| `Workspace.ArenaCrowd` | 120 modelos `Spectator_*` (6 Part, 5 Motor6D, 1 Decal; **sin** Humanoid ni Animator) |
| `Workspace` | `OilWrestlingRing`, `Colosseum`, `BroadcastBooth`, `StadiumEnclosure` |
| `SoundService` | `MusicGroup` (0.35): LobbyMusic, BattleMusic · `SFXGroup` (0.85): Ambiente/Ronda/Combate/Resultado — **11 sonidos** |

Los nombres que los scripts de `src/client/` buscan por `WaitForChild` **existen todos**
en los ScreenGui: la reconstrucción de la interfaz no rompió ninguna referencia.

## 5. Lo que NO está conectado (revisado, no se tocó)

- **Los 11 sonidos no suenan**: `src/` no contiene ni una referencia a `Sound`. La biblioteca
  está preparada y bien organizada, pero ningún código la reproduce.
- **Tienda, cajas y skins no existen en el juego**: `CosmeticsShared`, `ShieldAbilities` y
  `OilBlockVFX` solo están en `ServerStorage.Respaldo_*`. Los botones del `ShopPanel` no
  tienen backend. Además esos módulos hacen `require` de cosas que no están: activarlos tal
  cual rompe el arranque.
- **Las 120 figuras del público son estáticas**: 0 objetos `Animation` en todo el lugar.

## 6. Cómo volver a verificar

El hash FNV en Luau **no** se puede calcular con `h = (h * 16777619) % 2^32`: en Luau los
números son dobles y el producto se pasa de 2^53, así que pierde precisión y da un hash
distinto para el mismo texto (parece que todos los archivos cambiaron a la vez). Hay que
multiplicar en trozos de 16 bits:

```lua
local function mul32(x, y)
	local xl, xh = x % 65536, (x - x % 65536) / 65536
	local yl, yh = y % 65536, (y - y % 65536) / 65536
	local ll = xl * yl
	local lh = xl * yh + xh * yl
	local hh = xh * yh
	return (ll + (lh % 65536) * 65536 + (hh % 65536) * 4294967296) % 4294967296
end
local function fnv(s)
	local h = 2166136261
	for i = 1, #s do
		h = bit32.bxor(h, string.byte(s, i))
		h = mul32(h, 16777619)
	end
	return h
end
```

En Python (mismo algoritmo, enteros de precisión arbitraria) para comparar contra los
archivos de `src/`:

```python
def fnv(data: bytes) -> int:
    h = 2166136261
    for b in data:
        h ^= b
        h = (h * 16777619) % 4294967296
    return h
```
