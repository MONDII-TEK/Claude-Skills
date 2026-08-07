---
name: testing-orchestration
description: Orchestrates Python/Flask + Docker testing and guards best practices for new features and fixes. Covers plan-guardian (Service→Unit→Route→Integration→Build+RUN→Frontend→i18n→Manual→Docs), unit/API/background/external-provider tests, reset+rebuild cycles of dev and test stacks, test→fix→re-run regression loop, detection of tests affected by changes, manual UI test orchestration, migration ID validation, sprint status reporting, post-run log audit, i18n coherence checking, release/semver tagging (workflow L) and release-notes maintenance (release notes are ALWAYS written from the commit log of the pushed range — subjects and bodies — never from session memory, and any entry contradicted by a revert within the range is removed or corrected). Trigger phrases include "voy a añadir feature", "nueva feature", "añade feature", "add feature", "implementa feature", "diseñar plan", "doc de análisis", "documento de análisis", "crear un doc de análisis", "vamos a crear un doc", "plan de implementación", "plan de PRs", "documento maestro", "redactar el plan", "abordar desde ese documento los cambios", "procedimientos y tasks", "arregla el bug", "fix bug", "fixea el bug", "nuevo bug", "reporta un bug", "investigar bug", "regression", "test:module", "test:stripe", "test:full", "test:bg", "test:unit", "rebuild test image", "down y rebuild", "manual test from user perspective", "regression check", "fix and re-run", "valida migraciones", "report status", "actualiza i18n", "añade traducción", "i18n missing locale", "manage.sh", "mt.sh", "version:tag", "version:current", "bump version", "tag de release", "tagea", "tag it", "vamos a hacer release", "haz release", "deploy a NAS", "release notes", "dev notes", "notas de release", "escribe las release notes", "redacta release notes", "actualiza las release notes", "actualiza las RN", "escribe las RN", "qué tenemos para push", "estamos para push", "hotfix", "hazme un hotfix", "haz un hotfix", "vamos con hotfixes", "parche", "parche rápido", "arreglo rápido", "quick fix", "esto no se actualiza", "queda desactualizado hasta refresh", "no se refresca", "sale stale", "no invalida la caché", "dejó de funcionar", "esto está roto". IMPORTANTE: redactar un DOC DE ANÁLISIS que incluya el plan de implementación (cambios, fixes, procedimientos, tasks a abordar después) ES fase de diseño y dispara el plan-guardian (workflow G) AUNQUE en esa sesión no se toque código ni se ejecute ningún test — el plan dentro del doc debe nacer con la estructura del plan-template (tests afectados, RBAC, i18n, gates test-verde, definition of done) y con test contracts (§H) e invariantes (§B/§G) por PR; no cargar la skill "porque aún no hay código" es el error de criterio que esta frase previene. IMPORTANTE: un "hotfix" / "arreglo rápido" NO es una excepción — dispara la skill igual que un bug fix normal (workflow D: baseline→red→fix→green); si el usuario encadena varios hotfixes seguidos, la skill sigue activa en cada uno. Short English triggers (sub-agents and tools often prompt tersely in English — match these as substrings/wildcards, `*` = match anywhere): *analysis doc*, *analysis document*, *implementation plan*, *master plan*, *PR plan*, *design doc*, *hotfix*, *fix bug*, *fix the bug*, *bug fix*, *this is broken*, *stopped working*, *reproduce*, *run tests*, *run the tests*, *test:module*, *rebuild test image*, *red-green*, *failing test*, *test first*, *write a test*, *add a test*, *test coverage*, *regression*, *cache stale*, *stale cache*, *not refreshing*, *stale until refresh*, *invalidate cache*, *validate migration*, *cut a release*, *tag release*, *bump version*, *release notes*, *what's ready to push*. Auto-aprendizaje (workflow M): se dispara sobre todo por DETECCIÓN del modelo (emerge un aprendizaje reutilizable durante el trabajo), NO por una frase; el usuario puede FORZARLO con: *apúntalo*, *apunta eso*, *captura este aprendizaje*, *esto es un aprendizaje*, *añádelo a la skill*, *guárdalo en la skill*, *aprende esto*, *recuérdalo para futuro*, *que no se repita*, *documéntalo para que no se repita*, *learn this*, *capture this learning*, *add this to the skill*, *remember this for next time*, *don't let this happen again*, *note this pattern*. Also triggers on "lighthouse", "pagespeed", "search console", "auditoría seo", "meta-html", "dynamic rendering", "lo ve el bot", "documento que recibe googlebot". IMPORTANTE — AUDITAR O EXPLORAR CÓDIGO (invariante 27): auditar código, diagnosticar un bug, medir el alcance de un fix/hotfix, arrancar una feature, refactorizar o averiguar qué tests cubren algo se hace con el GRAFO (`codebase-memory-mcp`), NO con grep; el grep sobre código es fallback de urgencia y obliga a declarar que la cobertura es parcial. Gatillos: "audita el código", "auditoría de código", "revisa el código", "revisar la implementación", "qué llama a", "quién usa", "qué se rompe si cambio", "qué tests cubren", "dónde se usa", "traza el flujo", "impacto del cambio", *audit the code*, *code audit*, *review the implementation*, *what calls*, *who uses*, *what breaks if*, *which tests cover*, *trace the flow*, *impact analysis*. IMPORTANTE — cambio de INVARIANTE GLOBAL (invariante 37): también se dispara al ir a añadir un guard que aborta, restringir una configuración a menos valores, sustituir un camino por otro o cambiar la firma de algo llamado desde varios sitios, porque el inventario de llamadores y de tests afectados hay que hacerlo ANTES del cambio — después todo lo que quedó con la regla vieja sigue en verde y no hay señal que lo delate: "añadir un guard", "meto un guard", "poner una validación", "restringir la configuración", "solo permitir", "deprecar", "cambiar la firma", "quién llama a esto", "todos los llamadores", "esto se llama desde varios sitios", *add a guard*, *add a validation*, *restrict the config*, *deprecate*, *change the signature*, *who calls this*, *all callers*, *breaking change*.
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

Al adoptar la skill en un proyecto destino, **resolver las variables siguientes consultando `CLAUDE.md`** (y los docs que referencie). Se configuran de dos formas, **ninguna en el frontmatter**: (a) las que el código de los workflows consume, vía **env vars** (`BACKEND_PATH`, `LOCALES_DIR`, `MIGRATIONS_DIR`, `BUG_TRACKER_ACTIVE`, …); (b) las demás, declarándolas en `CLAUDE.md` para que la skill las lea en contexto. El frontmatter de una skill solo admite `name`+`description` (ver cabecera), así que **el disparo es por `description` + invocación explícita**, nunca por `paths:`.

| Variable | Resolución | Dónde aplica | Notas |
|---|---|---|---|
| `{{backend_path}}` | path raíz del backend declarado en `CLAUDE.md` | `BACKEND_PATH` env var (freshness check, workflow E, workflow K) | **Crítica** — el algoritmo de freshness depende. Por defecto el código del freshness usa placeholder `backend`; exportar `BACKEND_PATH=app` (o el path real del proyecto) antes de invocar la skill |
| `{{frontend_path}}` | path del frontend declarado en `CLAUDE.md` (si aplica) | commands-reference.md, plan-template §7-§9 | Eliminar referencias si el proyecto no tiene frontend |
| `{{locales_path}}` | path de los archivos i18n (si aplica) | workflow J vía `LOCALES_DIR` env var | Omitir si no hay i18n |
| `{{locales_list}}` | detectado dinámicamente del filesystem | workflow J — leído de `$LOCALES_DIR/*/` | No hardcoded |
| `{{namespaces_list}}` | detectado dinámicamente | workflow J — leído de `$LOCALES_DIR/<ref>/` | No hardcoded |
| `{{migrations_path}}` | path Alembic declarado en `CLAUDE.md` | workflow H + validate_migrations.sh vía `MIGRATIONS_DIR` env var | Consultar `CLAUDE.md` §"layout / migrations" |
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
1. **Copiar** `skills/testing-orchestration/` al repo destino (solo docs — la skill ya no trae scripts; referencia los `./scripts/*` del proyecto).
2. **Configurar las variables** que los workflows consumen vía env (al menos `BACKEND_PATH`; y `LOCALES_DIR` / `MIGRATIONS_DIR` / `BUG_TRACKER_ACTIVE` / `BUG_TRACKER_HISTORY` si aplican) y confirmar que `CLAUDE.md` declara arquitectura, layout y credenciales test. **El frontmatter no se toca** (solo `name`+`description`); si quieres afinar el disparo, ajusta las frases gatillo del `description`.
3. **Ejecutar** `/testing-orchestration self-check` (workflow K) para verificar que `CLAUDE.md`, `manage.sh`, paths, markers pytest y bug tracker dual están presentes y consistentes.

**Pre-flight de adopción** — workflow opcional `/testing-orchestration self-check`:
1. Verifica que el peer doc (`CLAUDE.md` o equivalente) existe y describe arquitectura, stack, credenciales test, comandos del orquestador.
2. Verifica que `./scripts/<orquestador>` existe y es ejecutable.
3. Verifica el **stack Docker** (pieza fundamental de los requisitos arquitectónicos): daemon vivo, `docker compose` v2 disponible, compose files referenciados por el orquestador presentes en disco, servicios mínimos (`backend` + `db-test` o equivalentes según `CLAUDE.md` — override via `EXPECTED_SERVICES`) declarados, imagen test construida (warn si falta — primer `test:*` la crea), label `src_hash` para freshness por hash (warn si falta — fallback mtime aplica), red externa `proxy` si la requiere `up` prod (info — irrelevante en máquina dev pura).
4. Verifica que los paths del proyecto (env vars `BACKEND_PATH`/`LOCALES_DIR`/`MIGRATIONS_DIR`/… o declarados en `CLAUDE.md`) resuelven a archivos reales.
5. Verifica que `pytest.ini` / `conftest.py` exponen markers usados (`stripe_integration`, `stripe_heavy`, `stripe_flaky`, `bg_flaky` o equivalentes — ver workflow B).

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
11. **Auditoría inter-PR vs doc maestro** — en features grandes con plan vinculante (e.g. doc 063 logística DHL con §G matriz cobertura + §H test contracts), tras cerrar cada PR y antes de empezar el siguiente, auditar formalmente:
    - **Decisiones cerradas (§G)** asignadas al PR mergeado → todas implementadas en código real.
    - **Test contracts (§H)** asignados al PR → existen en `backend/tests/` y pasan en verde.
    - **Invariantes** (§B plan maestro) → cumplidos (audit emission, JWT permission_required, idempotency, i18n 4 locales, tokens semánticos).
    - **Drift del doc** → si hubo desvío de decisión cerrada, debe haber commit `docs(...)` previo al merge.
    - **Regresión** → suite del módulo relacionado en verde.

    Si la auditoría detecta gaps, completarlos en commits modulares **dentro del mismo branch** (no revertir el PR cerrado). NO arrancar el siguiente PR hasta cobertura 100%. El commit de cierre suele tener forma `test(...): cierre PR #N — test contract #X + ...`. Detalle completo de la regla en memoria del agente `feedback_inter_pr_audit.md`.
12. **Validar el FLUJO COMPLETO, no solo la mecánica aislada**. Una prueba de feasibility de una integración externa (pasarela, API de terceros) que confirma "el proveedor acepta X" NO basta si el cambio afecta el flujo dependiente: webhooks entrantes, UI/refresh, reconciliación de eventos. Una primitiva aceptada por el proveedor puede romper ese flujo (p.ej. cambiar el modo de facturación deja eventos `processed=f` huérfanos y la UI colgada). La Fase 0 debe ejercitar el camino end-to-end, no solo la llamada aislada.
13. **Adaptador = primitivas agnósticas; core = orquestación**. El provider/gateway concreto expone primitivas pass-through (lo que la API externa ofrece); la lógica de negocio y la orquestación viven en el core/servicio de dominio. Nunca meter decisiones de negocio (crear documentos, calcular importes, ramificar por caso) dentro del adaptador concreto — rompe Clean Architecture y acopla el dominio al proveedor.
14. **Mínimo cambio sobre rediseño**. Si algo "antes funcionaba" y solo falla un detalle (p.ej. el importe), corregir ese detalle, no reescribir el mecanismo entero. El rediseño amplía la superficie de regresión; preferir el fix acotado salvo justificación.
15. **No hardcodear criterio fiscal/legal/contable sin el experto**. Cuando una decisión depende de normativa (base imponible, devengo, retenciones, rectificativas), dejar el comportamiento neutro/conservador y **escalar la decisión** al asesor — no fijar un criterio por código razonando solo. Un criterio fiscal mal fijado puede causar doble-declaración u omisión.
16. **Autonomía vs consulta — sin spam de decisiones**. Autonomía por defecto para cambios acotados, reversibles y de bajo riesgo (fix puntual, test, doc). **Consultar ANTES** solo cuando hay: (a) decisiones de **arquitectura/diseño**, (b) cambios que tocan **muchas clases actuales con riesgo de regresión**, o (c) acciones **outward-facing** (publicar a repos compartidos, terceros). Reportar el plan no es preguntar por cada micro-paso.
17. **Consolidación de auditorías multi-agente — verificación independiente, nunca suma de conclusiones**. Cuando se lanzan varios agentes de auditoría independientes (p.ej. fullstack + arquitecto-vs-doc-oficial + dominio específico), la revisión final que las consolida **NO presupone que cada informe sea completo ni correcto** — cada agente tuvo **alcance restringido y conocimiento parcial** del sistema. Reglas de la consolidación:
    - **Verificar cada hallazgo de forma independiente contra el código real** (`archivo:línea`) antes de aceptarlo. Si un agente afirma un bug, reprodúcelo/confírmalo en el código; si no se sostiene, descártalo explicando por qué.
    - **Falsos positivos**: un hallazgo puede ser un no-problema por **contexto que ese agente no vio** (un guard de idempotencia en otra capa, una decisión fiscal/diseño ya cerrada, un invariante FK-first). Márcalos como descartados con la razón.
    - **Falsos negativos / gaps de costura**: al estar cada agente scopeado, puede haber riesgos que **ninguno** vio en las **intersecciones entre dominios** (membership↔ecommerce, webhook↔task, crédito↔pasarela). Audita esas costuras tú mismo.
    - **Contradicciones entre agentes**: resuélvelas con **el código como árbitro**, no por mayoría.
    - El informe final es **tu auditoría independiente** que usa los demás como insumos, con severidad recalibrada por ti — no un merge de sus conclusiones.
    - **Dato empírico (2026-07-19, doc 110)**: tres auditorías independientes (fiscal, cobertura, arquitectura) entregaron informes bien argumentados y con `file:line`, y aun así **3 de sus 4 riesgos "ALTO/MEDIO" no se sostuvieron al ejecutar** — uno inalcanzable (bloqueado por una validación), uno improbable (exigía +20 facturas por lifetime cuando el máximo real era 2) y uno inexistente (el comportamiento ya era correcto). El único real había sido detectado antes por una prueba manual del usuario. Moraleja operativa: **la lectura estática ve la FORMA del defecto** (`.first()` sobre una clave que puede repetirse, comparación por timestamp) **pero no si el escenario se produce ni si otra capa lo compensa**. Antes de aceptar un riesgo de un informe, reprodúcelo con una **sonda** (test desechable que reporta el comportamiento real sin afirmarlo) o mídelo con datos (`db:query`); cuesta minutos y evita tocar el núcleo de dinero sin necesidad. Lo mismo aplica a los importes de un informe: verifícalos ejecutando, no leyendo (en ese doc, la afirmación "los tests pasan por el cap" resultó falsa y cambió la estrategia entera del fix). (Aplica también a sub-agentes Explore/lectores dentro de un mismo agente: su resumen optimista puede mislabelar un hallazgo; la lectura directa del código manda.)
18. **Cobertura de la selección — verificar que el test se EJECUTÓ, no solo que el run "pasó" (anti-falso-verde)**. El comando de módulo del orquestador (`test:module <name>` o equivalente) resuelve los ficheros por **prefijo/glob** (p.ej. `test_<name>_*.py`). Un fichero de test cuyo nombre **no casa** ese patrón queda **silenciosamente excluido**: el run sale **verde sin haber ejecutado tu test** (falso verde — y peor si commiteas confiando en él). Reglas:
    - Tras CADA run con tests nuevos o modificados: confirmar que el test **se recogió** — el `collected N items` **subió** respecto al baseline **y** aparece la línea `ruta::Clase::test_x PASSED` **por nombre** en el log. `rc=0` + "X passed" **NO** prueba que TU test corriera; el contador puede ser el de otra selección.
    - Si tu fichero no entró en la selección, invocar con el nombre de módulo que **sí** casa el patrón, o apuntar al **fichero/expresión exactos** (`-k "<expr>"`), y re-verificar por nombre.
    - Vale para cualquier orquestador con resolución por patrón (prefijo, sufijo, marcador, path-glob): el conjunto que el comando ejecuta puede ser un **subconjunto** del que asumes — nunca inferir cobertura del número agregado.
19. **Factoría / reutilización PRIMERO — nunca clonar bespoke lo que ya existe**. Antes de escribir un componente, hook, servicio o mixin nuevo, comprobar si hay una **pieza de factoría** (componente/hook/mixin/servicio base reutilizable) que cubra el caso; si existe, **usarla o extenderla**, jamás duplicarla con una variante a medida (duplicar = divergencia, el riesgo nº1). Si la funcionalidad es **claramente escalable** (varias entidades/casos), **crear la factoría** (componente + hook + servicio/mixin asociados) en vez de una solución de un solo uso, aunque hoy solo haya un consumidor; si una factoría casi encaja, **generalizarla** (añadir un modo/opción) sin romper a sus consumidores, no clonarla. Un panel/servicio a medida que reimplementa la factoría es antipatrón → refactor. El plan-guardian (workflow G) debe verificar esto en §2 (diseño Service) y §7 (frontend). Detalle en el peer doc del proyecto (`CLAUDE.md §5 "Factoría / reutilización PRIMERO"`).
20. **Multi-idioma / SEO — factorías OBLIGATORIAS (parte de la arquitectura, respetar siempre)**. Traducir contenido dinámico, construir un editor admin multi-idioma o tocar SEO se hace SIEMPRE con las factorías, NUNCA bespoke: backend row-per-language (`TranslatableMixin`/`…RepositoryMixin`/`…ServiceMixin`) o **lateral** para entidades estructuradas (`LateralTranslationMixin`/`LateralTranslatableRepositoryMixin`/`LateralTranslatableServiceMixin`), ambas con `translation_resolver` + registro `content_field_protection`; frontend `useContentVariants(basePath,{lateral?})` + `ContentVariantBar` + `fieldGuard` + `ContentLanguageBadges`; SEO esquema B `services/seo/` (`SeoLang`) + `lib/seo/`. Si una factoría casi encaja, **generalizarla** (p.ej. `{lateral:true}`), no clonarla. El plan-guardian DEBE verificar: (a) editor con switcher + **auto-guardado al cambiar de pestaña** (secuencia canónica), (b) `fieldGuard` deshabilita los campos (C) en variante no-fuente, (c) proxy Express con `lang` en la clave de caché **y** reenvío de `?lang=` a Flask, (d) lista admin con dedup + badge `languages`, (e) idioma del structured data/meta **determinista del path** (no del selector). Contrato completo y errores recurrentes a bloquear: peer doc del proyecto (`ARCHITECTURE.md §22.4–22.7` + `CLAUDE.md §5` + `docs/analysis/095`/`096`).
21. **White-label / agnóstico al negocio — nunca asumir vertical**. El producto es white-label multi-tenant (sirve a gimnasio, clínica, despacho, estudio…). NUNCA asumir un tipo de negocio en código, UI, i18n, **placeholders**, ejemplos, labels, seed, docs ni defaults de schema. Prohibido texto/ejemplo de un vertical concreto ("gimnasio", "clínica", "Dr. med."/títulos médicos, "entrenador", "paciente" como ejemplo genérico); usar términos neutros ("profesional", "miembro del equipo", "cliente", "servicio"). Los campos vertical-específicos (p.ej. `medical_specialty`, `local_business_type`) se gatean/emiten por el `local_business_type` del tenant, nunca hardcodeados. Placeholders neutros o vacíos. El plan-guardian (workflow G) debe bloquear cualquier sesgo de vertical en §7 (frontend), §9 (i18n) y §11 (docs). Detalle en `CLAUDE.md §5 "White-label / agnóstico al negocio"`.
22. **Ningún cambio de comportamiento sin `test→red→fix→green` — y el test que confirma el rojo es E2E (workflow D). Los hotfixes NO están exentos.** Un bug fix de una línea, un "parche rápido" o una serie de hotfixes encadenados exigen lo mismo que una feature: (a) **baseline verde** de la suite relacionada; (b) un test **E2E que FALLE (rojo) capturando el bug ANTES del fix** — no basta un test post-fix que ya pasa, porque no demuestra que capture la regresión; (c) el fix; (d) el mismo test en **verde** + suite sin regresiones. El atajo "es solo un hotfix, lo verifico a mano y commiteo" es el antipatrón que esta skill previene: el arreglo manual sin test deja el bug sin red y reaparece.

    **Por qué E2E y no un unitario con mocks — éste es el detalle que decide si el ciclo sirve**: un test mockeado confirma el rojo **de tu hipótesis sobre el bug**, no el rojo **del sistema**. Escribes el mock según lo que crees que pasa, así que reproduce tu diagnóstico; si el diagnóstico era incorrecto o incompleto, el test se pone verde con el fix y el bug sigue vivo por el camino real — con el agravante de que ahora hay un test que "lo cubre" y nadie volverá a mirarlo. El rojo solo prueba algo cuando lo produce el camino que recorre el usuario: acción por **nuestro endpoint**, efectos esperados de los **eventos reales** del proveedor (invariante 36). Los tres bugs de la auditoría del invariante 37 estaban cubiertos por tests en verde; ninguno era E2E.

    **Qué cuenta como E2E aquí, sin ambigüedad**: un test **de API** que entra por nuestros endpoints HTTP y recibe los eventos **reales** del proveedor a través del sidecar `stripe-cli` (`test:stripe`). Todo lo demás no vale como rojo del sistema. Queda **terminantemente prohibido**, porque devuelve un verde falso: **inyectar webhooks** con payload propio, **escribir o retocar datos en la BBDD** para colocar el escenario, y **aserciones que no prueban el E2E** — comprobar lo que el propio test acaba de fabricar, envolverlo en `if`/`try` que puede no ejecutarse, o afirmar algo lateral en vez del hecho bajo prueba. Esas tres son las trampas del invariante 36, donde está el catálogo completo con sus casos reales; aquí se nombran porque el momento de caer en ellas es justo éste: con el bug delante y prisa por ver el rojo.

    **La secuencia es parte de la regla, no un formalismo**: el test se escribe y se **ejecuta en rojo antes de tocar el código**. Un test escrito después del fix —aunque sea E2E— no ha demostrado nunca fallar, y un test que no se ha visto fallar no se sabe si comprueba algo. Si al ejecutarlo en rojo falla por un motivo distinto del que esperabas, eso es diagnóstico nuevo: clasifícalo antes de seguir (invariante 35).

    **Y cuando el rojo no se llegó a ejecutar** —pasa, sobre todo con suites lentas donde uno escribe test y fix del tirón— la pregunta que de verdad protege no es *"¿viste el rojo?"* sino **"¿sabes que este test falla sin el fix, y CÓMO lo sabes?"**. Solo hay tres respuestas, y dos exigen trabajo:

    - **Lo viste fallar.** La mejor, y lo que se intenta siempre primero.
    - **Lo sabes por INVENTARIO, y es verificable con el grafo**: lo que el test exige sencillamente **no existía** —un campo que nadie escribía, una rama sin código, un código de error sin emisor— y lo comprobaste con `codebase-memory-mcp`. Ahí el rojo es deducible sin ejecutarlo, pero **se declara en el mensaje del commit** (p.ej. *"rojo deducido por inventario: nadie escribía `suspension_days_restored`, verificado con el grafo"*). Sin esa línea, quien lo lea dentro de seis meses no puede distinguir "no hizo falta" de "se me olvidó" — y esa duda vale tanto como no haberlo hecho.
    - **No lo sabes.** Entonces se aparta el fix y se ejecuta. Un test que pasa puede estar pasando por otra razón, y ésa es justamente la avería que esta regla existe para evitar.

    La frontera es dura a propósito: el inventario vale cuando la **ausencia** es objetiva y quedó comprobada, no cuando la intuición dice que "eso seguro estaba mal". Un cálculo incorrecto, una condición que no cubría un caso o un orden de operaciones equivocado **no** son ausencias: son hipótesis sobre el comportamiento, y ahí es exactamente donde el diagnóstico suele estar incompleto. Se ejecuta.

    **Cuando el E2E no alcanza el caso** (el proveedor no permite provocar el hecho, el camino exige interacción de navegador): no se sustituye en silencio por un unitario y se sigue. Se **declara** —igual que el invariante 36 exige para lo no migrable—, se sondea antes de darlo por imposible, y si aun así no hay vía, el unitario que se escriba en su lugar lleva escrito **qué parte del camino real NO cubre**. Complementar el E2E con unitarios para casos borde es bueno; **reemplazarlo** es perder la garantía.

    **Excepción única**: cambios que **no tocan comportamiento** (doc, release notes, script de deploy, rename de comentario) — ahí no hay red que escribir. El coste de los E2E es real (son lentos, `stripe_heavy`), y aun así sale barato: los 40-88 días de exposición del invariante 37 los produjo exactamente la confianza en tests que pasaban sin recorrer el camino del usuario. Si el usuario dice "hotfix" o encadena varios, **auto-activarse en cada uno** (ver frases gatillo del `description`), no solo en el primero.
23. **Guardian de invalidación de caché en frontend (mutación → estado compartido stale)**. Toda mutación (cancelar, reembolsar, aprobar, cambiar estado, borrar) que altere un **estado derivado/compartido que otra vista muestra** (saldo/créditos en el navbar, contadores, badges, resúmenes en otra pantalla) DEBE **invalidar la clave de caché del cliente** (p.ej. `queryClient.invalidateQueries({queryKey})`) tras la operación — un `fetch` local de la propia lista **no** refresca las demás superficies. Síntoma del bug: "se queda desactualizado / no se refresca hasta hacer hard-refresh". El plan-guardian (workflow G §7 frontend) debe verificar: por cada mutación, **listar TODAS las vistas que muestran el estado afectado** (usa la MISMA query/hook) y confirmar que todas se invalidan; la invalidación por **prefijo de clave** cubre las variantes con parámetro (`["x"]` invalida `["x", id]`). Corolario de cobertura: cuando una **familia de factoría** tiene test por miembro (p.ej. `test_<entidad>_translation_api.py` por cada entidad traducible), un miembro **sin su test** es un gap — el editor/entidad que carece del test suele ser justo donde se cuela el bug (auditar "el único miembro de la familia sin su test").
24. **Enlaces de confirmación por email = IDEMPOTENTES (no consumir el token de un solo uso)**. Todo flujo de verificación por enlace de email (verificar cuenta, reset de contraseña, confirmar cita, magic link) NO debe **anular/borrar el token** en el primer hit; la idempotencia se apoya en un timestamp `*_verified_at` (o estado equivalente): re-confirmar un recurso ya verificado es un **no-op que devuelve "ya verificado"**, nunca un `NOT_FOUND`/"Invalid or expired token". **Por qué (síntoma SOLO en producción)**: los escáneres de seguridad de email corporativos (Outlook/Defender **Safe Links**, Mimecast, Proofpoint…) **PRE-CARGAN** los enlaces al entregar el correo → consumen el **1er hit** → el click real del usuario es el **2º** → si el token era de un solo uso, falla. En dev no hay escáner, así que no se reproduce (trampa clásica). La caducidad por **tiempo** (`*_expiry_hours`) sí es válida para invalidar; el consumo del token NO. Test obligatorio: **confirmar dos veces con el mismo token → el 2º devuelve 200 "already_verified"**, no 404. Si encuentras un test que asserta el 404 del 2º hit, está **documentando el bug** — corrígelo al comportamiento idempotente.

25. **Dynamic rendering = DOS documentos por URL — identifica cuál mira tu observador ANTES de diagnosticar**. En un stack con dynamic rendering (bots → HTML server-rendered "meta-html"; navegadores → shell SPA hidratado por JS), cada URL pública existe como **dos documentos distintos** — con contenido, `<html lang>`, landmarks, meta tags e incluso status/redirects diferentes. Cualquier diagnóstico, fix o verificación que dependa del "HTML servido" (SEO, a11y, OG/previews, redirects, hallazgos de herramientas externas) es ambiguo hasta responder: *¿qué documento recibe este observador?* Respóndelo **empíricamente** — `curl -A "<UA real del observador>"` contra la URL y mirar qué vuelve — nunca por asunción. Claves de mapeo: Search Console / PageSpeed / "URL Inspection" auditan el documento de **Googlebot** (meta-html); Lighthouse lanzado desde el navegador audita la **SPA**; los scrapers sociales y bots IA reciben meta-html; los tests de front ejercitan la SPA y los de `test:module geo` el meta-html. **Por qué (dos fallos reales el mismo día, 2026-07-13/14)**: (a) un hallazgo de a11y de Search Console se "arregló" en la home de la SPA y persistió tras el deploy — el landmark faltaba en el meta-html, que era el documento auditado (la pista ignorada: el elemento reportado, `<html lang="fr">`, solo existía server-side); (b) un cambio de contrato del meta-html (301 del alias desnudo) se verificó contra bots pero rompió a un **consumidor interno** del mismo endpoint (el preview del admin), que nadie inventarió. Reglas: (1) ante un hallazgo de herramienta externa, identificar su UA y reproducirlo con curl ANTES de tocar código — el elemento/valor reportado suele delatar qué documento es; (2) al cambiar el contrato del meta-html (status, redirects, estructura del head/body), **inventariar TODOS sus consumidores** — bots externos E internos (`grep -rn "meta-html" client/ server/`) — y cubrirlos en el mismo PR; (3) todo fix "a la página X" declara explícitamente a cuál de los dos documentos aplica (o a ambos) y su test rojo→verde ejercita **ese** documento.

26. **Gestión de ramas LINEAL — una rama de trabajo cada vez, sin stacks de PRs**. Decisión del usuario/arquitecto (2026-07-14): se trabaja en UNA rama; su PR se mergea (y la rama se borra) ANTES de abrir la siguiente. **PROHIBIDO** encadenar PRs cuyo base sea la rama de otro PR (stacked PRs): GitHub **auto-CIERRA sin mergear** un PR cuando su rama base se borra al mergear el PR de debajo — pérdida real 2026-07-14 (PR #79 quedó CLOSED con su contenido fuera de main; consolidación manual en PR #81). Si un trabajo depende de otro aún sin mergear: esperar al merge, o incluir ambos en la MISMA rama como commits secuenciales (un doc de análisis y su primera implementación pueden compartir PR si se mergean juntos). Cerrar cada bloque = merge + borrar rama antes del siguiente.
27. **Descubrimiento de código — el grafo NO es una preferencia, es el método; `grep` sobre código es fallback de urgencia y se declara como tal.** Siempre que se **audite, diagnostique o modifique CÓDIGO** —auditoría, bug, hotfix, feature nueva, refactor, revisión de tests, inventario de llamadores del invariante 37— la exploración se hace con el MCP de índice/grafo (`codebase-memory-mcp`: `search_graph`, `trace_path`, `get_code_snippet`, `query_graph`, `get_architecture`). No es "la primera opción recomendada": es **la que responde la pregunta**. Si el proyecto no está indexado, `index_repository` **primero**; si el índice está frío, refrescarlo cuesta menos que el error que evita.

    **Por qué es una regla dura y no una preferencia**: grep responde *"dónde aparece este texto"*, y ninguna pregunta de auditoría es esa. Las que importan —quién llama a esto, qué se rompe si lo cambio, qué tests cubren este camino, por dónde fluye este dato— son preguntas sobre el **grafo**, y el texto solo las aproxima. Falla en las dos direcciones y **las dos son caras**: da **falsos positivos** (el nombre aparece en un comentario, un string, un test muerto, otro módulo homónimo) y, mucho peor, **falsos negativos** — el llamador que usa un alias del import, la llamada dinámica, el reexport, la herencia, el decorador que envuelve. Un falso positivo cuesta tiempo; un falso negativo es exactamente el punto que se queda con la regla vieja y produce el defecto silencioso del invariante 37. Un inventario hecho por grep **parece completo y no lo está**, y esa es su propiedad peligrosa.

    **Dónde `grep`/`Read` siguen siendo lo correcto, sin disculpas**: TEXTO y ficheros no-code — i18n, configs, docs, plantillas, SQL de migración, logs de un run, el bug tracker, `docker ps`. Ahí el grafo no ve nada y el texto ES la respuesta. La frontera es simple: *¿pregunto por una relación del código, o por una cadena de caracteres?*

    **Protocolo de fallback (MCP caído, clon sin indexar, sesión headless)**: se puede usar `grep`, pero entonces (a) se **amplía deliberadamente** el patrón —nombre suelto además del cualificado, alias de import, el símbolo sin el prefijo del módulo— porque el riesgo real es lo que NO sale; (b) se **declara en el entregable** que la cobertura es parcial y por qué, con una frase explícita del tipo *"inventario por búsqueda textual, MCP no disponible: puede omitir llamadas dinámicas, alias y reexports"*; y (c) si la decisión que depende de ese inventario es de dinero, fiscal o lifecycle, **no se cierra** sobre el resultado del grep: se reintenta con el índice antes de dar el trabajo por hecho. Un inventario incompleto presentado sin ese aviso es peor que no haberlo hecho, porque el siguiente lector lo tratará como exhaustivo.

    **La herramienta es `codebase-memory-mcp` — el MCP del índice del código— y el índice tiene que estar FRESCO.** Se consulta con sus tools (`search_graph`, `trace_path`, `get_code_snippet`, `query_graph`, `search_code`, `get_architecture`) y se refresca con `index_repository(repo_path=..., name=<proyecto>)`, que EXIGE la ruta del repo — en un worktree, la del worktree y no la del checkout principal. **Se reindexa ANTES de consultar para decidir, no después de cada edición** — reindexar tras cada commit es trabajo que a menudo nadie aprovecha; lo que no puede fallar es que la consulta en la que fundamentas un cambio se haga sobre el código real. Disparadores: al abrir un frente de trabajo sobre código que la sesión ya tocó (auditar, diagnosticar, inventariar llamadores, decidir un fix); antes de delegar en un subagente, al que hay que darle el nombre del proyecto y avisarle si reindexas a mitad; y después de un merge, rebase o cambio de rama, porque el árbol es otro y el índice no se entera. La pregunta que decide: *¿voy a apoyar una decisión en lo que el grafo me diga?* Si sí y el código cambió, reindexa primero. Un índice construido antes de tus propias ediciones describe un código que ya no existe, y responde con la misma seguridad que si estuviera al día — por eso es más peligroso que no tenerlo. Si la sesión ha tocado ficheros (tuyos o de otro agente), **reindexa antes de volver a consultar**, y comprueba la frescura **por SÍMBOLO** —busca algo creado en esta sesión— y no por el SHA, que puede coincidir con un índice a medias. Al delegar en un subagente, dile qué proyecto del índice usar y avísale si reindexas a mitad: sus consultas anteriores describen otro código.

    **Lo que `codebase-memory-mcp` da y `grep` no puede dar**, y que es la razón de fondo para no tratarlos como intercambiables: además de las relaciones, devuelve el **docstring, la firma, los llamadores y el grado** de cada símbolo. Ahí es donde suele estar la decisión ya tomada. **Caso real (2026-07-29)**: ante la pregunta "cómo devolver los días de una suspensión", `grep` y el grafo señalaron exactamente **las mismas líneas** — pero solo el grafo mostró el docstring de `resume_membership`: *"NO manipula la fecha de renovación de la pasarela: se acepta su reloj nativo"*. Es decir, la política que el proyecto ya había fijado. Con el resultado de `grep` se habría propuesto justo lo contrario de lo acordado, y con toda la apariencia de estar fundamentado. El fallo no fue no encontrar el código: fue no ver **por qué** estaba escrito así.

    Detalle y guard "si está disponible" en el peer doc (`CLAUDE.md §5 "Búsqueda de código"`).
28. **UI frontend (React) — cargar la skill `frontend-design` ANTES de escribir el código visual**. Cuando una feature/fix toque UI (pantalla/componente nuevo, rediseño, o cambios de maquetación/estilos: contraste, alineación, jerarquía o consistencia de botones, spacing), cargar y seguir la skill **`frontend-design:frontend-design`** antes de codificar lo visual. Es una skill de PLUGIN de `.claude` (se invoca por su nombre; no aparece en `skills:list`). El plan-guardian (workflow G §7 frontend) debe verificar que se aplicó: contraste con **tokens semánticos** (no colores hardcoded), jerarquía tipográfica intencional, **botones consistentes/equilibrados** —en flujos de consentimiento/decisión, "aceptar" y "rechazar" con la MISMA prominencia, nunca dark patterns—, spacing preciso, responsive + focus visible. Aprendizaje del proyecto (doc 108 PR-2, rediseño del banner de cookies; decisión del usuario 2026-07-18). Detalle en el peer doc (`CLAUDE.md §5 "Diseño / UI nueva"`).
29. **ACOTAR el sistema es un fix legítimo — mide el ALCANCE antes de arreglar un caso borde**. Este proyecto resuelve clases enteras de problemas **restringiendo lo que el sistema permite** (membresía = siempre recurrente, switch solo entre planes del mismo intervalo, solo política `immediate`…). Consecuencia directa para el trabajo de diagnóstico: **un defecto real en un camino que el sistema ya no permite alcanzar es deuda registrada, no un fix**. Antes de tocar código —sobre todo de dinero, fiscal o lifecycle— comprueba empíricamente si el escenario puede producirse hoy: consulta los datos (`db:query`), busca la validación que lo bloquea, o escribe una **SONDA** (test desechable que reporta el comportamiento real sin afirmar nada) para medirlo. Y al diseñar el fix, evalúa la restricción como alternativa al código defensivo: si el caso problemático no aporta valor de negocio, prohibirlo en el punto de entrada (validación, guard de policy, gate de UI) elimina la clase entera y es más barato y más testeable que sembrar ramas defensivas por todo el lifecycle. Dos cautelas: (a) acotar vale cuando el caso restringido **no debe existir** — si es legítimo y el sistema lo permite hoy, hay que arreglarlo de verdad, no taparlo; (b) toda restricción se documenta donde el usuario la vive (manual + mensaje de error accionable con la alternativa), no solo como `ServiceResult.fail`. **Caso real (2026-07-19)**: una auditoría marcó como riesgo ALTO el cancel de membresías de pago único; verificado con sonda, el defecto existía pero el escenario es **inalcanzable** desde que el intervalo de facturación es obligatorio → se documentó con la dirección del fix y NO se tocó código. La verificación costó minutos; el fix habría tocado el núcleo del cálculo de reembolsos sin necesidad. Detalle en el peer doc (`CLAUDE.md §5 "ACOTAR el sistema es un fix legítimo"`).

30. **Si falta el dato, EXTENDER EL MODELO — nunca resolver con heurísticas**. Cuando una decisión de negocio necesita un dato que el modelo no guarda, lo correcto es **crearlo** (columna, FK, tabla puente + migración), no inferirlo. Quedan **prohibidas por inferencia** las resoluciones tipo "última fila por clave" (`.order_by(id.desc()).first()`), comparaciones por timestamp, ventanas (`limit(N)`), tolerancias (±1h) y repartos proporcionales/probabilísticos: fallan en los casos límite (clave repetida, concurrencia, reordenación, backfill) y **fallan en silencio** — devuelven un valor plausible en vez de un error. Una FK es determinista y se rompe ruidosamente. En este proyecto sale barato: dev sin usuarios reales, migraciones que corren en dev y sin backfill (§"Estado del proyecto"). **Para el plan-guardian (workflow G) y para cualquier doc de análisis**: si la propuesta usa una heurística, debe **justificar explícitamente por qué NO se extiende el modelo**; sin esa justificación el diseño no está cerrado. Preferir además el dato **al momento del hecho** (snapshot en el evento: id de la transacción de pasarela, id del ciclo, importe aplicado) sobre recalcularlo después — lo que no se guarda cuando ocurre, luego solo se estima. Regla de olfato al revisar código o tests: si una query "acierta casi siempre", falta un dato, y ese *casi* es el bug que llegará a producción. **Cómo se resuelve la duda —para no confundirlo con "añadir columnas por si acaso"—: la disyuntiva real es "¿persisto el dato con FK, o lo deduzco con un proceso?", y ante la duda gana SIEMPRE la FK.** Motivo: el dato con FK es determinista, la integridad la garantiza la BD y, si falta, **falla ruidosamente**; el proceso que lo deduce depende del estado en el momento de ejecutar, no tiene constraint que lo proteja y, cuando su supuesto deja de cumplirse, devuelve un valor **plausible pero incorrecto en silencio** — el fallo más caro de depurar. **Cuándo NO aplica**: si ya hay una FK que responde la pregunta (úsala), o si el valor es derivable **sin ambigüedad** — una suma sobre filas ya ancladas por FK es una agregación determinista, no una heurística. Lo prohibido son las inferencias que *eligen* una fila (`.first()` sobre clave repetible) o *estiman* un valor (tolerancias, proporciones), no el cálculo sobre datos ya anclados. Complementa el invariante FK-first: aquél dice *apóyate en FK*; éste, *y si no existe, créala en vez de deducirla*. Detalle en el peer doc (`CLAUDE.md §5 "Si falta el dato, EXTENDER EL MODELO"`).


31. **Un test rojo puede estar describiendo un mundo que ya no existe** — triaje ANTES de tocar código. Ante un fallo, clasificarlo primero en una de tres categorías, en este orden: **(1) bug real** → se arregla el código; **(2) escenario ya restringido** → el test ejercita un camino que el sistema ya no permite (ver invariante de acotar) → se acota o retira el test y se **documenta** que es inalcanzable, sin tocar producción: parchear ahí es trabajo perdido y siembra ramas defensivas en caminos muertos; **(3) infraestructura** → entrega de webhooks, estado residual, sesiones solapadas → aislar y reintentar antes de diagnosticar nada. **El síntoma de fondo es la deriva silenciosa**: cuando se añade una restricción, los tests se adaptan en el **código** pero sus **docstrings, nombres de clase y comentarios** siguen describiendo el comportamiento anterior; como el test pasa, nadie los relee — hasta que uno falla y su documentación manda la investigación en dirección contraria. De ahí la regla operativa: **al añadir una restricción, actualizar docstrings y nombres de los tests del área EN EL MISMO COMMIT**, no solo las aserciones; y al diagnosticar un rojo, **leer el docstring y contrastarlo con las restricciones vigentes antes que el código** — si describe algo que hoy el sistema rechaza, la documentación es sospechosa primero. Un docstring obsoleto es deuda: corregirlo en cuanto se detecte, aunque el test pase. Casos reales (2026-07-19/20): el cancel de membresías de pago único, defecto real en un camino **inalcanzable** desde que el intervalo es obligatorio (se documentó, no se tocó código); y `TestPath2DoubleSwitchRefundCancelImmediate`, cuyo docstring seguía describiendo `weekly→monthly→monthly` pese a que el cambio entre intervalos está bloqueado desde 2026-07-17 y el código del test ya se había adaptado. Detalle y política completa en `docs/analysis/053_testing_guide_and_stripe_paths.md` → "Política: un test rojo puede estar describiendo un mundo que ya no existe".

32. **Un fallo crítico no se resuelve escondiéndolo — nada de auto-fixes/self-healing sobre causas sin diagnosticar.** Cuando el sistema detecta un estado inconsistente (un contador que no cuadra con los documentos emitidos, un saldo que diverge, una referencia rota), la tentación es que el código lo "repare" al vuelo y siga. Resistirla: **cada auto-fix silencioso borra la evidencia de una causa que alguien necesitaba encontrar**. Un código repleto de auto-reparaciones "funciona" mientras la deuda crece invisible — las causas dejan de aflorar, cada síntoma nuevo se tapa con otro parche porque ya no se distingue el origen, y el resultado es spaghetti: parches que compensan parches. La resolución correcta tiene tres capas, en este orden: **(1) PREVENIR** el estado inválido en su punto de entrada (guard/bloqueo de la operación que lo produce — con mensaje accionable, no solo un fail); **(2) EXPONER** la inconsistencia donde el operador la vea (alerta en la UI que administra ese estado, log de warning con datos concretos) para que se resuelva CON diagnóstico; **(3)** dejar que el fallo residual sea **RUIDOSO** (constraint de BD, excepción clara) — la colisión es la última red, no un caso a absorber. **Cuándo un valor por defecto SÍ es legítimo**: inicializar lo que NUNCA existió (lazy-init de un dato nuevo, sin estado previo que ocultar) o la idempotencia de reintentos — la línea roja es *reparar lo que se corrompió*: si el valor "curado" reemplaza a uno que debió existir y no existe, se está borrando la evidencia. Emparenta con "detectar antes que bloquear" (aquél evita bloquear flujos legítimos por defensas especulativas; éste evita CURAR estados corruptos en silencio) y con el invariante 30 (un fallback plausible es la variante runtime de la heurística que acierta *casi* siempre). Caso real (2026-07-21, BUG-165): el contador de numeración de pedidos desapareció con documentos vivos → 500 por colisión en el checkout; se propuso un self-healing (sembrar el contador desde el máximo emitido al crear la fila) y el usuario lo RECHAZÓ explícitamente — la solución final fue el guard del reset (409 con documentos emitidos, botón bloqueado en la UI con el motivo), la alerta "contador inconsistente" en el tab Numeración, y la colisión ruidosa como red final; la causa (un reset con documentos vivos) quedó identificable en vez de enterrada bajo una reparación.

33. **Un setting de FAMILIA CONSOLIDADA vive en N LISTAS ESPEJO — el fix en una sola capa NO cierra el bug.** Las familias de claves consolidadas (p.ej. `email_auto_send_*`) se declaran en VARIOS puntos que deben moverse JUNTOS: (1) el **mapa del servicio consumidor** (qué clave gobierna cada acción — p.ej. `AUTO_SEND_SETTINGS_MAP` del servicio de email); (2) la **whitelist ESTRICTA del backend** (`setting_registry` — el namespace rechaza claves no registradas, así que el PUT se descarta EN SILENCIO); (3) la **whitelist del frontend** (el Set que filtra qué claves acepta/emite la UI — p.ej. `ALLOWED_AUTO_SEND_KEYS` — más el descriptor del toggle y sus labels i18n en N locales). El síntoma es siempre el mismo y engañosamente simple: **"el setting nuevo no persiste"** — la UI parece guardar y al recargar vuelve al default, sin error visible en ninguna capa. Por qué es traicionero: cada capa filtra en silencio por diseño (forward-compat, anti-typo), así que arreglar la capa que encontraste primero produce un "ya está" falso — y la siguiente ronda de validación manual del usuario vuelve a fallar igual (coste real 2026-07-23: TRES capas desincronizadas para `email_auto_send_dispute_opened_admin`, DOS rondas de re-prueba quemadas — el sprint origen pobló solo el mapa del servicio; el primer fix añadió solo el registry). Reglas operativas: (a) ante "no persiste", **grep de una CLAVE HERMANA que sí funciona** — la lista de sitios donde aparece la hermana ES el checklist de la nueva; (b) el fix no se da por cerrado sin verificar el flujo **end-to-end** (PUT+GET por API y recarga de la UI — caso concreto del invariante 12); (c) al crear una familia consolidada nueva o detectar este patrón, dejar un **test de coherencia entre listas** que exija mapa-del-servicio ⊆ registry (p.ej. `test_email_auto_send_registry_coherence`) — la capa frontend no es alcanzable desde pytest, así que el grep de la hermana sigue siendo obligatorio para ella.

34. **La release note se escribe EN EL MISMO COMMIT que el cambio — no al mergear, no al taggear, no "al final del bloque".** La regla operativa completa vive en [workflows.md](workflows.md) §"Mantenimiento de `RELEASE_NOTES.md`"; está aquí, entre los invariantes, porque el momento en que hay que recordarla es **al cerrar cada commit**, y esa sección solo se carga al invocar el workflow de release — demasiado tarde. Al cerrar un commit con efecto user-facing, se añade o ajusta su bullet bajo `## Unreleased` en ese mismo commit, de modo que el bloque refleje en todo momento lo que hay sin publicar. **Por qué**: la nota redactada en caliente, con el porqué del cambio aún fresco, sale fiel; redactarlas todas de golpe al final degrada el trabajo a arqueología del log —se pierden los matices de por qué algo importaba al usuario— y, peor, empuja a escribirlas de memoria, que es justo lo que esta skill prohíbe (las notas salen SIEMPRE del log del rango). Aplica igual a `fix(...)` que a `feat(...)`: un bugfix cambia el contrato observable y es control de cambios, no un detalle interno. Señal de que lo estás incumpliendo: te encuentras redactando varias entradas seguidas en un commit `docs(release-notes)` separado, releyendo `git log` para reconstruir qué hacía cada cambio — en ese momento ya has perdido el contexto que hacía valiosa la nota. Excepción natural: los commits sin efecto observable (refactor interno, tests, docs) no necesitan bullet, o llevan una línea en `Notes` si conviene dejar rastro.

35. **Ante un test en ROJO, la clasificación se escribe ANTES de tocar el test — y se lee el log ENTERO del run AISLADO, no solo la ausencia que reporta el aserto.** El invariante 31 dice en qué categorías clasificar (bug real / escenario restringido / infraestructura); éste dice *cuándo* y *con qué evidencia*, porque ahí es donde se falla en la práctica. La clasificación se apoya en evidencia **independiente del propio test**: el log del run aislado, el objeto en la pasarela, el código de producción, la doc oficial. **Por qué hace falta decirlo**: el impulso contrario siempre gana por velocidad — formular una hipótesis y ajustar el aserto devuelve el verde en un minuto; investigar cuesta diez y puede abrir un frente nuevo. Ese atajo es exactamente el que produce los tests que luego hay que migrar, así que tomarlo *mientras migras* es especialmente absurdo. **El fallo tiene DOS caras y conviene reconocerlas ambas**: (a) **tapar** — quitar o relajar el aserto porque falla, que entierra el bug; y (b) **precipitarse al revés** — declarar "bug de producción" con evidencia parcial, que envía a alguien a arreglar lo que no está roto. Las dos salen del mismo apuro por concluir. **La regla que las evita**: la ausencia que reporta un aserto solo dice *"no estaba cuando miré"*; no distingue entre *nunca se creó*, *llegó tarde* o *está bajo otra clave* — tres diagnósticos opuestos con idéntico síntoma. Solo el log completo del run aislado lo resuelve. **Caso real (2026-07-26, migración E2E)**: un test nuevo falló porque no encontraba la entrada de auditoría `proration_credit`; se llegó a afirmar "laguna de auditoría real" y a redactar la entrada del tracker… cuando el log aislado contenía `proration_credit_audit_entry_created`. La entrada existía; el test se adelantaba a comprobarla. Antes, en el mismo test, se había cambiado un aserto por otro asumiendo un artefacto (`billing_reason='subscription_update'`) que solo produce el camino viejo. **Corolario E2E, que es la causa concreta más frecuente**: *cada hecho verificado debe ESPERARSE*. Los efectos de una acción llegan en eventos distintos y en momentos distintos; esperar uno y comprobar otro al instante hace que el test se adelante y produce exactamente el falso rojo de arriba. **Y el patrón hermano**: un defecto detectado *de refilón* mientras haces otra cosa se repara en el momento o se convierte en tarea — nunca se queda "anotado mentalmente"; el mismo día se acumularon dos recaídas por ese "lo apunto y sigo", y ambas se descubrieron con el grafo, no ejecutando.

36. **Un test de integración E2E contra un proveedor externo NO fabrica ningún hecho: los produce el entorno real y nosotros solo los observamos.** Éste es el invariante de **diseño** — el 35 gobierna cómo diagnosticar un rojo y el 31 cómo triarlo; éste dicta cómo se construye el test desde cero, de modo que aquellos hagan falta lo menos posible. Aplica a pasarelas de pago, mensajería, logística o cualquier integración por webhooks. Solo dos herramientas: **la API de nuestra app** y **el canal real del proveedor** (su CLI/sidecar de reenvío, su sandbox, su reloj de pruebas). **El reparto**: las **ACCIONES** se disparan por donde las dispara el usuario o el operador —nuestro endpoint— porque la app registra estado propio (intents, FK) del que dependen decisiones posteriores; los **EFECTOS** se esperan de los eventos que el proveedor emite de verdad. Los hechos que **nacen en el proveedor** (una renovación por ciclo, un impago, una disputa, una sesión que caduca) se provocan **allí**: avanzando su reloj, con un medio de pago que falla, con una tarjeta que abre disputa.

    **Por qué**: un test que fabrica el hecho que dice verificar no prueba la integración — prueba nuestro parser contra nuestro propio JSON. Si el proveedor cambia dónde coloca un dato, producción se rompe y el test sigue verde. No es hipotético: así se coló un fallo de parsing de disputas con la suite entera en verde.

    **El catálogo de trampas, en orden creciente de gravedad** (todas observadas en tests reales del proyecto, no imaginadas):
    - **Inventar el evento**: enviarse un webhook con payload propio. El caso base.
    - **Inventar identificadores**: `ch_test_…`, `re_test_…`, `evt_dedup_…` que no existen en el proveedor. Peor, porque el handler recibe algo que jamás podría resolver contra la API real.
    - **Servirle al sistema el dato que debe extraer**: pasarle en el payload el `receipt_url` que el contrato dice que hay que sacar del evento. Verifica que sabemos leer lo que nosotros mismos escribimos.
    - **Entrar por la puerta de atrás**: llamar a un método privado del servicio en vez de al endpoint. Se salta permisos, validación y el resultado que la ruta devuelve — justo lo que el operador atraviesa.
    - **Hacer el trabajo que el sistema debe hacer**: calcular el reparto de un reembolso entre cargos y emitirlos, y después comprobar que hay varios. Verifica la aritmética del propio test; si el sistema dejara de repartir, seguiría verde.
    - **Escribir en la BD lo que la configuración prohíbe**: fijar una política restringida saltándose su validación. Certifica en verde una funcionalidad deliberadamente deshabilitada (ver invariantes 29 y 31).
    - **Aserciones que pueden no ejecutarse**: todo el cuerpo dentro de un `if` cuya condición depende de datos inventados, o envuelto en un `try/except` que loguea y deja pasar. El test termina en verde sin haber comprobado nada.

    **Excepción legítima, estrecha y que se documenta**: reentregar el evento **auténtico** del proveedor (recuperado de su API, con su identificador real) cuando el caso bajo prueba *es* la reentrega — probar idempotencia frente a reintentos exige repetir el mismo evento, y provocar un reintento real requeriría devolverle un error al proveedor y esperar su reloj interno. El evento sigue siendo real; solo cambia la vía de entrega. Lo mismo vale para un reenvío de recuperación cuando el orden de llegada falló. Lo que **no** es excepción es fabricar el contenido.

    **Cuando no se puede provocar el hecho de verdad** (p.ej. el proveedor no permite completar por API un flujo pensado para navegador): eso NO autoriza a inventarlo en silencio — se declara **no migrable**, se deja la inyección con un comentario que explique por qué es inevitable, y se sondea antes de darlo por imposible. Un sondeo de diez minutos ha desmentido más de una vez la creencia de que "esto no se puede provocar": el evento sí se emitía, y el test llevaba meses fabricándolo sin necesidad.

37. **Al cambiar un invariante GLOBAL, el inventario de lo que depende de él se hace ANTES y se trata en el MISMO commit — incluidos los tests que verificaban la regla anterior.** Cambiar un invariante global es añadir un guard que aborta, sustituir un camino por otro, o restringir una configuración a menos valores de los que admitía. Lo que los hace peligrosos es que su alcance **no es el fichero que estás editando**: es el conjunto de puntos que asumían la regla vieja. La pregunta obligatoria antes de cerrar el commit es una sola: *¿qué otros puntos dependen del invariante que estoy cambiando, y qué tests lo verifican?* Se responde con el **grafo de llamadas** (invariante 27), no de memoria ni a golpe de grep.

    **La señal de que el patrón ya falló**: te encuentras parcheando el **segundo** caso en un commit aparte. Si el primer punto necesitó propagación manual, el resto también la necesita — y no van a aparecer solos: aparecerán como incidencias, de una en una y meses después. En cuanto detectes ese segundo parche, para y haz el inventario completo.

    **Por qué se escapa**: el cambio se aplica donde el autor está mirando; el resto queda con la regla vieja **y en verde**, porque sus tests siguen afirmando el comportamiento anterior. No hay rojo que avise. El defecto no aflora hasta que alguien recorre justo ese camino — y para entonces el commit que lo causó está enterrado bajo meses de historial. Por eso los tests son parte del inventario y no una tarea posterior: un test que sigue forzando la configuración que acabas de prohibir certifica en verde un mundo que ya no existe (invariante 31).

    **Cómo se hace, en concreto**: (a) **los llamadores**, con el grafo — `trace_path` sobre la función que cambia y `search_graph` por su nombre cualificado; el grep queda para lo que el grafo no ve (plantillas, i18n, SQL de migración). (b) **Los tests**, buscando quién afirma la regla vieja: el nombre del setting, el valor que acabas de prohibir, la fixture que lo fuerza — es donde más se falla, y es lo que dejó a BUG-183 sin una sola red. (c) **Los puntos hallados no se tratan todos igual**: unos propagan el dato que ahora hace falta, otros se **acotan** si el camino ya no debe existir (invariante 29), y otros se documentan como inalcanzables (invariante 31). Lo que ninguno puede quedar es sin decisión.

    **Si el inventario no cabe en un commit** —cuarenta llamadores no se arreglan de una sentada— la regla no se rompe, se cumple a medias a propósito: **el inventario completo sí va en ese commit**, como lista explícita en el tracker o en el cuerpo del mensaje, y el tratamiento se reparte. Lo prohibido no es tardar en arreglarlos; es **no saber cuántos son**, porque entonces no hay diferencia entre "quedan seis" y "creo que ya está".

    **Caso real — no es una hipótesis, es una auditoría (2026-07-26)**: BUG-181, BUG-182 y BUG-183 no eran tres descuidos sueltos; comparten esta forma exacta.

    | Bug | Origen | Qué quedó fuera | Días expuesto |
    |---|---|---|---|
    | BUG-181 | `2e402e3f7` — guard que ABORTA si `amount < plan.price` sin `gateway_payload` | el camino de **renovación** no propaga el payload | 85 |
    | BUG-182 | `9360f621e` — unificación PayPal: `finalize_subscription_termination` **con** guard | `cancel_membership` (5 entradas) se quedó **sin** guard | 88 |
    | BUG-183 | `fc21b7c9c` — `choices=("immediate",)` | **cero tests actualizados**: 6 seguían forzando las policies retiradas | 40 |

    En BUG-181 la señal estuvo desde el primer día: el guard se introdujo propagando el payload en un camino y **el mismo día** hizo falta otro commit (`3b8531031`) para el segundo. El patrón "guard global + propagación caso por caso" ya había fallado en cuestión de horas; aun así el tercer caso sobrevivió 85 días. Los tres se localizan con el grafo **en segundos** — así aparecieron BUG-182 y BUG-183, sin ejecutar un solo test.

    **Frontera con el invariante 33, para saber cuál aplicar**: aquél cubre las **familias de claves declarativas** (un setting que vive en N listas espejo) y su síntoma es "no persiste" — la UI parece guardar y al recargar vuelve al default; éste cubre los **invariantes de comportamiento** (guards, caminos, restricciones) y su síntoma es el silencio: nada falla, ni siquiera en los tests, hasta que un usuario pisa el camino olvidado. Comparten mecanismo (N puntos que deben moverse juntos) y cura (inventariar antes, no parchear según aparezcan).

38. **El bug que aparece de refilón se ARREGLA en la misma rama, aunque no tenga nada que ver con lo que estabas haciendo.** Trabajando sobre un fix o una feature se tropieza con defectos ajenos: una heurística en un cálculo vecino, una clave duplicada, una pantalla que asume un proveedor. La reacción instintiva —"lo apunto y sigo"— parece disciplina de foco y es justo lo contrario: un bug anotado sin fecha ni dueño es un bug que **nadie va a arreglar**. La disciplina real es arreglarlo mientras tienes el contexto en la cabeza.

    **Por qué el momento importa más que el esfuerzo**: cuando lo encuentras ya has pagado la parte cara —localizarlo, entender por qué ocurre, saber qué lo rodea—. Volver dentro de tres semanas obliga a reconstruir todo eso desde una línea de tracker escrita con prisa. El arreglo cuesta minutos ahora y una tarde después, y esa asimetría es la que decide si se hace o se queda para siempre en la lista.

    **Cómo se hace sin convertir un fix en un refactor sin fin**: el arreglo va en su **propio commit**, con su rojo→verde si toca comportamiento, y con su entrada en el tracker cerrada en ese mismo commit. No se mezcla con el trabajo original en el mismo diff — así el revisor puede leerlos por separado y, si hiciera falta, revertir uno sin tocar el otro. Si el arreglo resulta ser grande (toca dinero, exige decisión de producto, o abre un frente propio), entonces **sí** se registra en el tracker con el alcance medido y la dirección del fix escrita — pero eso es una decisión tomada, no el "ya lo miraré" por defecto.

    **Lo que NO cuenta como bug de refilón**: un cambio que te apetece hacer (renombrar, reordenar, "de paso lo dejo más limpio"). Eso es ruido en el diff y hay que resistirlo. La frontera es concreta: ¿produce un resultado incorrecto para alguien, o solo me molesta a mí? Solo lo primero entra.

    **Caso real (2026-07-27)**: trabajando en un bug de comunicaciones aparecieron y se cerraron tres defectos sin relación con él — una fecha resuelta con la heurística "última fila por clave" que anunciaba el final de un ciclo distinto al cancelado; dos claves duplicadas en un mismo diccionario, donde editar la primera **no surtía efecto alguno** y el síntoma aparecía a ochocientas líneas de distancia; y una pantalla financiera que ofrecía filtrar por un solo proveedor y, cuando el dato faltaba, **inventaba** el proveedor en lugar de dejar el hueco. Los tres eran invisibles desde el trabajo original y los tres se habrían perdido. El del diccionario, además, ya había costado dos vueltas de diagnóstico **en esa misma sesión** antes de que nadie lo mirara de frente.

39. **Los tests nuevos se añaden al PRINCIPIO del fichero, no al final.** Pytest ejecuta en orden de definición y en este repo el **failfast está activo por defecto**, así que un test escrito al final es un test que a menudo no llega a ejecutarse: cualquier rojo anterior —o un flaky de la pasarela— corta la pasada antes. Quien está iterando sobre su propio caso se queda sin ver su resultado, que es justo lo contrario de lo que necesita en ese momento.

    **Por qué esto y no un flag**: `-k` filtra bien pero hay que acordarse en cada invocación, y en cuanto se olvida vuelve el problema. `--ff` (*failed-first*) sería el default correcto —ejecuta primero lo que falló y sigue con el resto, combinando lo mejor de ambos— pero **hoy no funciona**: el contenedor de test se crea nuevo en cada run y monta solo `tests`, `pytest.ini` y `client`, así que el caché donde pytest anota qué falló muere con él. Habilitarlo exige montar un volumen para `/app/.pytest_cache` **y** añadir el flag en `manage.sh`; hasta entonces, colocar el test arriba es la única solución que no depende de recordar nada.

    **El coste de no hacerlo, medido (2026-07-30)**: cerrando la batería de desenlaces simulados, cada iteración obligaba a filtrar con `-k` para que las clases nuevas —añadidas al final con `cat >>`— llegaran a ejecutarse. Eso encadenó cuatro relanzamientos por sidecar huérfano, porque filtrar y relanzar deprisa es exactamente el patrón que colisiona con un run anterior todavía vivo.


## Cuándo invocar esta skill

Se activa por **frases gatillo del `description`** (el modelo decide al detectar el contexto) o invocándola **explícitamente** con `/testing-orchestration`. No hay auto-trigger por edición de archivos: las skills solo disponen de `name`+`description` para el disparo (ver cabecera).

Casos típicos:
- Vas a empezar una feature/fix nueva → workflow G (plan-guardian).
- **Vas a crear/redactar un doc de análisis que incluya el plan de implementación** ("vamos a crear un doc de análisis para abordar desde él los cambios, fixes, procedimientos y tasks") → workflow G. Por qué: ese documento ES el plan de diseño — si nace sin la estructura del plan-template (tests afectados, RBAC, i18n, gates, definition of done por PR) ni test contracts (§H) e invariantes (§G), los PRs posteriores heredan el gap y reaparece como regresión sin red. El trigger NO requiere que la sesión toque código ni ejecute tests: la skill aplica en la redacción del plan, no solo en su ejecución. (Aprendizaje 2026-07-14: se omitió cargar la skill ante "vamos a crear un doc de análisis…" por clasificarla como 'investigación pura'.)
- **Un "hotfix" / "parche rápido" / serie de hotfixes** (aunque el usuario le quite importancia) → workflow D (`baseline→red→fix→green`), invariante 22. NO saltarse el test-first por ser "rápido", y el test que confirma el rojo es **E2E**: un unitario con mocks confirma tu hipótesis del bug, no el bug. Re-activar en CADA hotfix de una cadena.
- **Un hallazgo de Lighthouse / PageSpeed / Search Console / validador externo, o un cambio en el meta-html/dynamic rendering** → invariante 25: identificar con curl+UA qué documento (meta-html vs SPA) mira el observador + inventario de consumidores del endpoint.
- **Un bug de "no se actualiza / queda stale hasta refresh"** (caché frontend) → invariante 23: localizar la mutación, invalidar la clave, auditar TODAS las vistas que muestran ese estado + red→green.
- **Vas a DISEÑAR un test de integración E2E contra un proveedor externo** (pasarela, mensajería, logística: cualquier cosa con webhooks), o a migrar uno viejo que se los inventa → invariante 36. Conviene cargar la skill **antes de escribir el test**, no cuando falle: el catálogo de trampas de ese invariante es una lista de cosas que parecen razonables mientras las escribes y solo se ven mal después.
- **Vas a AUDITAR o explorar código** (auditoría, diagnóstico de un bug, alcance de un fix o hotfix, feature nueva, refactor, revisar qué tests cubren algo) → invariante 27: se explora con el **grafo** (`codebase-memory-mcp`), no con `grep`. El grep sobre CÓDIGO es fallback de urgencia y obliga a declarar en el entregable que la cobertura es parcial. Por qué importa el orden: un inventario hecho por texto **parece completo y no lo está** — sus falsos negativos (alias de import, llamadas dinámicas, reexports, herencia) son justo los puntos que luego producen el defecto silencioso del invariante 37.
- **Vas a cambiar un invariante GLOBAL**: añadir un guard que aborta, sustituir un camino por otro, restringir una configuración a menos valores (`choices=(...)`), o cambiar la firma de algo que se llama desde varios sitios → invariante 37: inventario por grafo de llamadores **y** de los tests que verifican la regla vieja, todo en el mismo commit. Conviene cargar la skill **antes** del cambio: después, lo que queda con la regla anterior sigue en verde y no hay señal que lo delate. Gatillo adicional: si te descubres parcheando el **segundo** caso por separado, ya estás dentro de este invariante.
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
| **G** | Plan-guardian | "voy a añadir feature X" / "vamos a crear un doc de análisis con el plan de implementación" | emite `plan-template.md` (inline o embebido en el doc de análisis) | plan validado por 6-checks |
| **A** | Restart dev (site) | "down y rebuild dev" | `manage.sh down → build:dev → up:dev` | `up:dev` reporta READY + smoke `/api/health` |
| **B** | Restart test stack | "reset test" | `test:clean → build:test` | imagen test fresh |
| **C** | Run + audit canónico | `test:module/api/bg/stripe/full/unit` | preflight → run con captura → audit run dir | veredicto PASS/FAIL/SKIP |
| **D** | Test → fix → re-run | post-cambio backend, bug fix, refactor | baseline → **E2E en rojo** (visto fallar, antes del fix) → fix → re-run | scope verde, sin regresiones, máx 3 intentos (variable) |
| **E** | Detect tests afectados | edit en código fuente backend (path declarado en `CLAUDE.md`) | `git diff` + grep imports + símbolos | tabla con confianza alta/media/baja |
| **F** | Manual UI test | "verificación manual" | A → guion UI → audit reactiva | reporte clasificado |
| **H** | Validate migrations | edit `{{migrations_path}}*` | `validate_migrations.sh` | IDs únicos + chain coherente |
| **I** | Sprint status | "report del sprint" | agrega runs + bugs + markers | reporte consolidado |
| **J** | i18n coherence | edit `{{locales_path}}` | check N locales (dinámico) + **cobertura código→locale (paso 7, multilínea-safe)** + cross-check user manual + tests | gaps reportados |
| **K** | Self-check de adopción | `/testing-orchestration self-check` | 8 verificaciones (peer doc, orquestador, docker stack, paths, locales, bug tracker dual, markers pytest, env vars) | 0 errores `[FAIL]` |
| **L** | Release & versionado | "vamos a hacer release" / "tag de release" | `version:tag --release --patch\|--minor\|--major` | tag creado + push + `RELEASE_NOTES.md` promovido (Unreleased → bloque del tag) |
| **M** | Auto-aprendizaje (self-learning) | emerge un aprendizaje reutilizable durante cualquier tarea | formular 1 línea → clasificar destino (skill/proyecto/tracker) → **PREGUNTAR al usuario** con la propuesta redactada → escribir al confirmar (destino=skill: redactar SIEMPRE con `skill-creator:skill-creator` + commit submódulo + `manage.sh install:skill … --force`) — NOTA: `skill-creator` es una skill de **PLUGIN de `.claude`** (`claude-plugins-official`), NO una skill del proyecto: no aparece en `skills/` ni en `skills:list`, se invoca por su nombre `skill-creator:skill-creator`; no concluir "no está disponible" por buscarla solo entre las skills del proyecto | aprendizaje capturado en su destino o descartado |

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

**Defaults obligatorios del proyecto** (decisión del arquitecto 2026-05-27): TODO `test:*` se ejecuta con **`--no-failfast --debug`** salvo que el usuario explícitamente declare lo contrario. Razón: failfast oculta fallos múltiples y obliga a re-ejecutar; `--debug` aporta el output que la skill audita en post-run. El coste (tiempo extra y output más verboso) es aceptable frente a la falsa señal verde / información insuficiente. Aplica a `test:unit`, `test:module`, `test:api`, `test:bg`, `test:stripe`, `test:full`.

| Caso | Flags propuestos (sobre los defaults) |
|------|------------------|
| Iteración rápida tras cambio puntual en un test | `--no-build` (los defaults ya incluyen `--no-failfast --debug`) |
| Validación pre-PR de un módulo | `-c` (coverage) sobre defaults |
| Debug de regresión confusa | defaults (`--no-failfast --debug` ya cubren) |
| Suite completa pre-merge | `test:full -c` con defaults |
| Repro de un solo test | `test:module <mod> -k "<expr>" --no-build` con defaults |
| Tras cambio de deps | `--no-cache` obligatorio |
| Tras cambio de modelos | rebuild + `validate_migrations.sh` antes |
| Override del default (failfast on) | usuario debe declarar explícitamente — la skill avisa |

La skill propone los flags óptimos por caso sobre los defaults; el usuario puede overridearlos. Sin override, defaults de la matriz.

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

**Auto-trigger por `description` match** (modelo decide — sin teclear):

- Frases del usuario tipo *"voy a añadir feature"*, *"down y rebuild"*, *"lanza test:stripe"*, *"verificación manual"*, *"qué tests cubren"*, *"fix and re-run"*, *"valida migraciones"* (la lista vive en el `description` del frontmatter — único campo de disparo de una skill).
- **No existe** disparo por edición de archivos (`paths:` no es un campo válido de skill): si editas backend/migrations/locales y quieres la skill, invócala con una de esas frases o con `/testing-orchestration`.

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

## Scripts del proyecto que la skill referencia (NO los bundlea)

La skill **no copia** scripts del proyecto — los **referencia** por su ruta del repo
(`./scripts/...`) en todos sus docs. Antes traía copias (manage.sh, mt.sh, validate_migrations.sh,
stripe_heavy_collect.py) + un pre-commit hook de sincronización; se eliminaron por causar
drift constante y ensuciar el submódulo. La skill es ahora solo docs.

Scripts esperados en el proyecto destino (la skill los invoca por su ruta del repo):
- `./scripts/manage.sh` — orquestador (entry point; **obligatorio**).
- `./scripts/mt.sh` — **opcional**: middleware de manual tests (solo proyectos con billing externo).
- `./scripts/validate_migrations.sh` — validador Alembic (workflow H; parametrizable via `MIGRATIONS_DIR`).
- `./scripts/stripe_heavy_collect.py` (o equivalente) — collector pytest por marker (fases stripe heavy).

Al adoptar la skill en otro proyecto, esos scripts deben existir en su `scripts/` (o adaptar los
nombres en los docs). No hay copias en la skill ni hook de sincronización que mantener.

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

- Step-by-step de cada workflow A-L: [workflows.md](workflows.md)
- Plantilla literal copiable del plan G + variantes (refactor / hotfix / config-only): [plan-template.md](plan-template.md)
- Plantillas copiables del bug tracker (open/close/NO-BUG/reopen): [bug-tracker-template.md](bug-tracker-template.md)
- Políticas generales (rebuild, anti-colisión, xfail, RBAC, idempotencia, lifecycle bug tracker): [policies.md](policies.md)
- External providers (Stripe / PayPal / similares — heavy, flaky, sidecar, playbooks lifecycle E2E, idempotency tests): [stripe-integration.md](stripe-integration.md). **Eliminar este archivo si el proyecto no usa external billing providers**.
- Manual user-perspective tests (rebuild dev, guion UI, audit reactiva, reporte clasificado): [manual-testing.md](manual-testing.md)
- Audit post-run (run dir, archivos exigidos, formato veredicto, política DISCREPANCIA): [audit.md](audit.md)
- Comandos referencia tabla completa con flags (`manage.sh test:*`, recovery, síntomas): [commands-reference.md](commands-reference.md)
