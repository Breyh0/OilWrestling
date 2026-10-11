"""Comprueba la huella del manifiesto de escena.

No se fia de Studio: recalcula el FNV-1a de 32 sobre el propio .md y lo compara con
la huella declarada. Si alguien edita el manifiesto a mano y no actualiza la huella,
esto lo dice.

Uso:  python tools/verificar_escena.py
"""
import re
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
MANIFESTO = RAIZ / "escena" / "MANIFIEST-ESCENA.md"
MARCA = "(se calcula al final)"


def fnv(data: bytes) -> int:
    h = 2166136261
    for b in data:
        h ^= b
        h = (h * 16777619) % 4294967296
    return h


def main() -> int:
    if not MANIFESTO.exists():
        print(f"ERROR: no existe {MANIFESTO}")
        return 1

    texto = MANIFESTO.read_text(encoding="utf-8")
    m = re.search(r"^Huella: `(\d+)`$", texto, re.M)
    if not m:
        print("ERROR: el manifiesto no tiene una linea 'Huella: `<numero>`'")
        return 1
    declarada = int(m.group(1))

    # La huella se calcula sobre el documento con la linea de la huella en su marcador.
    limpio = texto.replace(f"Huella: `{declarada}`", f"Huella: {MARCA}")
    calculada = fnv(limpio.encode("utf-8"))

    print(f"declarada : {declarada}")
    print(f"calculada : {calculada}")
    if declarada == calculada:
        print("OK: el manifiesto esta intacto")
        return 0
    print("AVISO: la huella no cuadra. El manifiesto se edito a mano sin regenerarlo.")
    print("        Regeneralo con escena/inventario.luau y commit el resultado.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
