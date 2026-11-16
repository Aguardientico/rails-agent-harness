# rails_agent_harness

Instala instrucciones, la skill `rails-review` y verificaciones para agentes que
trabajan en Rails. El único verificador es `bin/agent-check`.

```sh
bundle add rails_agent_harness --group development
bin/rails g agent_harness:install
bin/agent-check verify-install
bin/agent-check
```

| Cliente | Nivel instalado |
|---|---|
| Claude Code | Instrucciones, skill; guardia antes de editar, lint después y Stop bloqueante |
| Codex CLI | AGENTS.md, skill; PreToolUse lee parches apply_patch (incluidos movimientos), lint posterior y Stop bloqueante |
| Copilot VS Code (harness Copilot), CLI y coding agent de GitHub | Instrucciones y skill nativas; preToolUse, postToolUse y agentStop con respuestas JSON propias |
| Cursor Agent | AGENTS.md y skill; guardia preToolUse, lint diagnóstico tras editar y comprobación completa con un mensaje de continuación en stop |
| Gemini CLI | GEMINI.md y skill; BeforeTool, AfterTool y AfterAgent con rechazo y realimentación |
| Cline y Roo Code | Reglas y skill; sin adaptadores de hooks instalados |
| Amp y Windsurf / Devin Local actual | AGENTS.md y skill compartida; sin adaptadores de hooks instalados |
| Junie CLI / IDE | Skill en `.junie` y guías en AGENTS.md (actualiza `.junie/AGENTS.md` solo si existe); sin adaptador de hooks |
| JetBrains AI Assistant | Reglas; seleccionar Always en el IDE y comprobar que se adjuntan |
| Aider | `aider --config .aider.agent-harness.yml`: carga AGENTS.md y ejecuta bin/agent-check como auto-test después de editar |

Revisa y confía en el proyecto, y aprueba los hooks en cada cliente cuando lo
requiera. Codex exige confianza en sus hooks por separado; el generador no los
aprueba. Copilot también importa configuraciones de Claude; los comandos generados de
Claude solo se ejecutan cuando existe CLAUDE_PROJECT_DIR. En VS Code selecciona el harness Copilot: no se instala el formato del
antiguo agente Local. Inicia los clientes en la raíz de la aplicación Rails.
Claude conserva la salvedad de CLAUDE.md: si ya existe, importa AGENTS.md desde él.

El coding agent requiere Ruby, bundle (incluida esta gema de desarrollo), linters
y base de pruebas preparados en su entorno; configura los
[setup steps oficiales](https://docs.github.com/en/copilot/how-tos/copilot-coding-agent/customizing-the-development-environment-for-copilot-coding-agent).
Las sesiones remotas necesitan los archivos de proyecto y dependencias allí.

Las garantías son distintas: los hooks previos cubren herramientas de archivos
reconocidas, no escrituras por shell, cualquier MCP ni todas las rutas del editor.
Cursor solo muestra el lint posterior como diagnóstico; su hook stop devuelve los
fallos al agente. Sus versiones antiguas sin preToolUse solo detectan después.
Las comprobaciones de migraciones son heurísticas y no demuestran que se usó el
generador. Los hooks permiten terminar tras un reintento para evitar bucles;
`bin/agent-check` en CI sigue siendo la barrera final.

Hay una sola plantilla de SKILL.md y un manifiesto de clientes fuera de ella.
El instalador conserva instrucciones propias y mezcla hooks sin eliminar los
existentes. `--skip-client-hooks` omite los hooks nuevos; `--skip-claude-hooks`
omite los de Claude; `--skip-skills` omite todas las skills. `--force-client-files` reemplaza skills y la configuración generada de Aider sin
restablecer config/agent_harness.yml. `--force` también restablece ese archivo.

El instalador verifica sus archivos al terminar. `bin/agent-check verify-install`
comprueba skills y bloques administrados con SHA-256, y la presencia de comandos
de hooks. Permite cambiar ajustes del cliente, configuración del verificador y
texto propio fuera de los bloques, sin copiar configuraciones existentes. Una skill editada se conserva y la instalación falla
hasta reconciliarla. JSON inválido o con comentarios se conserva y se informa
como error. La verificación no demuestra que un cliente haya aprobado/cargado sus
hooks. No se instala un servidor MCP: ofrecer una herramienta no obliga a usarla.

La suite prueba contratos de entrada/salida documentados y la instalación desde
la gema empaquetada. No se afirma una certificación con sesiones autenticadas de
todos los clientes. Consulta [fuentes oficiales y límites](docs/agent-clients.md),
el [README en inglés](README.md) y su configuración detallada.
