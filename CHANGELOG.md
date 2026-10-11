# Changelog

Versiones del juego. El número va en el tag de git (`v0.4.0`) y en la publicación del
place.

Formato: `[añadido]` · `[cambiado]` · `[arreglado]` · `[quitado]`, en una línea, escrito
desde el punto de vista de quien juega.

---

## [v0.4.0] — sistema de sonido

**Añadido**
- Los 11 sonidos de `SoundService` suenan por primera vez: música de lobby y de batalla,
  ambiente de público, cuenta atrás, silbato, rugido, salpicaduras, impactos y fanfarria.
- Los impactos, la esquiva, la embestida y el lanzamiento **suenan en 3D**: se oyen de
  dónde vienen.

**Arreglado**
- La fanfarria de victoria sonaba repetida (el servidor anuncia el final una vez por
  segundo) y se arrastraba al menú.

**Nota técnica**
- `SoundDirector` es aditivo: escucha eventos que el servidor ya emitía. No toca
  `OilCombat` ni ningún otro archivo, así que se puede borrar sin más.

---

## [v0.3.0] — núcleo de combate y animación

**Añadido**
- Segundo movimiento en la animación (follow-through): hombros, codos y cuello persiguen
  al torso con retardo y rebotan. Es lo que hace que los golpes tengan peso.
- Remates por tipo de estado: los golpes entran rápido y salen despacio.

**Arreglado**
- Embestidas y agarres que actuaban contra el combate siguiente.
- Cargas que bloqueaban el hilo del servidor.
- La partida se quedaba colgada si el combate petaba.

---

## [v0.2.0] — progresión

**Añadido**
- XP, niveles, monedas, misiones diarias y semanales, rachas y bono de primera victoria.
- Panel de progreso en el lobby, con la columna fija a la izquierda para que el menú no
  salte al abrir un submenú.

---

## [v0.1.0] — base jugable

**Añadido**
- Ring-out, primero a 3 puntos. Modo solitario contra IA y multijugador hasta 4.
- Física de aceite, HUD de combate, marcador de rondas, menú y pantalla de carga.

---

## Cómo se publica una versión

1. Rama de feature verificada, mergeada a `main` con `--no-ff`.
2. `46/46 tests` + preflight + playtest + visto bueno del usuario.
3. **Publicar el place** en Studio (Ctrl+S). Sin esto, la escena no existe.
4. Tag: `git tag -a v0.5.0 -m "..." && git push --tags`
5. Anotar aquí arriba qué se publica.

El punto 3 es el que se olvida. La escena y la GUI **no están en git**: sin publicar, el
cambio solo existe en tu Studio.

- scene: inventario de escena versionado con huella, para vigilar la capa que no esta en git

