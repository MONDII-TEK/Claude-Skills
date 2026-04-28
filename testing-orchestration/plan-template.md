# Plantilla del plan de feature/fix (workflow G)

Copia esta plantilla al iniciar cualquier feature, fix o refactor que toque código backend o frontend con impacto user-facing. La skill `testing-orchestration` audita los **6 chequeos** marcados con 🔍 antes de aprobar el plan; cada chequeo fallido genera **warning** (no bloqueo duro — el arquitecto decide override con justificación).

## Selección de variante

Antes de rellenar, elige la variante adecuada al cambio:

| Variante | Cuándo usar | Secciones aplicables |
|---|---|---|
| **A — Estándar** | Feature nueva, fix con impacto user-facing, refactor con cambio de comportamiento | §0–§12 (todas) |
| **B — Refactor puro** | Rename, extract method, dedup, sin cambio de comportamiento | §0, §1, §2, §3, §6, §11, §12 (omite §4 route/RBAC, §7 frontend, §8 refactor consumidores, §9 i18n, §10 manual UI) |
| **C — Hotfix urgente** | Bug crítico en producción que requiere fix inmediato | §0, §1 (test post-fix obligatorio incluso after-the-fact), §6 (gate test-verde), §11, §12 |
| **D — Config / migration only** | Cambio sólo de `SystemSettings`, env var, o migración Alembic sin endpoint nuevo | §0, workflow H (validate migrations) si aplica, §6 (regresión completa de la suite afectada), §11 |

La skill audita los **pasos conservados** por el arquitecto, no exige todos. Declara `N/A — variante <X>` en pasos omitidos para que el chequeo lo entienda.

---

## Plan de [feature / fix / refactor / hotfix / config]: <título corto>

**Variante seleccionada**: A / B / C / D

### 0. Contexto

- **Qué se quiere lograr** (1-2 frases, dominio): …
- **Por qué** (motivación, bug ID si aplica, ticket): …
- **Alcance**: ¿afecta backend? ¿frontend? ¿mobile? ¿docs? ¿config?
- **Precondición**: `git status` limpio + branch creada (`feature/...` o `fix/bug-…` o `hotfix/...`).

### 1. Tests afectados — predicción 🔍

(workflow E + refinamiento del arquitecto)

- **Archivos backend que cambiarán**: …
- **Tests existentes a re-correr** (predicción E con ranking imports/símbolos):

  | Test file | Confianza | Razón |
  |---|---|---|
  | `<test_path_1>` | alta | import directo |
  | `<test_path_2>` | media | usa símbolo |
  | `<test_path_3>` | baja | match por nombre |

- **Modelos tocados**: <lista> → ¿migración Alembic? ¿model checklist del peer doc del proyecto?
- **Policies / config tocadas**: <lista> → tests deben fijarlas explícitamente.
- **Subset focalizado refinado** (output que entra al paso 3):
  - El arquitecto **revisa** la predicción de la skill, descarta falsos positivos, añade 1-2 smoke tests críticos.
  - Output = **lista mínima óptima**: pequeña, focalizada, cobertura suficiente para detectar regresión localizada.

**Variante C (hotfix)**: añadir test que reproduzca el bug **after-the-fact** si no se pudo escribir antes. Es no negociable — el cierre del hotfix exige el test de regresión.

### 2. Service layer (paso 1 del playbook)

*Aplica en variantes A y B. Variante C: `N/A — fix directo en service / handler existente`. Variante D: `N/A — sin cambio de service`.*

- **Servicio nuevo / modificado**: `<ruta>::<nombre>`.
- Retorna estructura estándar del proyecto (en IronVolt: `ServiceResult` con `.success / .data / .message / .status_code`; otros proyectos: el patrón equivalente declarado en CLAUDE.md).
- **Sin SQL ni HTTP** en este paso — capa de repo para SQL, capa de routes para HTTP.
- **Test plan** (lo escribe paso 3): cobertura mínima del service (happy + ≥1 borde).

### 3. Unit test del servicio + ejecución subset focalizado (paso 2)

- **3.a. Escribir** el unit test:
  - Archivo: `<test_unit_dir>/test_<svc>.py` (path según convención del proyecto).
  - Asserts mínimos: …
- **3.b. Ejecutar SUBSET focalizado** (gate temprano — pequeño, reducido, óptimo):
  - Subset = unit test nuevo + units del servicio modificado + tests confianza alta de §1 + smokes del arquitecto.
  - Comando propuesto: `./scripts/manage.sh test:unit -k "<expresión>" --no-build` (o `test:module <mod> -k …` si hay integration en subset).
  - Smart flags: `--no-build` si freshness OK; `-d` si hay diagnóstico previo.
- **3.c. Gate temprano**:
  - Verde → procede a sección 4.
  - Rojo → workflow D toma el control (scope = subset, no full suite). Stop-condition variable.
- **3.d. Iteración**: si el subset no detecta una regresión que sí pilla sección 6, registrar aprendizaje en doc 060 §11 — la predicción de E debe expandirse.

### 4. Route + RBAC checklist 🔍

*Aplica en variante A. Variante B (refactor): `N/A — sin endpoint nuevo`. Variante C (hotfix): si toca route, aplica; si no, `N/A`. Variante D: `N/A`.*

**El proyecto define el chequeo de permisos canónico en su peer doc (`CLAUDE.md` o equivalente).** Esta sección lista las capas RBAC abstractas que típicamente requieren actualización al añadir un endpoint protegido. Adapta los nombres a la stack real de tu proyecto (paths, símbolos, tablas).

- **Endpoint**: `<METHOD> /api/<path>`
- **Decorador de auth**: el que el peer doc declare como canónico para el proyecto.
  - Regla universal: **nunca** un decorador que solo verifique JWT/sesión sin chequeo RBAC (excepción: `/auth/refresh` o equivalente).
  - Action verb (`list / read / create / update / delete / manage / upload`) debe coincidir semánticamente con la operación.
  - **Nunca** usar permiso `:read` para operaciones de escritura (anti-trampa RBAC — ver policies §15).

- **RBAC checklist (capas típicas — adaptar al proyecto)**:
  1. **Route**: decorador `permission_required(...)` (o el equivalente del proyecto).
  2. **Permission registry**: declaración del permiso en el archivo canónico del proyecto (consultar `CLAUDE.md` §RBAC / permisos para el path concreto y el nombre del registry).
  3. **Migration**: añadir permiso a roles que lo necesitan (con migración idempotente para entornos existentes).
  4. **Seed / fixtures**: actualizar `ROLE_PERMISSIONS` (o equivalente) espejando la migración.
  5. **Frontend role templates**: actualizar UI templates de roles si los hay.
  6. **SQL idempotente** para entornos sin reseed.
  7. **User manual**: si la feature es user-facing, documentar el permiso requerido y el rol que lo tiene por default.

- **Frontend gate**: el botón/UI gateado por el **mismo permiso exacto** que protege la route. Sin proxy, sin `:read` para escrituras (regla §"gate UI ≡ permiso backend").

### 5. Integration test de la ruta (paso 4)

*Aplica en variante A. Variante B/C/D: `N/A` o adaptar.*

- Archivo: `<test_api_dir>/test_<feature>_api.py`
- Cubre: shape de response, status codes, RBAC (403 sin permiso), errores de validación.
- Comando: `./scripts/manage.sh test:module <mod>`.

### 6. Build + RUN (paso 5) — gate test-verde obligatorio 🔍

- `./scripts/manage.sh build:test --no-cache` si hubo cambio de deps; `build:test` normal si no.
- Workflow C ejecuta `test:module <feature>` o `test:api`.
- **Gate test-verde**: el paso no se cierra hasta que los tests pasan.
  - Si fallan → workflow D loop (baseline → fix → re-run).
  - **Máx 3 intentos default** (variable según análisis del arquitecto). Cada intento aporta evidencia nueva o cambia hipótesis; reintentar la misma corrección 3 veces no cuenta como 3 intentos.
  - Si al 3º intento sigue rojo: **detenerse** y reportar al usuario hipótesis + evidencia + opciones.

### 7. Frontend (paso 6)

*Aplica en variante A si la feature tiene UI. Variantes B/C/D: típicamente `N/A`.*

- Hooks/pages/components nuevos o modificados.
- Tipos TS sincronizados con shape backend.
- Gate UI por permiso exacto del backend (regla §"gate UI ≡ permiso backend").

### 8. Refactor consumidores rodados-propios (paso 7)

*Aplica en variante A si hay duplicaciones consolidables. Variantes B/C/D: `N/A`.*

- Identificar implementaciones duplicadas consolidables (ej. componentes con su propio fetcher cuando hay hook compartido disponible).
- **Mismo sprint**, no PR de seguimiento.

### 9. i18n — N locales (paso 8) 🔍

*Aplica si hay strings user-facing nuevos. Variante B/C/D: `N/A — sin strings nuevos` si aplica.*

- Claves nuevas en los **N locales** del proyecto:
  - `<locales_path>/<lang_1>/<namespace>.json`
  - `<locales_path>/<lang_2>/<namespace>.json`
  - …
- Namespaces según convención del proyecto.
- Convención de naming: `{section}.{subsection}.{key}`.
- **Sin hardcoded strings**.

### 10. Plan manual UI (paso 9 — workflow F) 🔍

*Aplica si la feature es user-facing. Variantes B/C/D: `N/A` o reducido.*

- Guion no técnico para el usuario:
  - URL a abrir (`{{dev_url}}` del proyecto).
  - Credenciales (peer doc del proyecto §test creds).
  - Pasos UI numerados, cada uno acción observable: click, texto escrito, navegación, estado visible.
  - "Qué esperar ver" tras cada paso clave.
- Datos base preparados vía API admin token (no INSERT crudo).
- Audit reactiva: logs backend (`manage.sh logs backend --no-follow --since 5m`), DB (`db:query`), external providers si aplica.
- Reporte clasificado al cierre con sección "Impacto":
  - [ ] Comportamiento correcto → matriz manual
  - [ ] Test gap → propuesta automatización
  - [ ] Bug → entrada en `{{bug_tracker_active}}`
  - [ ] Feature gap / UX gap / Doc gap

### 11. Docs (paso 10)

- **User manual** (`{{user_manual_path}}` si existe): documentar comportamiento user-facing tal como se ve en UI. Source of truth.
- **Bug tracker dual**:
  - Si **abre** un bug nuevo durante el sprint → entrada en `{{bug_tracker_active}}` (activo, mínimo).
  - Si **cierra** un bug existente → mover entrada del activo a `{{bug_tracker_history}}` en el mismo commit que aplica el fix.
- **Doc de políticas del proyecto**: si durante la implementación se descubre patrón/anti-patrón nuevo de testing, consolidar ahí.

### 12. Definition of done 🔍

Marca según variante:

**Variante A — Estándar**:
- [ ] Service implementado + unit test verde.
- [ ] Route + RBAC checklist completa (capas adaptadas al proyecto).
- [ ] Integration test verde (workflow C).
- [ ] Frontend consume sin romper tipos.
- [ ] i18n N locales.
- [ ] Manual UI ejecutado y reportado.
- [ ] User manual actualizado.
- [ ] Bug tracker activo + gemelo sincronizados.
- [ ] Doc de políticas actualizado si surgió patrón nuevo.
- [ ] PR open con auditoría backend↔frontend (tabla):

  | Endpoint / campo backend | Pantalla | Opción / sección | Tab | Visible para | Verificado |
  |---|---|---|---|---|---|

**Variante B — Refactor puro**:
- [ ] Tests existentes verdes (sin regresión).
- [ ] Suite afectada verde (workflow C).
- [ ] Doc de políticas actualizado si surgió aprendizaje nuevo.

**Variante C — Hotfix urgente**:
- [ ] Test que reproduce el bug (after-the-fact si no se escribió antes).
- [ ] Test pasa tras fix.
- [ ] Suite afectada verde.
- [ ] Bug tracker: entrada movida al gemelo con causa raíz + post-mortem.
- [ ] User manual actualizado si la causa expone limitación user-facing.
- [ ] Follow-up registrado si la robustez requiere refactor mayor (no entra en hotfix).

**Variante D — Config / migration only**:
- [ ] `validate_migrations.sh` verde (si toca migrations).
- [ ] Suite afectada verde tras aplicar migration / cambio de config.
- [ ] User manual actualizado si la config es visible/configurable por el usuario.

---

## Notas para la skill (auditoría del plan)

Los 6 chequeos 🔍 que la skill ejecuta antes de aprobar el plan:

1. **§1 Tests afectados**: si dice "ninguno", la skill lanza workflow E para validar. Si E encuentra tests, plan incompleto → warning.
2. **§4 Route + RBAC**: si la variante incluye §4 y no declara chequeo de permisos del proyecto → RED FLAG. Si variante omite §4 (B/C/D) → verifica que la justificación esté presente.
3. **§6 Build + RUN**: si no declara gate test-verde + max 3 intentos (variable) → RED FLAG.
4. **§9 i18n**: si la variante incluye §9 y solo lista 1-2 locales → RED FLAG. Cross-check con `{{locales_path}}`. Si variante omite §9 con justificación "sin strings nuevos" → verifica con grep.
5. **§10 Plan manual UI**: si la feature es user-facing y la variante incluye §10 sin guion → RED FLAG. Refactor puro (B) → N/A aceptado.
6. **§12 Definition of done**: si no tiene checkboxes según la variante seleccionada → RED FLAG.

**Anti-patrones bloqueados** (warning + sugerencia de corrección):
- Empezar por frontend antes del service.
- "Test al final" — no hay paso "tests" final, son gates entre pasos.
- "i18n en otro PR" — refactor consumidores e i18n viven en el mismo sprint que el service.
- "Manual test cuando esté listo" — el plan manual se diseña al inicio, se ejecuta al final.
- Saltar §1 (tests afectados) → invariablemente reaparece como bug por regresión.
- 4º intento de fix sin reportar al usuario.
- Variante C (hotfix) sin test post-fix → contraviene la regla cardinal: el test de regresión es no negociable, aunque se escriba después del fix.
