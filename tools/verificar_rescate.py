"""Verifica que una copia rescatada sea identica byte a byte al script del lugar.

Compara el hash FNV-1a de 32 bits y el numero de bytes contra lo que se registro en el
checkpoint. Si no coinciden, la copia NO es fiable y hay que volver a extraerla.

Uso:
    python tools/verificar_rescate.py checkpoint/2026-10-11-escudos
"""
import sys
from pathlib import Path

# Lo que se registro del lugar el 2026-10-10 y el 2026-10-11.
# ruta relativa dentro de la carpeta del checkpoint -> (FNV, bytes)
ESPERADO = {
    "ServerStorage.Respaldo_Habilidades_Escudos/ShieldAbilities_original.luau": (3684004711, 9489),
    "ServerStorage.Respaldo_Habilidades_Escudos/ShieldAbilities_Test_original.luau": (2089202569, 5284),
    "ServerStorage.Respaldo_Tienda_Cajas/OilBlockVFX_original.luau": (3743230225, 19140),
    "ServerStorage.Respaldo_Tienda_Cajas/CosmeticsShared_original.luau": (825101627, 3331),
    # La otra mitad de la tienda, rescatada el mismo 2026-10-11
    "ServerStorage.Respaldo_Tienda_Cajas/ProgressionLogic_original.luau": (220074352, 12990),
    "ServerStorage.Respaldo_Tienda_Cajas/ProgressionService_original.luau": (1575331139, 14421),
    "ServerStorage.Respaldo_Tienda_Cajas/MainMenuClient_original.luau": (2341815890, 16573),
    "ServerStorage.Respaldo_UI_Progresion.ProgressionUI_anterior/ProgressionClient.luau": (1474751144, 1111),
    "ServerStorage.Respaldo_Habilidades_Escudos/OilCombat_original.luau": (1511816891, 50433),
}


def fnv(data: bytes) -> int:
    """FNV-1a de 32 bits. En Python los enteros no tienen limite, asi que aqui el
    producto de 16777619 nunca se pasa de 2^53 y el hash es correcto. En Luau hay que
    multiplicar en trozos de 16 bits."""
    h = 2166136261
    for b in data:
        h ^= b
        h = (h * 16777619) % 4294967296
    return h


def buscar(raices, relativa):
    """Un archivo puede estar en cualquiera de los checkpoints. Por eso se buscan en
    todos en vez de asumir uno solo: CosmeticsShared_original se rescato el 2026-10-10
    y los escudos el 2026-10-11."""
    for raiz in raices:
        ruta = raiz / relativa
        if ruta.is_file():
            return ruta
    return None


def main() -> int:
    if len(sys.argv) < 2:
        print("uso: python tools/verificar_rescate.py <carpeta del checkpoint> [otra...]")
        return 2
    raices = [Path(a) for a in sys.argv[1:]]
    for raiz in raices:
        if not raiz.is_dir():
            print(f"no existe la carpeta: {raiz}")
            return 2

    fallos = 0
    ausentes = 0
    for relativa, (hash_esperado, bytes_esperados) in sorted(ESPERADO.items()):
        ruta = buscar(raices, relativa)
        if ruta is None:
            ausentes += 1
            print(f"AUSENTE   {relativa}")
            print(f"         todavia sin rescatar (FNV {hash_esperado}, {bytes_esperados} bytes)")
            continue
        datos = ruta.read_bytes()
        hash_real = fnv(datos)
        ok = hash_real == hash_esperado and len(datos) == bytes_esperados
        estado = "OK      " if ok else "NO COINCIDE"
        if not ok:
            fallos += 1
        donde = "" if ruta.parent == raices[0] else "  (en %s)" % ruta.parent.name
        print(f"{estado} {relativa}{donde}")
        print(f"         FNV esperado {hash_esperado} | real {hash_real}")
        print(f"         bytes esperados {bytes_esperados} | reales {len(datos)}")

    rescatados = len(ESPERADO) - ausentes - fallos
    print()
    print(f"rescatados y verificados: {rescatados} de {len(ESPERADO)}")
    if ausentes:
        print(f"aun sin rescatar: {ausentes} (el rescate sigue en curso, no es un fallo)")
    if fallos:
        print(f"FALLAN {fallos}: esas copias NO son fiables, hay que volver a extraerlas")
        return 1
    print("ninguna copia rescatada esta corrupta")
    return 0


if __name__ == "__main__":
    sys.exit(main())