# Setup — nueva máquina / nuevo dev

Requisitos: Windows 10+, **Roblox Studio** actualizado, **git**, y tu IA (**opencode** o **Claude Desktop**).

## 1. Clone el repo

```sh
git clone https://github.com/Breyh0/OilWrestling.git C:\dev\LuchaDeAceite
cd C:\dev\LuchaDeAceite
git config --global user.name  "TuNombre"
git config --global user.email "tu@email"
```

## 2. Instala Rojo (sync archivos ⇄ Studio)

1. Descarga el `.zip` de Windows de la última release: <https://github.com/rojo-rbx/rojo/releases>
2. Extrae `rojo.exe` a una carpeta que esté en el PATH (ej. `C:\dev\bin`).
3. Verifica: `rojo --version`
4. Instala el plugin de Studio (una sola vez): `rojo plugin install`
5. **En el día a día**: doble clic en **`iniciar-rojo.bat`** (raíz del repo) — equivale a `rojo serve` y deja la ventana lista. Mantenerla abierta mientras se programa.

## 3. Roblox Studio

1. Abre el place por **Team Create** (el place es del grupo **Kyubu Studio**, propietario supergamertth8 — debe aparecer en tus places compartidos).
2. Con `rojo serve` corriendo en una terminal de la carpeta del repo: en Studio → plugin **Rojo → Connect**. Los scripts de Studio ahora son una **vista** de `src/`.

## 4. Conecta tu IA (Studio MCP)

1. En Studio: **Assistant → … → Manage MCP Servers → Enable Studio as MCP server** (indicador verde).
2. **opencode**: el repo ya trae `opencode.json` con el server `roblox-studio` — abre opencode dentro de `C:\dev\LuchaDeAceite` y ya estará.
3. **Claude Desktop**: añade a `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "Roblox_Studio": {
      "command": "cmd.exe",
      "args": ["/c", "%LOCALAPPDATA%\\Roblox\\mcp.bat"]
    }
  }
}
```

4. Verifica desde tu IA: listar los estudios conectados debe devolver el place "Lucha de aceite".

## 5. Reglas del equipo (resumen)

1. `git pull` antes de empezar · `git push` al terminar.
2. **Código solo en archivos** (editor o IA) — nunca en el editor de scripts de Studio.
3. **Escena/GUI solo en Studio** — nunca vía archivos.
4. Mantén `rojo serve` abierto mientras programas.
5. Lee `docs/MEMORY.md` antes de tocar cualquier cosa.
