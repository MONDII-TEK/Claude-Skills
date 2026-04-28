# Commands reference — sintaxis completa

Tabla canónica de los triggers de la skill `testing-orchestration` con sintaxis exacta, ejemplos y comportamiento ante args inválidos.

## 1. Slash commands explícitos (control determinista — el usuario teclea)

| Slash | Argumentos (`$ARGUMENTS`) | Workflow | Comportamiento sin args / args inválidos | Ejemplo |
|---|---|---|---|---|
| `/testing-orchestration` | (ninguno) | Carga skill | Carga la skill, queda activa para la sesión | `/testing-orchestration` |
| `/testing-orchestration design <título>` | título corto del feature/fix | **G** plan-guardian | Sin título → la skill pregunta *"¿título corto del feature/fix?"* y espera | `/testing-orchestration design freeze membership feature` |
| `/testing-orchestration run <test:cmd>` | comando completo `test:*` con flags | **C** run + audit | Sin cmd → menú con `test:unit / test:module / test:api / test:bg / test:stripe / test:full`. cmd inválido → error con sugerencia | `/testing-orchestration run test:module roles_api -c` |
| `/testing-orchestration restart-dev` | (ninguno) | **A** down + build:dev + up:dev + smoke | Args extra → ignorados | `/testing-orchestration restart-dev` |
| `/testing-orchestration restart-test` | (ninguno) | **B** test:clean + build:test | Args extra → ignorados | `/testing-orchestration restart-test` |
| `/testing-orchestration affected` | (ninguno; lee `git diff`) | **E** detect tests afectados | Si `git status` limpio → reporta "sin cambios"; si fuera de repo git → error claro | `/testing-orchestration affected` |
| `/testing-orchestration manual <feature>` | nombre/descripción del flujo | **F** manual UI test | Sin feature → pregunta *"¿qué flujo validar?"* | `/testing-orchestration manual switch policy next_renewal` |
| `/testing-orchestration audit <run-dir>` | path al run dir | Audit standalone | Sin path → lista los últimos 5 run dirs en `logs/test_runs/` y deja elegir. Path inexistente → error + sugerencia `/testing-orchestration status` | `/testing-orchestration audit logs/test_runs/20260428T120000Z_test_full/` |
| `/testing-orchestration validate-migrations` | (ninguno) | **H** valida Alembic IDs | Args extra → ignorados | `/testing-orchestration validate-migrations` |
| `/testing-orchestration status` | (ninguno) | **I** sprint status report | Args extra → ignorados | `/testing-orchestration status` |
| `/testing-orchestration self-check` | (ninguno) | **K** self-check adopción | Args extra → ignorados | `/testing-orchestration self-check` |

**Nota sobre sintaxis de args**: todos los slash usan `$ARGUMENTS` (string único) — el SKILL.md/workflows.md interpretan el contenido contextualmente. `$0`/`$1`/named arguments queda reservado para futuros casos posicionales rígidos.

## 2. Auto-trigger (modelo decide — sin teclear)

### 2.a. Por description match (frase libre del usuario)

El modelo carga la skill cuando matchea `when_to_use:` del frontmatter contra el prompt del usuario. Frases gatillo:

| Categoría | Frases típicas | Workflow |
|---|---|---|
| Diseño feature/fix | *"voy a añadir feature X"*, *"diseñemos plan para Y"*, *"vamos a refactorizar Z"* | G |
| Restart stacks | *"down y rebuild dev"*, *"restart completo"*, *"reset test"* | A / B |
| Run tests | *"lanza test:stripe lifecycle_paths"*, *"corre suite full"*, *"test:module roles_api"* | C |
| Detección tests | *"qué tests cubren este cambio"*, *"qué tests están afectados"* | E |
| Manual UI | *"verificación manual"*, *"prueba desde UI"*, *"test manual"* | F |
| Regression loop | *"el test sigue rojo, intentemos otro fix"*, *"fix and re-run"* | D |
| Migrations | *"valida migraciones"*, *"comprueba migration IDs"* | H |
| Status | *"report del sprint"*, *"estado del testing"* | I |
| i18n | *"actualiza i18n"*, *"añade traducción"*, *"i18n missing locale"* | J |

### 2.b. Por path match (filesystem)

La skill se carga automáticamente cuando el archivo abierto/editado matchea uno de los `paths:` del frontmatter:

> **Nota**: los paths de la tabla espejan los `paths:` del frontmatter — el contrato concreto se declara en `CLAUDE.md` del proyecto. Al portar la skill, sustituir las variables `{{backend_path}}`, `{{locales_path}}`, `{{migrations_path}}` por los paths reales del proyecto destino (consultar `CLAUDE.md` y, si se referencia, `ARCHITECTURE.md`). La sustitución se hace **una sola vez** al editar el frontmatter — esta tabla es documentación de referencia, no contrato ejecutable.

| Path matcheado | Workflow latente | Acción |
|---|---|---|
| `{{backend_path}}/services/<svc>.py`, `{{backend_path}}/routes/<r>.py`, `{{backend_path}}/repositories/<r>.py` | G + E | Si no hay plan G activo, propone diseño; siempre lista tests afectados |
| `{{backend_path}}/models.py` | E + alerta | Lista tests + alerta migración + checklist model change del peer doc |
| `{{backend_path}}/tests/<…>` | C silencioso | Sugiere `test:module/test:api` del archivo editado |
| `{{migrations_path}}/*.py` | H | Sugiere `validate_migrations.sh` |
| `{{locales_path}}/**/*.json` (si el proyecto tiene i18n) | J | Check N locales dinámicos + cross-check user manual + tests |
| `logs/test_runs/<ts>/<archivo>` | Audit retroactivo | Ofrece análisis del run dir |

**Eliminados explícitamente** del auto-trigger por path (decisiones de diseño que aplican al portar la skill a cualquier proyecto):
- Scripts del orquestador (`scripts/<orquestador>` y similares): auto-trigger es ruido; el sync check vive en workflow B/I.
- Bug tracker (`{{bug_tracker_active}}`, `{{bug_tracker_history}}`): auto-trigger ruido cuando solo se lee; las acciones explícitas (abrir/cerrar bug) se cubren por description triggers vía allowed-tools `Edit Write`.
- Frontend puro (en IronVolt: `client/src/**`; en otros proyectos: `frontend/src/**`, `app/**`, etc. — sustituir según `{{frontend_path}}`): no requiere orquestación de tests; cubierto solo si toca i18n (workflow J) o si el usuario anuncia feature (workflow G).
- Mobile (en IronVolt: `mobile/**`; sustituir según el layout del proyecto): la skill es agnóstica de la rama mobile.

## 3. Pre-flight invariants (chequeos internos antes de cualquier `test:*`)

Estos no son triggers que el usuario invoque; son verificaciones que ejecuta workflow B/C/D antes de cada run. Documentados aquí para transparencia, no como comandos a teclear.

| Invariant | Workflow que lo ejecuta | Acción |
|---|---|---|
| Anti-colisión | C, B, D | Detecta `<proyecto>_test-(backend-run\|<sidecar>)` activos → aborta o limpia |
| Image freshness check | C, B, D | Compara content hash del código backend (path declarado en `CLAUDE.md`, parametrizado via `BACKEND_PATH`) vs imagen test → rebuild si stale, aviso si `--no-build` explícito |
| Sync check scripts repo ↔ skill | B, I | Diff entre `scripts/<x>` (repo) y `skills/testing-orchestration/scripts/<x>` (skill) → warning si difieren (la primera defensa es el pre-commit hook) |

## 4. Mantenimiento (modificación de archivos por la skill)

| Trigger | Acción de la skill (vía Edit/Write allowed-tools) |
|---|---|
| *"abrir bug X"* / detectado fallo no transitorio | Añade entrada en `{{bug_tracker_active}}` siguiendo §1 de [bug-tracker-template.md](bug-tracker-template.md) |
| *"cerrar bug Y"* / fix mergeado | Mueve entrada del activo a `{{bug_tracker_history}}` siguiendo §2 de la plantilla, en mismo commit que el fix (operación cohesiva, atomicidad delegada a git) |
| *"marcar xfail/stripe_heavy/stripe_flaky/bg_flaky"* | Aplica reglas §10/§14 de [policies.md](policies.md) (proceso, comentarios, ETA) |
| Cierre de sprint con aprendizaje nuevo de testing | Propone update al doc de políticas vivo del proyecto (en IronVolt: `docs/analysis/053_testing_guide_and_stripe_paths.md`) |

## 5. Comandos `manage.sh test:*` que la skill orquesta

### Build & lifecycle

| Comando | Función |
|---|---|
| `test:build` | Build imagen test-backend (cache activo) |
| `test:build --no-cache` | Idem forzando no-cache (tras cambio deps) |
| `test:up` | Arranca solo `db-test` (no corre tests) |
| `test:down` | Para y elimina `db-test` |

### Ejecución

| Comando | Función |
|---|---|
| `test:unit` | Unit tests (sin Docker, rápidos) |
| `test:api` | API / integration tests (con DB test real) |
| `test:bg` | Background task tests |
| `test:stripe` | Stripe integration con sidecar (todos los modules) — si el proyecto tiene Stripe |
| `test:stripe <module>` | Subset bajo `tests/test_stripe/` |
| `test:module <mod>` | Módulo individual de `tests/test_api/` o `tests/test_services/` |
| `test:full` (alias `test:all`, `test:todos`) | Suite completa multi-fase con failfast inter-fase |

### Flags comunes (todos los `test:*`)

| Flag | Efecto |
|---|---|
| `--debug` / `-d` | LOG_LEVEL=DEBUG + verbose tracebacks (ON por defecto) |
| `--no-debug` | Desactiva debug output |
| `--coverage` / `-c` | Reporte HTML de coverage |
| `--email` | Envía emails reales (`TEST_FAST=0`) |
| `--build` / `-b` | Rebuild test image antes del run (precedencia: ignora freshness check) |
| `--build-no-cache` | Rebuild sin cache |
| `--no-build` | Salta rebuild (la skill avisa si imagen stale) |
| `--no-failfast` | No para tras primer fallo |

### Flags específicos `test:stripe` / `test:full`

| Flag | Efecto |
|---|---|
| `--heavy-only` | Solo phase 2 (stripe_heavy) |
| `--skip-heavy` | Solo phase 1 |
| `--teardown` | Tras run, baja db-test + elimina volumes |
| `--force` | Salta pre-flight anti-colisión (NO recomendado) |

### Control / diagnóstico

| Comando | Función |
|---|---|
| `test:status` | Inventario containers project con roles etiquetados |
| `test:clean` | Limpieza total (dev/prod/test + db-test) |
| `test:clean --keep-db` | Limpieza preservando `db-test` |
| `test:logs [N] [-f]` | Log último run (volumen Docker; quick view) |
| `test:list` | Módulos disponibles para `test:module` |

## 6. Recovery tras colisión

```bash
./scripts/manage.sh down                                 # baja contenedores dev/prod
./scripts/manage.sh test:clean                           # baja test (incluye --keep-db opcional)
docker ps --format '{{.Names}}' | grep <proyecto>        # solo db-test persistente OK
# luego lanzar nuevo test
```

## 7. Síntomas de colisión

| Síntoma | Causa probable |
|---|---|
| `QueuePool limit of size 5 overflow 2 reached` | Dos backend test compitiendo por conexiones a `db-test` |
| `relation "users" does not exist` | TRUNCATE mientras otro lee |
| `TimeoutError: Stripe did not finalize+pay invoice within Ns` | sidecar saturado por eventos cruzados |
| Webhooks llegan pero estado DB no cambia | Dev/prod backend en `:5001` interceptó webhook |
| Tests que pasan solo pero fallan agrupados | Webhooks/fixture cleanup interfiriendo |

## 8. `mt.sh` — middleware manual tests (OPCIONAL, project-specific)

Ver `policies.md §13` para condiciones de uso. Solo aplica a proyectos con external billing provider (Stripe, PayPal o similar) que expongan un middleware como IronVolt's `mt.sh`. Si tu proyecto destino no lo tiene, **omite esta sección** completa.

| Comando | Función |
|---|---|
| `./scripts/mt.sh --env` | Mostrar variables resueltas (diagnóstico) |
| `./scripts/mt.sh --refresh` | Forzar refresh de tokens |
| `./scripts/mt.sh '<cmd>'` | Eval con env (`BASE_URL`, `ADMIN_TOKEN`, `STRIPE_KEY`, …) — comillas SIMPLES obligatorias |
| `./scripts/mt.sh --db '<python>'` | Python en backend container (log-filtrado) |
| `./scripts/mt.sh --restore` | Restore membership test user (Stripe + DB + webhooks) |
| `./scripts/mt.sh --reset-credits` | Reset créditos test user al baseline |

Variables expuestas al comando (en IronVolt):

| Variable | Significado |
|---|---|
| `$BASE_URL` | URL backend alcanzable |
| `$ADMIN_TOKEN`, `$CLIENT_TOKEN` | JWT access tokens (refresh cada 20 min) |
| `$STRIPE_KEY` | `STRIPE_TEST_SECRET_KEY` |
| `$CUSTOMER_ID`, `$PM_ID`, `$STRIPE_PRICE` | IDs Stripe del user/plan de prueba |
| `$TEST_USER_ID`, `$TEST_PLAN_ID` | User y plan canónicos de testing |
| `$FLASK_ENV`, `$WEBHOOK_WAIT` | Contexto runtime y espera tras `stripe trigger` |
