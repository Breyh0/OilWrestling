-- AUTOTEST de la regla "alfabeto" (ver docs/PREFLIGHT.md).
-- Este archivo TIENE un fallo a proposito: no lo arregles.
-- Motivo real (2026-10-10): se colaron ideogramas en comentarios tres veces en una
-- sesion. Compilan igual, no aparecen en el diff ni en la consola, y se descubren
-- cuando alguien mas lee el archivo.

-- Romper el equilibrio de este texto con ideogramas: 平衡 y кириллица
-- Lo de arriba deberia ser español normal.

local t = "flecha → y euro € y triangulo ▼"
return t
