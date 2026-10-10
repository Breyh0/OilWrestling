"""Preflight de Luau para este repo.

No hay compilador de Luau disponible en la maquina, asi que estos tres fallos se
pillan leyendo el texto. Los tres han pasado de verdad:

  1. Palabra reservada usada como nombre (`lane = { until = 0 }` -> el script entero
     no compila y el juego se queda sin ese sonido, sin error visible en Rojo).
  2. Referencia adelantada: usar un `local` declarado mas abajo. Luau lo busca como
     global, o sea nil -> "attempt to call a nil value" en tiempo de ejecucion.
  3. Bloques sin cerrar.

Uso:  python tools/lua_preflight.py src/
      python tools/lua_preflight.py src/client/SoundDirector.client.luau
"""
import os
import re
import sys

RESERVED = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if",
    "in", "local", "nil", "not", "or", "repeat", "return", "then", "true", "until",
    "while",
}

BLOCK_OPEN = {"function", "if", "for", "while", "do", "repeat"}


def _blank(chunk):
    """Espacios pero respetando los saltos de linea: si no, se fusionan lineas."""
    return "".join("\n" if c == "\n" else " " for c in chunk)


def mask(lineas):
    """Sustituye comentarios y cadenas por espacios, conservando el numero de linea."""
    src = "\n".join(lineas)
    out = []
    i, n, quote = 0, len(src), None
    while i < n:
        c = src[i]
        if quote:
            if c == "\\":
                i += 2
                continue
            if c == quote:
                quote = None
            out.append(" ")
            i += 1
            continue
        if src.startswith("--[[", i) or src.startswith("[[", i):
            fin = src.find("]]", i)
            fin = n if fin < 0 else fin
            out.append(_blank(src[i:fin]))
            i = fin
            continue
        if src.startswith("--", i):
            fin = src.find("\n", i)
            fin = n if fin < 0 else fin
            out.append(_blank(src[i:fin]))
            i = fin
            continue
        if c in "\"'":
            quote = c
            out.append(" ")
            i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out).split("\n"), quote


def rev_reservadas(masc):
    fallos = []
    for num, ln in enumerate(masc, start=1):
        for w in RESERVED:
            if re.search(r"\.\s*" + w + r"\b", ln):
                fallos.append((num, "miembro '.' + palabra reservada '%s'" % w, ln))
            if re.search(r"(?<![\w.])" + w + r"\s*=[^=]", ln):
                fallos.append((num, "asignacion a palabra reservada '%s'" % w, ln))
            # 'local function f()' es sintaxis valida: 'function' queda fuera a proposito.
            if w != "function" and re.search(r"\blocal\s+" + w + r"\b", ln):
                fallos.append((num, "'local' con palabra reservada '%s'" % w, ln))
            if re.search(r"(?<![\w.])function\s+" + w + r"\s*[\(\.]", ln):
                fallos.append((num, "'function' con palabra reservada '%s'" % w, ln))
    return fallos


def rev_bloques(masc):
    pila = []
    for num, ln in enumerate(masc, start=1):
        loop = False
        for tok in re.finditer(r"\b(function|if|for|while|do|end|repeat|until)\b", ln):
            t = tok.group(1)
            if t in ("for", "while"):
                loop = True
                pila.append((t, num))
            elif t == "do":
                if not loop:
                    pila.append((t, num))
            elif t in ("function", "if", "repeat"):
                pila.append((t, num))
            elif t == "end":
                if pila:
                    pila.pop()
                else:
                    return [(num, "'end' sobrante", ln)]
            elif t == "until":
                if pila and pila[-1][0] == "repeat":
                    pila.pop()
    return [(n, "bloque sin cerrar: %s" % t, "") for t, n in pila]


def rev_adelantadas(masc):
    """Un `local` usado antes de su declaracion.

    Dos variantes, ambasOccurred el 2026-10-10:
      - llamadas:  `pushMusic` llama a `fadeTo` declarado mas abajo -> nil en runtime.
      - valores:   `maxSeconds = VICTORY_MAX` con VICTORY_MAX declarado mas abajo ->
                   vale nil EN SILENCIO (leer no da error), asi que la funcionality
                   simplemente no existe y no se nota hasta que se ve en juego.

    Se ignoran los miembros (`.campo`) porque esos no son el local.
    """
    decl = {}
    repetidos = set()
    for i, ln in enumerate(masc, start=1):
        m = re.match(r"\s*local function ([A-Za-z_][A-Za-z0-9_]*)", ln)
        if m:
            nombres = [m.group(1)]
        else:
            # Incluye declaraciones multiples: "local a, b = x, y"
            m = re.match(r"\s*local\s+([A-Za-z_][\w,\s]*?)\s*(=[^=]|$)", ln)
            if not m:
                continue
            nombres = [n.strip() for n in m.group(1).split(",") if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", n.strip())]
        for nombre in nombres:
            if nombre in decl:
                repetidos.add(nombre)  # se reutiliza el nombre: no se puede juzgar
            else:
                decl[nombre] = i

    # Nombres que ademas son parametros de funcion o variables de bucle en otro
    # ambito: son locales distintos y el analisis de ambitos seria de mas.
    texto = "\n".join(masc)
    ocultos = set()
    for params in re.findall(r"function[^\n(]*\(([^)]*)\)", texto):
        for p in params.split(","):
            p = p.strip()
            if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", p):
                ocultos.add(p)
    for grupo in re.findall(r"\bfor\s+([A-Za-z_][\w,\s]*?)\s+(?:in\b|=)", texto):
        for v in grupo.split(","):
            v = v.strip()
            if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", v):
                ocultos.add(v)

    fallos = []
    for name, dline in decl.items():
        if name in repetidos or name in ocultos:
            continue
        # miembro -> no cuenta; llamada o valor -> cuenta
        patron = re.compile(r"(?<![\w.:])" + re.escape(name) + r"(?![\w])")
        for i, ln in enumerate(masc, start=1):
            if i >= dline:
                break
            if re.match(r"\s*local (function )?" + re.escape(name) + r"\b", ln):
                continue
            if patron.search(ln):
                m = patron.search(ln)
                # "clave = valor" dentro de una tabla no es un uso del local: es el
                # nombre de un campo. Se descarta por ahi, o se llora con cada mapa.
                if re.match(r"\s*=[^=]", ln[m.end():]):
                    continue
                es_llamada = bool(re.search(r"(?<![\w.:])" + re.escape(name) + r"\s*\(", ln))
                fallos.append((i, "'%s' se usa %s antes de declararse (L%d)"
                               % (name, "llamando" if es_llamada else "como valor", dline), ln))
    return fallos


def rev_sintaxis_de_tabla(masc):
    """Detecta `f({ ... })` con la llave pegada, estilo `hold = 0.6}` sin espacio."""
    fallos = []
    for num, ln in enumerate(masc, start=1):
        for m in re.finditer(r"[%w_]\s*}", ln):
            ctx = ln[max(0, m.start() - 12):m.end() + 2]
            if re.search(r"[%w_]\s*}$", ln.strip()) and "=" not in ctx:
                fallos.append((num, "sospecha de llave pegada a un valor", ctx))
                break
    return fallos


def rev_corchetes(masc):
    """Balance de () {} [] sobre el archivo entero (las tablas multilinea son normales).
    Avisa de un cierre sin apertura y de aperturas que nunca cierran."""
    pares = {")": "(", "}": "{", "]": "["}
    pila = []
    linea = 1
    fallos = []
    for ch in "".join(masc):
        if ch == "\n":
            linea += 1
        elif ch in "({[":
            pila.append((ch, linea))
        elif ch in ")}]":
            if not pila:
                fallos.append((linea, "cierre '%s' sin apertura" % ch, ""))
            elif pila[-1][0] != pares[ch]:
                fallos.append((linea, "se cierra '%s' pero estaba abierto '%s' (L%d)" % (ch, pila[-1][0], pila[-1][1]), ""))
                pila.pop()
            else:
                pila.pop()
    for ch, ln in pila:
        fallos.append((ln, "abre '%s' y nunca cierra" % ch, ""))
    return fallos


def rev_huerfanas(masc):
    """Instance.new() asignado a un local al que nunca se le pone .Parent en NINGUN sitio.

    Asi se colaron los sonidos 3D: el clon colgaba de un Attachment que nunca se
    parento, asi que quedaba fuera del DataModel. Sin Parent no suena y no sale en
    ningun GetDescendants(), y tampoco da error: el fallo es invisible.
    Heuristica: si otro local del mismo nombre recibe .Parent en el archivo, no se
    avisa (falso negativo posible; a cambio no llora con el codigo normal).
    """
    texto = "\n".join(masc)
    fallos = []
    vistos = set()
    for num, ln in enumerate(masc, start=1):
        m = re.match(r"\s*local ([A-Za-z_][A-Za-z0-9_]*) = Instance\.new", ln)
        if not m:
            continue
        nombre = m.group(1)
        if nombre in vistos:
            continue
        vistos.add(nombre)
        if re.search(r"(?<![\w.])" + re.escape(nombre) + r"\.Parent", texto):
            continue
        # Solo es sospechoso si se usa como hijo de otra cosa ("algo = nombre").
        # El lookahead rechaza metodos ("= v.Changed") y solo acepta "= v" a secas.
        # Un NumberValue suelto que se tweeniza y se destruye a mano es legal.
        if re.search(r"=\s*" + re.escape(nombre) + r"(?![\w.])", texto):
            pass
        else:
            continue
        # Si el mismo nombre se usa como variable de bucle en otro sitio ("for k, v in"),
        # el "= v" que hemos visto no es este objeto: no se avisa para no llorar.
        if re.search(r"\bfor\b[^\n=]*\b" + re.escape(nombre) + r"\b[^\n=]*\bin\b", texto):
            continue
        fallos.append((num, "orphan", ln))
    return fallos


def rev_alfabeto(lineas):
    """Caracteres de alfabetos que no son el nuestro.

    En un archivo con tildes y eñes se cuelan ideogramas, cirilico o japones sin que
    se note en el diff: compila igual, asi que el preflight es el unico que lo ve.
    Se permiten los simbolos de UI (formas geometricas U+2500-U+27BF, grados, flechas,
    comillas tipograficas, monedas): esos son intencionados y no delatan un idioma.
    """
    permitidos = set("°·—–…“”„«»¡¿€$£¥•⇒")
    fallos = []
    for num, ln in enumerate(lineas, start=1):
        malos = sorted({
            c for c in ln
            if ord(c) > 0x2500 and c not in permitidos and not (0x2500 <= ord(c) <= 0x27BF)
        })
        if malos:
            fallos.append((num, "alfabeto: %s" % " ".join("%s(U+%04X)" % (c, ord(c)) for c in malos),
                           ln.strip()[:80]))
    return fallos


def comprobar(path):
    with open(path, encoding="utf-8-sig") as fh:
        lineas = fh.read().split("\n")
    masc, quote = mask(lineas)
    problemas = []
    if quote:
        problemas.append((0, "cadena sin cerrar (%s)" % quote, ""))
    for etiqueta, lista in (
        ("reservada", rev_reservadas(masc)),
        ("bloques", rev_bloques(masc)),
        ("corchetes", rev_corchetes(masc)),
        ("adelantada", rev_adelantadas(masc)),
        ("huerfana", rev_huerfanas(masc)),
        ("alfabeto", rev_alfabeto(lineas)),
    ):
        for num, msg, ln in lista:
            problemas.append((num, "[%s] %s" % (etiqueta, msg), ln.strip()[:88]))
    return problemas, len(lineas)


def main():
    try:
        sys.stdout.reconfigure(errors="replace")
    except Exception:
        pass

    objetivos = []
    for arg in sys.argv[1:]:
        if os.path.isdir(arg):
            for raiz, _, archivos in os.walk(arg):
                for a in archivos:
                    if a.endswith(".luau"):
                        objetivos.append(os.path.join(raiz, a))
        else:
            objetivos.append(arg)

    total = 0
    for path in sorted(objetivos):
        problemas, nlineas = comprobar(path)
        if problemas:
            print("FALLA  %s  (%d lineas)" % (path, nlineas))
            for num, msg, ln in problemas:
                print("   L%-4d %s" % (num, msg))
                if ln:
                    print("          %s" % ln)
            total += len(problemas)
        else:
            print("OK     %s  (%d lineas)" % (path, nlineas))
    print()
    print("archivos: %d | problemas: %d" % (len(objetivos), total))
    sys.exit(1 if total else 0)


if __name__ == "__main__":
    main()
