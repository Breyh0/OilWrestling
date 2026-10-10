"""Chequeo de referencias adelantadas en Luau.

Luau resuelve los nombres en tiempo de compilacion segun su posicion: si una funcion
usa un `local` declarado MAS ABAJO, no captura ese valor, lo busca como global (nil).
Este script recorren el archivo y avisa de esos casos.
"""
import re
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    lines = fh.read().split("\n")

decl = {}
for i, ln in enumerate(lines, start=1):
    m = re.match(r"\s*local function ([A-Za-z_][A-Za-z0-9_]*)", ln)
    if m:
        decl[m.group(1)] = i

print("--- declaraciones locales (%d) ---" % len(decl))
for k, v in sorted(decl.items(), key=lambda x: x[1]):
    print("  L%-4d %s" % (v, k))

print()
print("--- usos ANTES de su declaracion ---")
problemas = 0
for name, dline in sorted(decl.items(), key=lambda x: x[1]):
    patron = re.compile(r"(?<![\w.:])" + re.escape(name) + r"\s*\(")
    for i, ln in enumerate(lines, start=1):
        if i >= dline:
            break
        if re.match(r"\s*local function\s+" + re.escape(name) + r"\b", ln):
            continue
        if patron.search(ln):
            print("  %s: usado en L%d pero declarado en L%d" % (name, i, dline))
            print("      " + ln.strip()[:92])
            problemas += 1

if not problemas:
    print("  ninguno")
print()
print("lineas totales: %d" % len(lines))
