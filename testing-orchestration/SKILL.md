---
name: testing-orchestration
description: Orchestrates Python/Flask + Docker testing and guards best practices for new features and fixes. Covers plan-guardian (Service→Unit→Route→Integration→Build+RUN→Frontend→i18n→Manual→Docs), unit/API/background/external-provider tests, reset+rebuild cycles of dev and test stacks, test→fix→re-run regression loop, detection of tests affected by changes, manual UI test orchestration, migration ID validation, sprint status reporting, post-run log audit, and i18n coherence checking. Trigger phrases include "voy a añadir feature", "diseñar plan", "test:module", "test:stripe", "test:full", "test:bg", "test:unit", "rebuild test image", "down y rebuild", "manual test from user perspective", "regression check", "fix and re-run", "valida migraciones", "report status", "actualiza i18n", "añade traducción", "i18n missing locale", "manage.sh", "mt.sh".
---

<!--
Frontmatter notes (Claude Code skill format constraints):
- Only `name` + `description` are valid skill frontmatter keys. Any extra key (e.g. `when_to_use`, `paths`) or non-list `allowed-tools` value causes the skill to be silently dropped from the catalog by the indexer (no error surfaced).
- Trigger phrases live INSIDE `description` so the model can pattern-match them — `when_to_use:` does not exist as a separate frontmatter key for skills.
- `allowed-tools:` with `Bash(./scripts/manage.sh*)`-style globs is slash-command policy syntax, NOT skill syntax. Skills accept a flat list of tool names (e.g. `[Bash, Read, Edit]`) or omit the key entirely (the latter is what we do — tool gating happens via the host's settings.json instead).
- Auto-trigger by `paths:` is a slash-command feature that does NOT apply to skills. The skill is invoked by description-match against the user prompt, or by explicit `/testing-orchestration`.
- Internal references throughout this file and the companion docs (workflows.md, commands-reference.md, etc.) that mention "the `paths:` frontmatter" or "the `when_to_use:` frontmatter" describe the original design intent and remain useful as documentation; the operational contract is now: invoke the skill explicitly or via prompt phrasing.
-->


# Testing orchestration

Orquesta el ciclo de testing automatizado de un proyecto Python/Flask sobre Docker y actúa como guardián de buenas prácticas para nuevas funcionalidades y fixes. Entry point exclusivo para Docker/test/env: el script de orquestación del proyecto (`./scripts/manage.sh` o equivalente; **regla absoluta — nunca `docker compose` directo**).

## Adopción al proyecto (LEER PRIMERO)

Esta skill es **agnóstica al proyecto**. Se diseñó portable a otros proyectos Python/Flask + Docker que tengan:
- `CLAUDE.md` (peer doc auto-cargado por Claude Code) declarando arquitectura/layout/credenciales test, opcionalmente referenciando un `ARCHITECTURE.md` u otros docs como detalle profundo.
- Un script de orquestación tipo `manage.sh` o equivalente con subcomandos `test:*`, `build:test`, `up:dev`, etc.

Al adoptar la skill en un proyecto destino, **resolver las variables siguientes consultando `CLAUDE.md`** (y los docs que referencie). Las que se documentan via env var pueden quedar en placeholder; las que afectan el frontmatter `paths:` deben añadirse al frontmatter al instalar la skill.

| Variable | Resolución | Dónde aplica | Notas |
|---|---|---|---|
| `{{backend_path}}` | path raíz del backend declarado en `CLAUDE.md` | `paths:` frontmatter (AÑADIR `<backend_path>/**`), `BACKEND_PATH` env var (freshness check, workflow E, workflow K) | **Crítica** — el algoritmo de freshness depende. Por defecto el código del freshness usa placeholder `backend`; exportar `BACKEND_PATH=app` (o el path real del proyecto) o sustituir en el frontmatter |
| `{{frontend_path}}` | path del frontend declarado en `CLAUDE.md` (si aplica) | commands-reference.md, plan-template §7-§9 | Eliminar referencias si el proyecto no tiene frontend |
| `{{locales_path}}` | path de los archivos i18n (si aplica) | `paths:` frontmatter (AÑADIR), workflow J `LOCALES_DIR` env var | Omitir si no hay i18n |
| `{{locales_list}}` | detectado dinámicamente del filesystem | workflow J — leído de `$LOCALES_DIR/*/` | No hardcoded |
| `{{namespaces_list}}` | detectado dinámicamente | workflow J — leído de `$LOCALES_DIR/<ref>/` | No hardcoded |
| `{{migrations_path}}` | path Alembic declarado en `CLAUDE.md` | `paths:` frontmatter (AÑADIR), workflow H, validate_migrations.sh `MIGRATIONS_DIR` env var | Consultar `CLAUDE.md` §"layout / migrations" |
| `{{user_manual_path}}` | path al user manual declarado en `CLAUDE.md` (si existe) | invariant 9, plan-template §11, workflow J `USER_MANUAL_PATH` env var | Vacío = skip cross-check; eliminar si no hay user manual |
| `{{bug_tracker_active}}` | path al bug tracker activo del proyecto | invariant 10, policies §12, bug-tracker-template, workflow K `BUG_TRACKER_ACTIVE` env var | Default razonable: `docs/<analysis_dir>/<bug_tracker>.md` |
| `{{bug_tracker_history}}` | path al gemelo histórico | idem (`BUG_TRACKER_HISTORY` env var) | |
| `{{dev_url}}` | URL del dev frontend declarada en `CLAUDE.md` | manual-testing.md, plan-template, workflow A smoke test | |
| `{{backend_url}}` | URL del backend declarada en `CLAUDE.md` | stripe-integration.md (manual stripe-cli) | |
| `{{minio_console}}` | URL consola MinIO si aplica | manual-testing.md (audit storage) | Eliminar si no hay MinIO o storage similar |
| `{{test_admin_email}}` | credenciales test declaradas en `CLAUDE.md` §test creds | manual-testing.md, plan-template §10 | |
| `{{compose_project_prefix}}` | prefijo Docker Compose del proyecto | invariants, anti-colisión grep | Default: `COMPOSE_PROJECT_NAME` del proyecto |
| `{{sidecar_name}}` | nombre del sidecar test si existe | invariant 1, anti-colisión grep, audit | Ej. `stripe-cli`, `localstack`, `mailhog`; eliminar si no aplica |
| `{{stage}}` | `dev` o `production` declarado en `CLAUDE.md` §"estado del proyecto" | sección "Estado del proyecto" abajo | `dev` = sin backfill ni shape antiguo. `production` cambia reglas (fuera de scope skill) |

**Resumen de instalación (3 pasos)**:
1. **Copiar** `skills/testing-orchestration/` al repo destino (preservando `scripts/` adjuntos).
2. **Editar** `paths:` del frontmatter SKILL.md añadiendo los paths concretos del proyecto destino (descomentando los placeholders del bloque `# Paths específicos del proyecto destino`).
3. **Ejecutar** `/testing-orchestration self-check` (workflow K) para verificar que `CLAUDE.md`, `manage.sh`, paths, markers pytest y bug tracker dual están presentes y consistentes.

**Pre-flight de adopción** — workflow opcional `/testing-orchestration self-check`:
1. Verifica que el peer doc (`CLAUDE.md` o equivalente) existe y describe arquitectura, stack, credenciales test, comandos del orquestador.
2. Verifica que `./scripts/<orquestador>` existe y es ejecutable.
3. Verifica el **stack Docker** (pieza fundamental de los requisitos arquitectónicos): daemon vivo, `docker compose` v2 disponible, compose files referenciados por el orquestador presentes en disco, servicios mínimos (`backend` + `db-test` o equivalentes según `CLAUDE.md` — override via `EXPECTED_SERVICES`) declarados, imagen test construida (warn si falta — primer `test:*` la crea), label `src_hash` para freshness por hash (warn si falta — fallback mtime aplica), red externa `proxy` si la requiere `up` prod (info — irrelevante en máquina dev pura).
4. Verifica que paths del frontmatter resuelven a archivos del proyecto.
5. Verifica que `pytest.ini` / `conftest.py` exponen markers usados (`stripe_integration`, `stripe_heavy`, `stripe_flaky`, `bg_flaky` o equivalentes — ver workflow B sync).

Si self-check falla → **no usar la skill** hasta resolver. La skill **no es funcional** sin el peer doc + el orquestador + Docker funcional.

## Estado del proyecto (precondición)

Si el proyecto está en fase **dev sin usuarios reales** (declarado en `CLAUDE.md` §"estado del proyecto" — `{{stage}} = dev`): no hay backfill de data legacy, no hay shape antiguo a tolerar. Schema migrations sí; data legacy no. Cualquier fix solo necesita dejar el comportamiento correcto para data nueva; data dev se reseedea libremente.

Si el proyecto tiene usuarios reales en producción: declarar `{{stage}} = production`, y entonces aplican reglas de backfill/migration scripts (esta skill **no** las orquesta — fuera de scope).

## Asunciones del entorno

Esta skill **asume** que el peer doc del proyecto (`CLAUDE.md`) describe la arquitectura concreta (stack, bind mounts, servicios, puertos, credenciales test). Para bindings específicos consulta esa fuente como peer doc preloadado. **No** repliques esa información aquí — la skill encoda solo reglas abstractas.

## Invariants — leer antes de cualquier acción

1. **Anti-colisión**: antes de cualquier `test:*`, ningún `{{compose_project_prefix}}_test-(backend-run|<sidecar>)` ni `{{compose_project_prefix}}_(backend|web)-1` activos.
2. **Image freshness — la skill es la autoridad**. Comparar **content hash** (preferido) o timestamp UTC de la imagen test vs. archivos `{{backend_path}}/` no-tests. Si stale, rebuild silencioso. Con `--no-build` explícito, avisar al usuario. Algoritmo robusto en sección "Pre-flight" abajo.
3. **Rebuild ON por defecto**. Opt-out con `--no-build`. Precedencia: `--build` siempre rebuild, `--no-build` siempre skip (con warning si stale), sin flag → freshness check decide.
4. **Secuencial, nunca paralelo**. Compartir `db-test` schema entre runs simultáneos rompe TRUNCATE.
5. **Captura output a fichero** para runs largos (`>/tmp/test_debug.log 2>&1`).
6. **Nunca matar un run a medio**. `TaskStop` → `manage.sh test:down` → verificar limpio → re-lanzar.
7. **Tests configuran su policy** (no confiar en defaults globales — `SystemSettings`, feature flags, env config).
8. **Integration tests no mockean DB**.
9. **User manual = source of truth** (`{{user_manual_path}}` si existe). Mantener en sync con cambios funcionales.
10. **Bug tracker dual**: activo (`{{bug_tracker_active}}`, mínimo de abiertos) + gemelo (`{{bug_tracker_history}}`, append-only). Mover entrada en el commit que cierra el bug — operación cohesiva en un único commit (atomicidad delegada a git, no transaccional a nivel filesystem).

## Cuándo invocar esta skill

Aparece automáticamente al editar archivos en `paths:` o por frases gatillo del `when_to_use:`. Invócala explícitamente con `/testing-orchestration`.

Casos típicos:
- Vas a empezar una feature/fix nueva → workflow G (plan-guardian).
- Quieres lanzar tests (`test:module / test:api / test:bg / test:stripe / test:full / test:unit`).
- Diagnosticas `relation "users" does not exist`, `QueuePool limit`, `TimeoutError`, schema corruption.
- Vas a marcar/desmarcar `xfail`, `stripe_flaky`, `bg_flaky`, `stripe_heavy`.
- Audit post-run de `logs/test_runs/<ts>_<label>/`.
- "Verificación manual desde la perspectiva del usuario".
- Cambios en i18n.
- Cambios en migraciones.
- "Status del sprint" / "resumen de runs y bugs".

## Workflows orquestados extremo-a-extremo

| ID | Nombre | Disparo típico | Comando inicial | Cierre |
|---|---|---|---|---|
| **G** | Plan-guardian | "voy a añadir feature X" | emite `plan-template.md` | plan validado por 6-checks |
| **A** | Restart dev (site) | "down y rebuild dev" | `manage.sh down → build:dev → up:dev` | `up:dev` reporta READY + smoke `/api/health` |
| **B** | Restart test stack | "reset test" | `test:clean → build:test` | imagen test fresh |
| **C** | Run + audit canónico | `test:module/api/bg/stripe/full/unit` | preflight → run con captura → audit run dir | veredicto PASS/FAIL/SKIP |
| **D** | Test → fix → re-run | post-cambio backend, bug fix, refactor | baseline → failing-test-first → fix → re-run | scope verde, sin regresiones, máx 3 intentos (variable) |
| **E** | Detect tests afectados | edit en código fuente backend (path declarado en `CLAUDE.md`) | `git diff` + grep imports + símbolos | tabla con confianza alta/media/baja |
| **F** | Manual UI test | "verificación manual" | A → guion UI → audit reactiva | reporte clasificado |
| **H** | Validate migrations | edit `{{migrations_path}}*` | `validate_migrations.sh` | IDs únicos + chain coherente |
| **I** | Sprint status | "report del sprint" | agrega runs + bugs + markers | reporte consolidado |
| **J** | i18n coherence | edit `{{locales_path}}` | check N locales (lista dinámica) + cross-check user manual + tests | gaps reportados |
| **K** | Self-check de adopción | `/testing-orchestration self-check` | 9 verificaciones (peer doc, orquestador, docker stack, paths, locales, bug tracker dual, markers pytest, sync scripts, env vars) | 0 errores `[FAIL]` |

**Plan G envuelve a los demás** durante el diseño de feature/fix:

```
G ──┬── 0. precondición: status repo limpio
    ├── 1. ejecuta E (detect tests afectados → subset focalizado refinado)
    ├── 2. arquitecto diseña Service
    ├── 3. unit test + RUN subset focalizado (gate temprano) — workflow D si rojo
    ├── 4. Route + RBAC (capas ad-hoc del proyecto, ver plan-template §4)
    ├── 5. Integration test
    ├── 6. Build + RUN módulo (gate completo) — workflow D si rojo, max 3
    ├── 7-9. Frontend + refactor consumidores + i18n N locales
    ├── 10. ejecuta F (manual UI test) y consolida reporte
    └── 11-12. docs (manual + bug tracker + doc políticas si aprendizaje) + definition of done
```

D, E, F, C, H, I, J también pueden invocarse standalone (sin G).

**Variantes adicionales del Plan G** (ver plan-template.md):
- **Refactor puro** — omite §4, §7-§10 (conserva §1, §2, §3, §6, §11, §12).
- **Hotfix urgente** — sólo §0, §1, §6, §11, §12 (test post-fix no negociable).
- **Config / migration only** — §0 + workflow H + §6 (regresión completa) + §11.

Detalle paso a paso de cada workflow: ver [workflows.md](workflows.md).

## Pre-flight (compartido por workflows B/C/D)

```bash
# 1. Status
./scripts/manage.sh test:status

# 2. Anti-colisión
docker ps --format '{{.Names}}' | grep -E "_test-(backend-run|stripe-cli|<sidecar>)" && \
  ./scripts/manage.sh test:clean --keep-db

# 3. Image freshness check (LA SKILL ES LA AUTORIDAD) — algoritmo robusto
# Variables de proyecto (override via env):
BACKEND_PATH="${BACKEND_PATH:-backend}"  # placeholder genérico — exportar el path real declarado en CLAUDE.md (ej. app, src, server, …)
TESTS_SUBPATH="${TESTS_SUBPATH:-tests}"   # subpath de tests dentro de BACKEND_PATH
TEST_IMG=$(docker images --format '{{.Repository}}' | grep -E 'test-backend' | head -1)

# Preferido: comparación por content hash (label de la imagen)
SRC_HASH=$(find "$BACKEND_PATH" -type f -name '*.py' \
  -not -path "$BACKEND_PATH/$TESTS_SUBPATH/*" \
  -not -path '*/__pycache__/*' \
  -not -name '*.pyc' \
  -not -name '*.egg-info*' \
  | sort | xargs sha256sum | sha256sum | cut -d' ' -f1 | head -c 16)

IMG_HASH=$(docker image inspect "$TEST_IMG" --format '{{ index .Config.Labels "src_hash" }}' 2>/dev/null)

if [ -z "$TEST_IMG" ]; then
  ./scripts/manage.sh build:test  # imagen no existe
elif [ -z "$IMG_HASH" ]; then
  # Fallback timestamp UTC explícito (compatible con builds antiguas sin label)
  IMG_TS_UTC=$(docker image inspect "$TEST_IMG" --format '{{.Created}}' 2>/dev/null)
  IMG_EPOCH=$(date -u -d "$IMG_TS_UTC" +%s 2>/dev/null)
  LATEST_SRC=$(find "$BACKEND_PATH" -type f -name '*.py' \
    -not -path "$BACKEND_PATH/$TESTS_SUBPATH/*" \
    -not -path '*/__pycache__/*' \
    -not -name '*.pyc' \
    -newermt "@$IMG_EPOCH" 2>/dev/null | head -1)
  if [ -n "$LATEST_SRC" ]; then
    echo "STALE (mtime fallback): $LATEST_SRC after build"
    ./scripts/manage.sh build:test
  fi
elif [ "$SRC_HASH" != "$IMG_HASH" ]; then
  echo "STALE (hash mismatch): src=$SRC_HASH img=$IMG_HASH"
  ./scripts/manage.sh build:test
fi
```

**Notas del algoritmo**:
- **Content hash robusto** a zonas horarias, mtimes preservados (git checkout, tarball), archivos generados (`__pycache__/`, `*.pyc`, `*.egg-info`).
- **Parametrizado** vía `BACKEND_PATH` y `TESTS_SUBPATH` env vars — funciona en cualquier layout. Consultar `CLAUDE.md` del proyecto para los valores reales; exportar antes de invocar la skill o sustituir en el frontmatter.
- Asume que `manage.sh build:test` añade `--label src_hash=<hash>` al `docker build`. Si la build no lo soporta, el fallback timestamp con epoch UTC funciona pero con falsos positivos posibles.
- Para añadir el label a tu `manage.sh`: `docker build --label src_hash=$(<el cálculo de SRC_HASH arriba>) ...`.

**Comportamiento por defecto**: rebuild silencioso si stale. Con `--no-build` explícito → avisa al usuario y pide confirmación.

## Smart run flags — matriz de decisión

| Caso | Flags propuestos |
|------|------------------|
| Iteración rápida tras cambio puntual en un test | `--no-build --no-failfast` |
| Validación pre-PR de un módulo | `-c` (coverage) + default failfast |
| Debug de regresión confusa | `-d` + `--no-failfast` |
| Suite completa pre-merge | `test:full -c` (sin debug) |
| Repro de un solo test | `test:module <mod> -k "<expr>" --no-build` |
| Tras cambio de deps | `--no-cache` obligatorio |
| Tras cambio de modelos | rebuild + `validate_migrations.sh` antes |

La skill propone los flags óptimos por caso; el usuario puede overridearlos. Sin override, defaults de la matriz.

## Post-run audit (compartido por C/D/F)

```bash
RUN_DIR=$(ls -td logs/test_runs/*/ | head -1)
echo "Auditing: $RUN_DIR"

# 1. summary.log — verdict por fase
cat "${RUN_DIR}summary.log"

# 2. backend.log — errores significativos
grep -nE "PASSED|FAILED|ERROR|CRITICAL|InternalError|OperationalError|psycopg2" \
  "${RUN_DIR}backend.log" | head -30

# 3. backend_heavy.log si phase 2 corrió
[ -f "${RUN_DIR}backend_heavy.log" ] && \
  grep -nE "FAILED|ERROR" "${RUN_DIR}backend_heavy.log" | head -20

# 4. db_test.log — arranque limpio
[ -f "${RUN_DIR}db_test.log" ] && \
  grep -nE "FATAL|deadlock|database system is ready" "${RUN_DIR}db_test.log" | head -10

# 5. stripe_cli.log — sidecar errors (solo proyectos con Stripe)
[ -f "${RUN_DIR}stripe_cli.log" ] && \
  grep -nE "\[ERROR\]|5[0-9]{2}|refused|timeout|no such host" "${RUN_DIR}stripe_cli.log" | head -20
```

**Veredicto al usuario**:
- Resumen pytest (PASS/FAIL/SKIP por fase).
- Path del run dir.
- Lista de errores significativos con `file:line`.
- Bloque cobertura: `[OK]` (presente con contenido) / `[N/A]` (contenedor no levantado, justificado) / `[DISCREPANCIA]` (exigible pero ausente).

**Política frente a DISCREPANCIA**: la skill **no declara verde** un run con discrepancia exigible. Acción:
1. Reportar la discrepancia al usuario con hipótesis (fallo de captura, container no arrancó, bug en harvest_logs).
2. Proponer re-run con `--build` forzado o investigación de harness.
3. Si el usuario decide aceptar la discrepancia (run "amarillo" pragmático), documentar override explícito en el reporte.

Detalle completo del protocolo: ver [audit.md](audit.md).

## Plan G — emisión de la plantilla

Cuando workflow G dispara, la skill inyecta la plantilla completa via shell injection desde el aux dedicado:

```
!`cat ${CLAUDE_SKILL_DIR}/plan-template.md`
```

El arquitecto (humano o agente reviewer del proyecto) rellena el contenido. La skill audita los **6 chequeos**:

1. ¿Sección 1 lista tests afectados? Si dice "ninguno", validar con workflow E.
2. ¿Sección 4 declara el chequeo de permisos del proyecto? Si no, RED FLAG (peer doc del proyecto define qué decorador usar).
3. ¿Sección 6 declara gate test-verde + max 3 intentos (variable)?
4. ¿Sección 9 lista los N locales del proyecto?
5. ¿Sección 10 incluye plan manual UI si la feature es user-facing?
6. ¿Sección 12 (definition of done) tiene checkboxes?

Si algún check falla → **warning visible** (no bloqueo duro). El arquitecto decide si overridea con justificación.

Variantes (refactor / hotfix / config-only): ver plan-template.md.

Detalle paso a paso de G: ver [workflows.md](workflows.md) §G.

## Triggers — cómo se activa la skill

**Slash explícitos** (control determinista — el usuario teclea):

| Slash | Workflow | Sintaxis |
|---|---|---|
| `/testing-orchestration` | Carga skill | sin args |
| `/testing-orchestration design <título>` | G plan-guardian | título freeform |
| `/testing-orchestration run <test:cmd>` | C run + audit | comando manage.sh con flags |
| `/testing-orchestration restart-dev` | A restart dev | sin args |
| `/testing-orchestration restart-test` | B restart test | sin args |
| `/testing-orchestration affected` | E detect tests afectados | sin args (lee git diff) |
| `/testing-orchestration manual <feature>` | F manual UI | nombre flujo |
| `/testing-orchestration audit <run-dir>` | Audit standalone | path al run dir |
| `/testing-orchestration validate-migrations` | H validate migrations | sin args |
| `/testing-orchestration status` | I sprint status | sin args |
| `/testing-orchestration self-check` | self-check adopción | sin args |

**Auto-trigger** (modelo decide — sin teclear):

- **Por description match**: frases del usuario tipo *"voy a añadir feature"*, *"down y rebuild"*, *"lanza test:stripe"*, *"verificación manual"*, *"qué tests cubren"*, *"fix and re-run"*, *"valida migraciones"* (lista completa en `when_to_use:` del frontmatter).
- **Por path match**: editar archivos en `paths:` (backend, migrations, locales, scripts del orquestador, compose, run dirs).

**Comportamiento ante args ausentes/inválidos**:
- `design` sin título → preguntar al usuario *"¿título corto del feature/fix?"*.
- `audit` sin path → listar últimos 5 run dirs en `logs/test_runs/`.
- `audit` path inexistente → error claro + sugerencia `/testing-orchestration status`.
- `run` sin cmd → menú con `test:unit / test:module / test:api / test:bg / test:stripe / test:full`.

Detalle completo de cada trigger + ejemplos: ver [commands-reference.md](commands-reference.md).

## Markers y políticas (resumen)

- `xfail` / `xpass`: sync con resultados reales — solo se añade tras observar fallo reproducible y diagnosticado; solo se quita tras re-ejecutar y verde en mismo contexto.
- `stripe_heavy` / `bg_heavy` / equivalentes del proyecto: aislamiento phase 2 + cooldown.
- `stripe_flaky` / `bg_flaky` / equivalentes: phase 3 retry-on-failure (3 attempts, cooldown según dominio — 30s Stripe, 15s bg).
- **No** existe `api_flaky` / `unit_flaky` — fallos ahí son bugs deterministas, no flakiness.

Detalle: [policies.md](policies.md) §flaky.

## Instalación de la skill en Claude Code

La skill vive en `skills/testing-orchestration/` del repo (artefacto distribuible vía git). Para que **Claude Code la auto-descubra** debe estar también en `.claude/skills/<name>/` (path canónico oficial). Recomendado:

```bash
./scripts/manage.sh install:skill testing-orchestration            # copia (default, runtime-portable)
./scripts/manage.sh install:skill testing-orchestration --force    # refresca copia tras editar fuente
./scripts/manage.sh install:skill testing-orchestration --symlink  # opt-in: symlink (cero drift, dev iterativo)
./scripts/manage.sh uninstall:skill testing-orchestration          # elimina symlink/copia (rm -rf de la copia)
./scripts/manage.sh skills:list                                     # lista qué hay disponible vs instalado
./scripts/manage.sh skills:sync-scripts                             # tras editar manage.sh/mt.sh, sincroniza la copia adjunta
```

**Copia por defecto** (decisión del arquitecto, ver doc 060 §11 + revisión 2026-04-28):
- `.claude/skills/testing-orchestration/` = copia recursiva del directorio fuente.
- Portable: no depende de la ruta absoluta del repo en disco.
- Robusto frente a runtimes que indexan `.claude/skills/` sin resolver symlinks de forma fiable (cold-start indexer detectaba el symlink tarde).
- **Trade-off**: tras editar la skill en `skills/`, hay que `install:skill <name> --force` para refrescar la copia (o `skills:sync-scripts` si solo cambiaste scripts adjuntos).

**Symlink opt-in (`--symlink`)**:
- Útil cuando la skill está en heavy iteration y se quiere evitar el reinstall manual.
- Cero drift entre la versión versionada en git y lo que Claude Code carga.
- Caveat Windows: symlinks requieren developer mode.
- Caveat runtime: si la skill no aparece tras `install`, prueba con copia en su lugar.

**Override del target dir**: por defecto `.claude/skills/` del repo. Para instalar a nivel usuario (todos los proyectos del mismo user) o a un path custom, exportar antes:
```bash
CLAUDE_SKILLS_DIR=$HOME/.claude/skills ./scripts/manage.sh install:skill testing-orchestration
```

**Restart de sesión Claude Code**: tras la primera `install:skill` (cuando `.claude/skills/` se crea por primera vez), reiniciar Claude Code es **obligatorio** per docs oficiales. Tras instalaciones posteriores, el restart suele ser opcional.

## Recursos adjuntos en la skill (estrategia A — copia)

- `${CLAUDE_SKILL_DIR}/scripts/manage.sh` — orquestador principal (copia de `scripts/manage.sh` del repo).
- `${CLAUDE_SKILL_DIR}/scripts/mt.sh` — **opcional**: middleware manual tests específico del proyecto (típicamente env vars para payment providers, tokens auth, sidecars externos — depende de cada proyecto). Si el proyecto destino no lo usa, eliminar.
- `${CLAUDE_SKILL_DIR}/scripts/stripe_heavy_collect.py` (renombrar a `pytest_class_collector.py` para portabilidad — collector pytest genérico que filtra por marker).
- `${CLAUDE_SKILL_DIR}/scripts/validate_migrations.sh` — Alembic validator (parametrizable via env `MIGRATIONS_DIR`).
- `${CLAUDE_SKILL_DIR}/scripts/sync-skill-scripts.sh` — pre-commit hook helper que vive **dentro de la skill** (no en `scripts/` del repo) por diseño: el hook es un asset distribuible con la skill, no del repo. Su ruta canónica al instalar es vía symlink desde `.git/hooks/pre-commit` (ver instrucciones en su cabecera).

**Sincronización repo ↔ skill** (drift prevention):
- **Pre-commit hook obligatorio** en `.git/hooks/pre-commit` o vía CI: si `scripts/<X>` cambió y `skills/testing-orchestration/scripts/<X>` no se actualizó en el mismo commit → fail.
- Workflow B y workflow I también ejecutan sync check (defensa secundaria). Implementación: `diff -q scripts/<X> skills/testing-orchestration/scripts/<X> || warning`.
- Alternativa: symlinks relativos (`scripts/manage.sh -> ../../../scripts/manage.sh`). Caveat: rompen al copiar la skill a otra máquina.

## Bug tracker dual (acción de la skill)

- **Abrir bug** (workflow #26): añade entrada en `{{bug_tracker_active}}` (activo, mínimo de abiertos) usando §1 de [bug-tracker-template.md](bug-tracker-template.md).
- **Cerrar bug** (workflow #27): mueve entrada del activo a `{{bug_tracker_history}}` (gemelo) en el mismo commit que aplica el fix, reescrita con §2 de la plantilla. La skill **modifica ambos archivos** vía `Edit`/`Write` allowed-tools — operación **cohesiva** en un único commit (atomicidad delegada a git, no transaccional a nivel filesystem).
- Mantiene el activo mínimo y el gemelo append-only con índice por dominio.
- Workflow I (`/testing-orchestration status`) verifica integridad: conteo, IDs duplicados, estados anómalos.

## Definition of done de un sprint que usa la skill

- Tests de la regresión scope = verde.
- Suite afectada = sin regresiones.
- xfail/xpass markers sincronizados.
- Bug tracker activo + gemelo actualizados (entradas movidas en mismo commit).
- User manual actualizado si hay impacto user-facing.
- i18n N locales si hay strings nuevos.
- Doc de políticas del proyecto actualizado si surgió patrón/anti-patrón nuevo.

## Navegación a contenido detallado

- Step-by-step de cada workflow A-J: [workflows.md](workflows.md)
- Plantilla literal copiable del plan G + variantes (refactor / hotfix / config-only): [plan-template.md](plan-template.md)
- Plantillas copiables del bug tracker (open/close/NO-BUG/reopen): [bug-tracker-template.md](bug-tracker-template.md)
- Políticas generales (rebuild, anti-colisión, xfail, RBAC, idempotencia, lifecycle bug tracker): [policies.md](policies.md)
- External providers (Stripe / PayPal / similares — heavy, flaky, sidecar, playbooks lifecycle E2E, idempotency tests): [stripe-integration.md](stripe-integration.md). **Eliminar este archivo si el proyecto no usa external billing providers**.
- Manual user-perspective tests (rebuild dev, guion UI, audit reactiva, reporte clasificado): [manual-testing.md](manual-testing.md)
- Audit post-run (run dir, archivos exigidos, formato veredicto, política DISCREPANCIA): [audit.md](audit.md)
- Comandos referencia tabla completa con flags (`manage.sh test:*`, recovery, síntomas): [commands-reference.md](commands-reference.md)
