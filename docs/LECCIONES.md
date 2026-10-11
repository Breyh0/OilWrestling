# Lecciones: errores que se repiten

Este documento es sobre **fallos míos** (de la IA del equipo), no sobre el juego. Está
escrito porque repetir un error porque se olvidó es peor que el error: lo escrito se
avisa, lo que está en la cabeza se pierde en la siguiente sesión.

Cada lección dice: **qué pasó**, **por qué** y **qué se hace ahora**. Las que tienen
herramienta son verificables, y por eso la regla se escribe para que no se vuelva a colar.

---

## 1. Se me colan ideogramas chinos en los archivos

**Qué pasó.** Seis veces en una tarde: ideogramas chinos y un texto coreano. Casi siempre
al final de un párrafo largo, en el punto donde ya estaba escribiendo la idea en español.
En cuatro casos compilaban igual (eran comentarios), así que **no se veían ni en el diff,
ni en Rojo, ni en la consola**. No se reproducen aquí a propósito: la puerta del preflight
los marca en cuanto aparecen, y un ejemplo copiado en la documentación la haría fallar a
ella sola. Los que se colaron están en el historial de git, en los commits afectados.

**Por qué.** Es un fallo de generación de texto, no de conocimiento. Pasa más cuanto más
largo es el texto y cuanto más cansado el contexto.

**Qué hay hecho.** El preflight tiene la regla `alfabeto`, que avisa de cualquier carácter
fuera del rango latino en `src/`, `docs/` y las skills:

```powershell
python tools\lua_preflight.py src docs .opencode
```

Funciona, y está en la CI. Dos veces me cazó a mí mismo en el mismo commit.

**Lo que el preflight NO pilla.** Palabras latinas corruptas: se me han colado cuatro o
cinco palabras que no son de ningún idioma (una con Initial mayúscula inventado, dos
fragmentos pegados al final de otra palabra, un verbo inexistente). La regla `alfabeto`
mira el **código del carácter**, no si la frase tiene sentido. Eso no lo automatiza nadie:
es justo el motivo de que la revisión humana antes de commitear siga siendo obligatoria.

**Dónde NO llega.** Y esto es lo importante:

| Sitio | ¿Lo pilla? |
|---|---|
| `.luau` y `.md` del repo | Sí, la CI lo bloquea |
| **Mensajes de commit** | **No** (uno de ellos llevaba ideogramas, que estuvieron semanas en el historial) |
| **Cuerpo de un PR** | **No** |
| **Mis respuestas en el chat** | **No** |

Esos tres los tiene que mirar una persona. Si ves caracteres raros en un commit o en un
PR, no son parte del juego: son míos.

**Cómo evitarlo.** Si un texto va a ser largo, se escribe corto y se revisa. Y cuando
vayas a pegarle a `git commit -m`, léelo antes de darle al enter: es el último sitio donde
se nota.

---

## 2. Repito el mismo proceso en vez de diagnosticar el fallo

**Qué pasó.** Varias veces, con lo mismo:

- La CI falló con `property/2 data matches no possible input`. Volví a mandar el mismo
  payload con un campo cambiado a ciegas **tres veces**, hasta que fui a la documentación
  y leí que faltaban campos `Required`.
- Un push fue rechazado y lo interpreté como "la protección no funciona". El motivo real
  era otro (`non-fast-forward`: mi `main` local estaba atrás). Repeaté la prueba con el
  mismo error en vez de leerlo.
- El `gsub` de la huella no ponía el número. Probé variantes del mismo `gsub`.

**Por qué.** Cuando algo falla, la inercia es a reintentar. Pero si el error es de
*validación* o de *sincronización*, reintentar sin leer es tiempo tirado: el resultado es
idéntico.

**Qué se hace ahora.**

| Tipo de fallo | Qué hacer |
|---|---|
| Validación de una API o de un esquema | Leer el mensaje: suelen venir los campos que faltan. O ir a la documentación. |
| Rechazo de git | Leer las tres líneas de abajo del error antes de interpretar nada. |
| Herramienta que devuelve `null` | Comprobar si tiene una versión anterior conocida que funcionó. Puede estar caída. |
| Fallo de sintaxis en Luau | `python tools\preflight.py <archivo>` antes de tocar nada más. |

Máximo **dos** reintentos con el mismo error. A la tercera, se cambia de estrategia: leer
la documentación, o medir antes de tocar.

---

## 3. Afirmo algo que no he comprobado

**Qué pasó.** Dos veces seguidas:

- Dije que con "Require status checks" la puerta de `main` quedaba cerrada. **Era
  falso**: los status checks no bloquean un `git push` directo. Lo demostraron dos pruebas
  de push y una llamada a la API. La regla que cierra la puerta es `pull_request`.
- Escribí en `docs/WORKFLOW.md` que `main` estaba protegida, en un commit que decía
  precisamente que no lo estaba. Tuve que corregirlo en el commit siguiente.

**Por qué.** Un advice razonado suena igual que uno verificado, y se escribe antes de
comprobar.

**Qué se hace ahora.** Nada de "queda hecho" sin una de estas dos cosas:

1. **Un comando que lo demuestra** (un push rechazado, un hash que coincide, una lectura
   de estado).
2. **La palabra "creo que"**, y una nota de lo que falta por verificar.

Es la misma regla que ya está en `lucha-qa` para el playtest, pero aplicada a lo que digo
yo sobre el repositorio.

---

## 4. Escribo código de una vez y lo depuro después

**Qué pasó.** Varios: escribo el archivo entero, lo ejecuto y luego lo corrijo. Con un
`swap` de operadores mal pegado, un `%.` donde iba `\.`, un `end` que faltaba, una tabla
declarada después de usarse. Funcionó porque el playtest y el preflight los cazaron, pero
hubo que corregir tres veces.

**Por qué.** Escribir de golpe es más rápido **si ya sabes la respuesta**. Aquí casi nunca
se sabe hasta ver el error.

**Qué se hace ahora.**

- Un cambio grande (archivo nuevo, función nueva) se ejecuta **antes** de seguir
  escribiendo.
- Lo que se pega en una herramienta se **lee después de pegar**, no antes.
- Las herramientas que ya existen se prueban con datos inventados antes de tocar el
  repo: el autotest del preflight nació de un `Instance%.new` que no detectaba nada y no
  me di cuenta hasta que lo ejecuté contra el bug real.

---

## 5. Detalles del entorno que cuestan tiempo

No son culpa del código, pero cada uno costó un viaje.

| Problema | Solución |
|---|---|
| Python escrito dentro de un comando de PowerShell con comillas escapadas | Escribirlo a un archivo y ejecutarlo. Siempre. |
| Comillas y `>` en mensajes de `git commit -m` | Sin comillas, sin `>` sin escapar. Leer el mensaje antes de confirmar. |
| `execute_luau` largos con muchos niveles | "Failed to parse command code". Dividir o aplanar el código. |
| Payloads grandes a `execute_luau` | Timeouts a partir de ~15 KB. Ir por partes. |
| Un `local` declarado más abajo | Preflight, regla `adelantada`. Le da `nil` en silencio, no error. |

---

## Cómo se usa este documento

Al empezar una sesión, leerlo **antes** de tocar nada. Y cuando pase algo de lo de aquí,
**añadirlo al final** con la fecha. Un documento de fallos que no crece es un documento
que ya no refleja la realidad.
