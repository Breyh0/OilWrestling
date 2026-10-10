"""Autotest del preflight: comprueba que cada regla detecta SU fallo.

Por que existe: el 2026-10-10 una regla ("Instance%.new" en vez de "Instance\\.new")
no detectaba nada y no se noto hasta que se ejecuto contra un archivo con el bug real.
Una regla que nunca salta no vale nada, asi que cada una tiene su archivo de prueba y
este script lo comprueba de forma automatizada.

Uso:  python tools/preflight_selftest.py
Salida: 0 si todas las reglas detectan lo que deben, 1 si alguna ha dejado de funcionar.
"""
import subprocess
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
TESTS = Path(__file__).resolve().parent / "preflight_tests"

# archivo -> (numero minimo de problemas, reglas que deben aparecer)
ESPERADO = {
    "reservada.luau": (1, ["reservada"]),
    "adelantada.luau": (2, ["adelantada"]),
    "corchetes.luau": (2, ["corchetes", "bloques"]),
    "huerfana.luau": (1, ["huerfana"]),
    "alfabeto.luau": (1, ["alfabeto"]),
}

# src/, docs/ y las skills deben salir limpios: si el preflight llora de mas, el
# equipo deja de mirarlo y la puerta se vuelve decorativa.
LIMPIOS = ["src", "docs", ".opencode"]


def correr(*args):
    return subprocess.run(
        [sys.executable, str(RAIZ / "tools" / "lua_preflight.py"), *args],
        capture_output=True, text=True, encoding="utf-8", errors="replace", cwd=str(RAIZ),
    )


def main():
    fallos = 0
    print("== autotests: cada regla debe detectar su fallo ==")
    for nombre, (minimo, reglas) in ESPERADO.items():
        ruta = TESTS / nombre
        if not ruta.exists():
            print(f"  FALTA  {nombre}")
            fallos += 1
            continue
        r = correr(str(ruta))
        salida = r.stdout + r.stderr
        total = 0
        detalle = []
        bien = True
        for regla in reglas:
            cuenta = salida.count("[%s]" % regla)
            total += cuenta
            detalle.append(f"[{regla}]x{cuenta}")
            if cuenta < 1:
                bien = False
        # ademas, el numero total de problemas debe llegar al minimo
        for l in salida.split("\n"):
            if "problemas:" in l:
                total = max(total, int(l.split("problemas:")[1].strip()))
        bien = bien and total >= minimo and "problemas: 0" not in salida
        print(f"  {'OK   ' if bien else 'FALLA'} {nombre:22s} {' '.join(detalle)}  total={total} (min {minimo})")
        if not bien:
            fallos += 1
            print("        " + salida.strip().replace("\n", "\n        ")[:600])

    print()
    print("== el codigo real debe salir limpio ==")
    r = correr(*LIMPIOS)
    ultima = [l for l in r.stdout.strip().split("\n") if l.strip()][-1]
    bien = "problemas: 0" in ultima
    print(f"  {'OK   ' if bien else 'FALLA'} {' '.join(LIMPIOS)}: {ultima}")
    if not bien:
        fallos += 1
        for l in r.stdout.split("\n"):
            if "FALLA" in l or "[reservada]" in l or "[adelantada]" in l or "[huerfana]" in l:
                print("        " + l.strip())

    print()
    print("autotests:", "TODO OK" if fallos == 0 else f"{fallos} CON PROBLEMAS")
    sys.exit(1 if fallos else 0)


if __name__ == "__main__":
    main()
