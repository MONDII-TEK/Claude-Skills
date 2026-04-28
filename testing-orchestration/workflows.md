# Workflows extremo-a-extremo

Detalle paso a paso de los 10 workflows orquestados por la skill. Cada uno con: disparo canónico, secuencia de comandos, criterio de "hecho", anti-patrones bloqueados.

## Workflow G — Plan-guardian (diseño previo de feature/fix)

**Propósito**: la skill no es solo runner; es co-piloto del arquitecto durante el diseño de cualquier cambio funcional. Asegura que **el plan** incluya tests antes que código, gates antes que fixes, i18n antes que UI, docs antes que merge.

**Disparo canónico**:
- Frase: *"voy a añadir feature X"*, *"voy a refactorizar Y"*, *"vamos a arreglar el bug Z"*, *"diseñemos plan para …"*.
- Auto-trigger por `paths:` del frontmatter (declarados según el layout del proyecto en `CLAUDE.md`) cuando aún no hay plan G activo en la sesión.
- Slash: `/testing-orchestration design <título>`.

**Quién es el arquitecto**: el usuario humano, o el agente `fullstack-architect-reviewer` si el usuario lo invoca para reforzar el plan. La skill **colabora**: emite plantilla + checklists; el arquitecto rellena el contenido de dominio; la skill audita el plan resultante.

**Secuencia**:

```
0. Emit plantilla (shell injection):
   !`cat ${CLAUDE_SKILL_DIR}/plan-template.md`

1. Arquitecto rellena el plan:
   - Si humano: edita en chat / fichero markdown / body de PR.
   - Si fullstack-architect-reviewer: agente devuelve plan en formato libre o usando la plantilla.

2. La skill audita los 6 chequeos:
   ✅/⚠️ §1 Tests afectados
   ✅/⚠️ §4 RBAC permission_required
   ✅/⚠️ §6 Gate test-verde + max 3 intentos
   ✅/⚠️ §9 i18n 4 locales
   ✅/⚠️ §10 Plan manual UI (si user-facing)
   ✅/⚠️ §12 Definition of done con checkboxes

3. Reporte:
   - Todos verdes → "plan aprobado, procede a sección 2 (Service)".
   - Algún warning → "RED FLAG: <qué falta>. Override con justificación o corrige el plan."
```

**Criterio de "hecho"**: 6 checks verdes (o overrides justificados) + arquitecto da OK explícito para empezar implementación.

**Anti-patrones bloqueados** (warning + sugerencia):
- Empezar por frontend antes del service.
- Saltar §1 (tests afectados) → siempre reaparece como bug por regresión.
- "Test al final" — no hay paso "tests" final, son gates entre pasos.
- "i18n en otro PR" — refactor consumidores e i18n viven en el mismo sprint.
- "Manual test cuando esté listo" — el plan manual se diseña al inicio.
- 4º intento de fix sin reportar al usuario.

**Smart abreviado**: si el cambio es **solo refactor sin cambio de comportamiento** (rename de variable, extract method puro), G ofrece **plan abreviado** sin §4 (route), §7-§10 (frontend/refactor/i18n/manual). Mantiene siempre §1 (tests afectados), §6 (gate test-verde), §11 (docs si aprendizaje nuevo), §12 (definition of done).

**Colaboración con `fullstack-architect-reviewer`**: la skill **consume** el output del agente como input del paso 1. Best practice: agentes son aislados (su contexto no ve la conversación), skills son persistentes en el contexto principal. El return del agente llega como mensaje de texto a la conversación → la skill (ya cargada) lo audita en el siguiente turno contra los 6 checks. La skill **no obliga** la plantilla literal — acepta cualquier plan que cumpla los 6 chequeos.

---

## Workflow A — Restart dev (site)

**Disparo**:
- Frase: *"down y rebuild dev"*, *"reset stack dev"*, *"restart del site"*.
- Variante completa: *"restart completo"*, *"down y rebuild de todo"*.
- Slash: `/testing-orchestration restart-dev`.

**Secuencia óptima** (compose inteligente):

```bash
./scripts/manage.sh down            # baja stack actual
./scripts/manage.sh build:dev       # rebuild imagen dev
./scripts/manage.sh up:dev          # arranca stack dev ({{dev_url}})
```

**Variante "restart completo"** (memoria `feedback_restart_cycle`): incluye prod + test images preconstruidas para que la siguiente acción (test:*, up en NAS, etc.) no necesite rebuild adicional:

```bash
./scripts/manage.sh down
./scripts/manage.sh build           # prod images
./scripts/manage.sh build:dev       # dev images
./scripts/manage.sh build:test      # test images
./scripts/manage.sh up:dev          # NUNCA `up` en máquina dev (red proxy NAS)
```

**Criterio de "hecho"**: `up:dev` retorna sin error + `docker ps` muestra contenedores en `(healthy)` + **smoke test post-deploy verde**. La skill reporta `{{dev_url}}` (declarada en `CLAUDE.md`).

**Smoke test post-deploy** (extensión obligatoria del workflow A):

```bash
# Espera a que el backend responda 200 OK en el endpoint de health
ATTEMPTS=30
while [ $ATTEMPTS -gt 0 ]; do
  if curl -sf "{{dev_url}}/api/health" >/dev/null 2>&1; then
    echo "[OK] Backend healthy"
    break
  fi
  ATTEMPTS=$((ATTEMPTS - 1))
  sleep 2
done
[ $ATTEMPTS -eq 0 ] && echo "[FAIL] Backend no responde tras 60s — investigar logs"
```

Si el smoke test falla, NO declarar el restart como exitoso. Levantar logs (`./scripts/manage.sh logs backend --no-follow --tail 100`) y reportar al usuario.

**Cuándo NO**: si `git status` está limpio y no se ha tocado código del sprint actual desde el último build, saltar el ciclo (excepción §"0 Ciclo estándar" doc 053).

**Smart compose** (reglas de optimización):
- Solo `tests/`-only changes → `--no-build` para test:*; ningún rebuild de dev.
- Cambios en `$BACKEND_PATH/` (no-tests) → `build:dev` + `build:test` requeridos antes de validar; `build` (prod) opcional salvo `up`.
- Cambios en `{{frontend_path}}/` → `build:dev`; `build:test` no requerido (frontend no entra en imagen test).
- Cambios en deps (`requirements.txt` / `package.json` o equivalentes) → `--no-cache` obligatorio en cualquier build afectado.

---

## Workflow B — Restart test stack

**Disparo**:
- Frase: *"reset test"*, *"limpia el stack de test"*, *"rebuild test image desde cero"*.
- Auto-trigger ante `relation "users" does not exist` o schema corruption detectado en logs.
- Slash: `/testing-orchestration restart-test`.

**Secuencia**:

```bash
./scripts/manage.sh test:status                # confirmar inventario actual
./scripts/manage.sh test:clean                 # baja db-test + sidecar + ephemeral
./scripts/manage.sh build:test                 # rebuild imagen test (con cache)
# Si hubo cambio de deps:
./scripts/manage.sh build:test --no-cache      # rebuild limpio
```

**Criterio de "hecho"**: `test:status` reporta solo `db-test` (si `--keep-db`) o vacío. Imagen test reconstruida sin error.

**Smart**: `test:clean --keep-db` cuando solo se quiere bajar backend o sidecar y se sabe que el schema actual es válido (ahorra ~30s del recreate de db-test).

**Sync check de scripts** (estrategia A copia, defensa secundaria — la primaria es el pre-commit hook):

```bash
for s in manage.sh mt.sh stripe_heavy_collect.py validate_migrations.sh; do
  [ -f "scripts/$s" ] || continue  # opcional: el proyecto puede no tener todos
  diff -q "scripts/$s" "skills/testing-orchestration/scripts/$s" > /dev/null 2>&1 || \
    echo "[WARN] scripts/$s diverge de skill copy — actualizar la copia o instalar pre-commit hook"
done
```

Si difieren → emite warning. **No bloquea** el restart de test (la skill puede funcionar contra el `scripts/` original mientras se sincroniza la copia), pero registra el drift en el reporte.

**Drift prevention robusto (recomendado)**: instalar pre-commit hook que falle si `scripts/<X>` cambió y `skills/testing-orchestration/scripts/<X>` no se actualizó en el mismo commit. Ver instalación en SKILL.md §"Recursos adjuntos".

---

## Workflow C — Run + audit (canónico de cualquier `test:*`)

**Disparo**:
- Frase: *"lanza test:X"*, *"corre la suite"*, cualquier mención de `test:module/api/bg/stripe/full/unit`.
- Slash: `/testing-orchestration run <test:cmd>`.

**Secuencia**:

```bash
# 1. Pre-flight (auto en test:stripe; manual en otros)
./scripts/manage.sh test:status
docker ps --format '{{.Names}}' | grep -E '_test-(backend-run|stripe-cli)' && \
  ./scripts/manage.sh test:clean --keep-db

# 2. Image freshness check (LA SKILL ES LA AUTORIDAD) — algoritmo robusto
# Variables de proyecto (consultar `CLAUDE.md` para los valores reales del layout;
# override via env si difieren de los placeholders BACKEND_PATH y TESTS_SUBPATH):
BACKEND_PATH="${BACKEND_PATH:-backend}"  # placeholder genérico — sustituir/override según CLAUDE.md
TESTS_SUBPATH="${TESTS_SUBPATH:-tests}"   # idem
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
  ./scripts/manage.sh build:test    # imagen no existe
elif [ -z "$IMG_HASH" ]; then
  # Fallback: timestamp UTC explícito (compatible con builds antiguas sin label)
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
# Notas: algoritmo robusto a zonas horarias (epoch UTC), mtimes preservados de
# git checkout (usa hash si la build añadió --label src_hash), archivos
# generados (excluye __pycache__/*.pyc/*.egg-info), parametrizado por
# BACKEND_PATH y TESTS_SUBPATH env vars — exportar valores reales según
# CLAUDE.md del proyecto.

# 3. Run con captura
./scripts/manage.sh test:<tipo> [<submodulo>] [<flags>] >/tmp/test_debug.log 2>&1

# 4. Audit del run dir unificado
RUN_DIR=$(ls -td logs/test_runs/*/ | head -1)
cat "${RUN_DIR}summary.log"
grep -nE "PASSED|FAILED|ERROR|CRITICAL|InternalError" "${RUN_DIR}backend.log" | head -30
[ -f "${RUN_DIR}backend_heavy.log" ] && grep -nE "FAILED|ERROR" "${RUN_DIR}backend_heavy.log" | head -20
[ -f "${RUN_DIR}stripe_cli.log" ] && grep -nE "\[ERROR\]|5[0-9]{2}|refused|timeout" "${RUN_DIR}stripe_cli.log" | head -20
```

**Criterio de "hecho"**: la skill emite veredicto con:
- Resumen pytest (PASS/FAIL/SKIP por fase).
- Path del run dir.
- Lista de errores significativos con `file:line` de log.
- Bloque cobertura: `[OK]` / `[N/A]` / `[DISCREPANCIA]` por archivo según fixture levantado.

**Smart auto-recovery**: si phase 4-5 falló por colisión detectada en preflight, la skill se auto-recovery con `down → test:clean → re-launch` **un único re-intento**, no en bucle.

---

## Workflow D — Test → fix → re-run (regression loop)

**Disparo**:
- Cualquier mutación a `$BACKEND_PATH/services/*`, `$BACKEND_PATH/routes/*`, `$BACKEND_PATH/repositories/*`, `$BACKEND_PATH/models.py` (default `BACKEND_PATH=backend`).
- Bug fix referenciado.
- Refactor anunciado por el usuario.
- Invocado desde G (paso 6) o standalone.

**Secuencia obligatoria** (memoria `feedback_baseline_test_fix_verify`):

```
0. BASELINE — antes de cualquier fix: correr la suite afectada (workflow C)
   y confirmar VERDE. Si arranca roja, primero estabilizar.

1. ADD FAILING TEST — para el bug/feature: añadir un test que falle
   capturando el comportamiento incorrecto/faltante. Ejecutar y
   confirmar que efectivamente falla con mensaje esperado.

2. FIX — aplicar cambio mínimo de producción que hace pasar el test
   nuevo. Sin tocar otros tests.

3. RE-RUN TARGET — el test nuevo + tests previamente existentes del
   módulo. Confirmar test nuevo PASSED.

4. RE-RUN SUITE AFECTADA — workflow E define el alcance (tests del
   módulo + tests que importan los módulos cambiados + smokes).
   Confirmar 0 regresiones.

5. AUDIT — workflow C audit completo (run dir, sidecar si stripe).

6. STOP-CONDITION — máx 3 intentos por defecto (variable).
   Si al 3º sigue rojo, la skill detiene el ciclo y reporta:
     (a) hipótesis de causa raíz acumuladas,
     (b) evidencia de cada intento (resumen),
     (c) opciones de fix alternativas o bloqueos identificados.
```

**Criterio de "hecho"**: scope verde **Y** suite afectada verde **Y** xfail/xpass markers sincronizados (regla §10 doc 053) **Y** bug tracker actualizado si aplica (PR #/commit hash).

**Stop-condition variable**: 3 es el default; el arquitecto puede subir/bajar con razón documentada en el reporte. Ej. *"intento 2 reveló cambio de invariante; subo a 5 con justificación X"*.

**Anti-patrones bloqueados explícitamente**:
- Tocar el assert del test para que pase.
- Saltar BASELINE ("seguro está verde").
- Fix sin test nuevo (no captura la regresión futura).
- Cuarto intento sin reportar al usuario.

**Autonomía**: workflow D ejecuta el loop sin pedir confirmación intermedia (per decisión #6). Reporta avance al usuario al cerrar cada intento.

---

## Workflow E — Detect tests afectados por un cambio

**Disparo**:
- Auto-trigger al cargarse la skill por `paths:` del frontmatter (layout del proyecto declarado en `CLAUDE.md`) con ficheros modificados.
- Frase: *"qué tests cubren este cambio"*, *"qué tests están afectados"*.
- Slash: `/testing-orchestration affected`.
- Paso 1 de G.

**Algoritmo** (parametrizado por `BACKEND_PATH`, default `backend`):

```
BACKEND_PATH="${BACKEND_PATH:-backend}"
TESTS_DIR="${TESTS_DIR:-$BACKEND_PATH/tests}"

1. Listar archivos modificados:
   git diff --name-only origin/main...HEAD
   git diff --name-only HEAD

2. Para cada archivo en $BACKEND_PATH/{services,routes,repositories,models.py}:
   - Extraer nombre de clase/función pública (Grep de export simbólico).
   - Buscar tests que importen el módulo (CONFIANZA ALTA):
       grep -lE "from ($BACKEND_PATH\.)?services\.<modulo>|import.*<modulo>" "$TESTS_DIR"
   - Buscar tests por nombre simbólico (CONFIANZA MEDIA):
       grep -lE "<ClaseONombrePublico>" "$TESTS_DIR"
   - Buscar tests por keyword del dominio (CONFIANZA BAJA):
       grep -lE "<dominio>" "$TESTS_DIR"

3. Mapear archivos cambiados → tests recomendados con ranking:

   | Archivo cambiado | Test directo (alta) | Indirecto (media) | Por keyword (baja) |

4. Si cambios en $BACKEND_PATH/models.py (o equivalente):
   ALERTA: probable migración Alembic → workflow H (validate migrations).
   ALERTA: model checklist del peer doc del proyecto.

5. Si cambios en config / feature flags / policies del proyecto:
   ALERTA: tests deben configurar la policy explícitamente
   (regla §7 policies.md).
```

**Criterio de "hecho"**: tabla de cobertura entregada al usuario; el usuario decide alcance de run (workflow C). La skill **no** lanza tests sola sin confirmación cuando es loop D iniciado por feature change.

**Smart**: si cambios solo en `$BACKEND_PATH/tests/` → workflow C directo; no se necesita cobertura cruzada.

---

## Workflow F — Manual UI test (user-perspective)

**Disparo**:
- Frase: *"verificación manual"*, *"prueba desde la UI"*, *"test manual"*, *"flujo desde la perspectiva del usuario"*.
- Slash: `/testing-orchestration manual <feature>`.
- Paso 10 de G.

**Secuencia** (regla §"0" doc 053):

```
1. WORKFLOW A (rebuild dev) — siempre antes del guion, en background.

2. SELECT TEST — el arquitecto (skill) elige qué validar:
   - post-fix recientes,
   - zonas de baja cobertura automatizada,
   - cambios user-facing,
   - regresión por intuición del usuario.

3. PREP DATA — vía API admin token (preferido). Variables resueltas desde CLAUDE.md:
   BASE="${DEV_URL:?CLAUDE.md §dev URL}"
   TEST_ADMIN_EMAIL="${TEST_ADMIN_EMAIL:?CLAUDE.md §test creds}"
   TEST_ADMIN_PASS="${TEST_ADMIN_PASS:?CLAUDE.md §test creds}"
   ADMIN_TOKEN=$(curl -s "$BASE/api/auth/login" \
     -H 'Content-Type: application/json' \
     -d "{\"email\":\"$TEST_ADMIN_EMAIL\",\"password\":\"$TEST_ADMIN_PASS\"}" \
     | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
   curl -s -X POST "$BASE/api/<endpoint>" \
     -H "Authorization: Bearer $ADMIN_TOKEN" -d '...'
   Nunca INSERT crudo (ver policies.md §13).

4. ENTREGA GUION al usuario:
   - URL ($BASE — declarada en CLAUDE.md),
   - credenciales (CLAUDE.md §test creds),
   - pasos UI numerados, lenguaje no técnico,
   - "qué esperar ver" tras cada paso clave.

5. AUDIT EN PARALELO mientras el usuario clica:
   ./scripts/manage.sh logs backend --no-follow --since 5m --tail 200
   ./scripts/manage.sh db:query "SELECT ... FROM ..."
   # Stripe API si aplica (db:py):
   ./scripts/manage.sh db:py "import stripe; print(stripe.Subscription.retrieve('sub_...'))"

6. REPORTE CLASIFICADO con sección "Impacto":
   - [ ] Comportamiento correcto → matriz manual
   - [ ] Test gap → propuesta automatización
   - [ ] Bug → entrada en 051_bug_tracker.md (activo)
   - [ ] Feature gap / UX gap / Doc gap

7. NO cerrar sin clasificar (regla anti-trampa).
```

**Criterio de "hecho"**: reporte con veredicto + clasificación impacto + próximo paso recomendado.

**Cuándo `mt.sh`**: flujos que dependen de Stripe real (subscription, payment method). `mt.sh` resuelve `BASE_URL`, `ADMIN_TOKEN`, `CUSTOMER_ID`, `PM_ID`, `STRIPE_PRICE` automáticamente.

**Cuándo NO `mt.sh`**: setup de datos puros sin Stripe (productos ecommerce, cursos). Usar admin token + curl directamente.

---

## Workflow H — Validate migrations

**Disparo**:
- Auto-trigger al editar `{{migrations_path}}` — path Alembic del proyecto, declarado en `CLAUDE.md`. Override via `MIGRATIONS_DIR` env var si el layout difiere del placeholder.
- Frase: *"valida migraciones"*, *"comprueba migration IDs"*, *"check Alembic"*.
- Slash: `/testing-orchestration validate-migrations`.

**Secuencia**:

```bash
./scripts/validate_migrations.sh
```

**Comprobaciones** (regla §6 CLAUDE.md):
- IDs únicos (no duplicados entre archivos).
- IDs no genéricos (`a1b2c3d4e5f6` blacklisteado).
- `down_revision` chain coherente sin gaps.

**Si detecta problema**:
1. Reportar archivo conflictivo.
2. Proponer fix: regenerar ID con `python -c "import uuid; print(uuid.uuid4().hex[:12])"`.
3. Si IDs duplicados → cuál migración mantiene el ID y cuál se renombra (cronología).

**Criterio de "hecho"**: script retorna 0 + workflow C `test:module` o `test:api` confirma que `flask db upgrade` aplica sin error en imagen test.

---

## Workflow I — Sprint status report

**Disparo**:
- Frase: *"report del sprint"*, *"estado del testing"*, *"resumen de runs"*.
- Slash: `/testing-orchestration status`.

**Secuencia**:

```bash
# 1. Últimos 5 runs
ls -td logs/test_runs/*/ | head -5 | while read dir; do
  echo "=== $dir ==="
  cat "${dir}summary.log" | head -20
done

# 2. Bugs abiertos (activo)
grep -cE "^### BUG-" docs/analysis/051_bug_tracker.md
grep -E "^### BUG-" docs/analysis/051_bug_tracker.md

# 3. Bugs cerrados último mes (gemelo)
grep -cE "^### BUG-" docs/analysis/051_bug_tracker_history.md
# Filtrar por fecha del último mes si el formato lo permite

# 4. Markers flaky / xfail
TESTS_DIR="${TESTS_DIR:-${BACKEND_PATH:-backend}/tests}"
grep -rnE "@pytest.mark.(xfail|stripe_flaky|bg_flaky|stripe_heavy)" "$TESTS_DIR" | wc -l
grep -rnE "@pytest.mark.(xfail|stripe_flaky|bg_flaky)" "$TESTS_DIR"

# 5. Sync check scripts repo ↔ skill
for s in manage.sh mt.sh stripe_heavy_collect.py validate_migrations.sh; do
  diff -q "scripts/$s" "skills/testing-orchestration/scripts/$s" || \
    echo "WARN: scripts/$s diverge de skill copy"
done

# 6. git status del scope
git status --short "${BACKEND_PATH:-backend}/" scripts/ skills/testing-orchestration/
```

**Reporte estructurado**:

```
## Sprint status — <fecha>

### Últimos 5 runs
<tabla con timestamp, label, verdict, errores principales>

### Bugs activos (mínimo)
- BUG-XXX: <título> — open / fixing
- ...

### Bugs cerrados último mes
<n> bugs en 051_bug_tracker_history.md

### Markers vivos
- xfail: N
- stripe_flaky: N
- bg_flaky: N
- stripe_heavy: N

### Divergencia scripts repo ↔ skill
[OK] / [DIVERGE: <archivo>]

### Cambios pendientes
<git status output>
```

**Criterio de "hecho"**: reporte entregado al usuario en un único mensaje.

---

## Workflow J — i18n coherence

**Disparo**:
- Auto-trigger al editar `{{locales_path}}` — path al directorio i18n declarado en `CLAUDE.md` del proyecto, override via `LOCALES_DIR` env var.
- Frase: *"actualiza i18n"*, *"añade traducción"*, *"i18n missing locale"*.

**Secuencia (locales y namespaces dinámicos — agnóstico al proyecto)**:

```bash
LOCALES_DIR="${LOCALES_DIR:-client/public/locales}"
USER_MANUAL_PATH="${USER_MANUAL_PATH:-}"  # path al user manual del proyecto si existe; declarado en CLAUDE.md (vacío = skip cross-check)

# 1. Detectar archivos editados
LOCALES_CHANGED=$(git diff --name-only "$LOCALES_DIR" 2>/dev/null)
[ -z "$LOCALES_CHANGED" ] && echo "Sin cambios en locales; skip" && exit 0

# 2. Detectar la lista REAL de locales del proyecto (en lugar de hardcoded es/en/fr/it)
LOCALES=()
for dir in "$LOCALES_DIR"/*/; do
  [ -d "$dir" ] && LOCALES+=("$(basename "$dir")")
done
[ ${#LOCALES[@]} -lt 2 ] && echo "Solo 1 locale; coherencia trivial" && exit 0
echo "Locales detectados: ${LOCALES[*]}"

# 3. Detectar namespaces (archivos .json en cada locale)
REFERENCE_LOCALE="${LOCALES[0]}"
NAMESPACES=()
for f in "$LOCALES_DIR/$REFERENCE_LOCALE"/*.json; do
  [ -f "$f" ] && NAMESPACES+=("$(basename "$f" .json)")
done

# 4. Para cada namespace tocado, comparar claves entre TODOS los locales detectados
for ns in "${NAMESPACES[@]}"; do
  ref_file="$LOCALES_DIR/$REFERENCE_LOCALE/$ns.json"
  [ ! -f "$ref_file" ] && continue
  KEYS_REF=$(python3 -c "import json; d=json.load(open('$ref_file')); print('\n'.join(sorted(d.keys())))")
  for lang in "${LOCALES[@]:1}"; do
    target_file="$LOCALES_DIR/$lang/$ns.json"
    [ ! -f "$target_file" ] && echo "MISSING: $target_file" && continue
    KEYS_LANG=$(python3 -c "import json; d=json.load(open('$target_file')); print('\n'.join(sorted(d.keys())))")
    DIFF=$(diff <(echo "$KEYS_REF") <(echo "$KEYS_LANG"))
    [ -n "$DIFF" ] && echo "WARN: $ns $REFERENCE_LOCALE ↔ $lang divergent:" && echo "$DIFF"
  done
done

# 5. Cross-check user manual (opcional — solo si existe)
if [ -f "$USER_MANUAL_PATH" ]; then
  NEW_KEYS=$(git diff "$LOCALES_DIR/$REFERENCE_LOCALE/" 2>/dev/null | \
    grep '^+.*":' | grep -oE '"[^"]+"' | head -20)
  for key in $NEW_KEYS; do
    grep -q "$key" "$USER_MANUAL_PATH" || \
      echo "INFO: clave $key añadida en i18n; ¿documentar en user manual?"
  done
fi

# 6. Cross-check tests (parametrizado)
TESTS_DIR="${TESTS_DIR:-${BACKEND_PATH:-backend}/tests}"
for key in $NEW_KEYS; do
  grep -rln "$key" "$TESTS_DIR" 2>/dev/null | head -3
done
```

**Criterio de "hecho"**: reporte con:
- Gaps de cobertura entre los N locales detectados dinámicamente (claves añadidas a 1 idioma pero faltantes en otros).
- Sugerencia de actualizar user manual si la string es user-facing relevante (omitido si no hay user manual).
- Tests que asseran la string (verificar que se actualicen si la traducción cambia).

**Coste**: muy bajo (solo lectura + diff JSON).

**Portabilidad**: el script no asume número de idiomas ni namespaces. Lee del filesystem la realidad del proyecto. Si el proyecto no tiene i18n, el workflow se omite por completo (no hay path en `paths:` que lo dispare).

---

## Workflow K — Self-check de adopción

**Disparo**:
- Slash: `/testing-orchestration self-check`.
- Frase: *"verifica que la skill funciona en este proyecto"*, *"adopción skill"*.
- Recomendado al adoptar la skill en un proyecto nuevo (post-clone), o tras cambios en `paths:` del frontmatter.

**Secuencia**:

```bash
echo "=== Self-check testing-orchestration ==="
ERRORS=0

# 1. Peer doc presente
if [ ! -f "CLAUDE.md" ] && [ ! -f ".claude/CLAUDE.md" ]; then
  echo "[FAIL] CLAUDE.md no encontrado — skill no es usable sin peer doc"
  ERRORS=$((ERRORS + 1))
else
  echo "[OK] Peer doc presente"
fi

# 2. Orquestador ejecutable
if [ ! -x "scripts/manage.sh" ]; then
  echo "[FAIL] scripts/manage.sh no ejecutable o ausente"
  ERRORS=$((ERRORS + 1))
else
  echo "[OK] Orquestador presente y ejecutable"
fi

# 3. Stack Docker (pieza fundamental — daemon, compose v2, compose files, servicios)
echo "--- Stack Docker ---"

# D1. Daemon vivo
if ! docker info >/dev/null 2>&1; then
  echo "[FAIL] Docker daemon no responde — arrancar dockerd o verificar permisos del socket (grupo 'docker')"
  ERRORS=$((ERRORS + 1))
else
  echo "[OK] Docker daemon vivo"
fi

# D2. compose v2 (manage.sh asume CLI plugin v2, no docker-compose legacy)
if ! docker compose version >/dev/null 2>&1; then
  echo "[FAIL] 'docker compose' v2 no disponible — manage.sh asume CLI plugin v2"
  ERRORS=$((ERRORS + 1))
else
  echo "[OK] docker compose v2 disponible"
fi

# D3. Compose files referenciados por manage.sh existen físicamente
COMPOSE_FILES=$(grep -hoE 'docker-compose[^[:space:]"'"'"']*\.ya?ml' scripts/manage.sh 2>/dev/null | sort -u)
if [ -z "$COMPOSE_FILES" ]; then
  echo "[INFO] Sin referencias a compose files en manage.sh — proyecto sin Docker o usa otro mecanismo"
else
  for f in $COMPOSE_FILES; do
    if [ -f "$f" ]; then
      echo "[OK] Compose file presente: $f"
    else
      echo "[FAIL] Compose file referenciado en manage.sh pero ausente en disco: $f"
      ERRORS=$((ERRORS + 1))
    fi
  done
fi

# D4. Servicios mínimos declarados (override via EXPECTED_SERVICES env)
EXPECTED_SERVICES="${EXPECTED_SERVICES:-backend db-test}"
for svc in $EXPECTED_SERVICES; do
  found=0
  for f in $COMPOSE_FILES; do
    [ -f "$f" ] || continue
    if grep -qE "^[[:space:]]+${svc}:" "$f"; then found=1; break; fi
  done
  if [ $found -eq 1 ]; then
    echo "[OK] Servicio compose '$svc' declarado"
  else
    echo "[FAIL] Servicio compose '$svc' no encontrado — adaptar EXPECTED_SERVICES si el proyecto usa otros nombres"
    ERRORS=$((ERRORS + 1))
  fi
done

# D5. Imagen test construida (warn si no — primer test:* la crea via build:test)
TEST_IMG=$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -E 'test-backend' | head -1)
if [ -z "$TEST_IMG" ]; then
  echo "[WARN] Imagen test no construida — primer 'test:*' la creará via build:test"
else
  echo "[OK] Imagen test presente: $TEST_IMG"
  # D6. Label src_hash para freshness check robusto
  IMG_HASH=$(docker image inspect "$TEST_IMG" --format '{{ index .Config.Labels "src_hash" }}' 2>/dev/null)
  if [ -z "$IMG_HASH" ] || [ "$IMG_HASH" = "<no value>" ]; then
    echo "[WARN] Imagen test sin label 'src_hash' — freshness check usará fallback mtime (más falsos positivos)"
  else
    echo "[OK] Imagen test con label src_hash=$IMG_HASH"
  fi
fi

# D7. Red externa proxy (info — relevante solo si 'up' prod la requiere)
if grep -qE "external.*name.*proxy|networks:.*proxy" scripts/manage.sh docker-compose*.yml 2>/dev/null; then
  if docker network ls --format '{{.Name}}' 2>/dev/null | grep -qE '^proxy$'; then
    echo "[OK] Red externa 'proxy' presente"
  else
    echo "[INFO] Red externa 'proxy' no existe — 'up' prod fallará en esta máquina; usar 'up:dev'"
  fi
fi

# 4. Subcomandos esperados del orquestador
for cmd in test:status test:clean test:unit test:module build:test; do
  if ! ./scripts/manage.sh 2>&1 | grep -q "$cmd"; then
    echo "[WARN] Subcomando '$cmd' no documentado en manage.sh — adaptar workflows si difiere"
  fi
done

# 5. Paths del frontmatter resuelven (parametrizado por BACKEND_PATH)
BACKEND_PATH="${BACKEND_PATH:-backend}"
for p in "$BACKEND_PATH/services" "$BACKEND_PATH/routes" pytest.ini; do
  if [ ! -e "$p" ]; then
    echo "[WARN] Path '$p' no existe en este proyecto — adaptar 'paths:' del frontmatter o exportar BACKEND_PATH"
  fi
done

# 6. Locales dinámicos
LOCALES_DIR="${LOCALES_DIR:-client/public/locales}"
if [ -d "$LOCALES_DIR" ]; then
  N_LOCALES=$(ls -d "$LOCALES_DIR"/*/ 2>/dev/null | wc -l)
  echo "[INFO] Locales detectados: $N_LOCALES en $LOCALES_DIR"
else
  echo "[INFO] Sin i18n — workflow J no aplicable"
fi

# 7. Bug tracker dual
ACTIVE="${BUG_TRACKER_ACTIVE:-docs/analysis/051_bug_tracker.md}"
HISTORY="${BUG_TRACKER_HISTORY:-docs/analysis/051_bug_tracker_history.md}"
[ -f "$ACTIVE" ] && echo "[OK] Bug tracker activo: $ACTIVE" || echo "[WARN] $ACTIVE ausente — crearlo con plantilla"
[ -f "$HISTORY" ] && echo "[OK] Bug tracker history: $HISTORY" || echo "[WARN] $HISTORY ausente — crearlo con plantilla"

# 8. Markers pytest
PYTEST_INI="${PYTEST_INI:-pytest.ini}"
[ -f "$PYTEST_INI" ] || PYTEST_INI="$BACKEND_PATH/pytest.ini"
if [ -f "$PYTEST_INI" ]; then
  for m in stripe_integration stripe_heavy stripe_flaky bg_flaky; do
    grep -q "$m" "$PYTEST_INI" || echo "[INFO] Marker '$m' no registrado en $PYTEST_INI — workflows Stripe/flaky requieren registro"
  done
else
  echo "[WARN] pytest.ini no encontrado en raíz ni en \$BACKEND_PATH ($BACKEND_PATH) — verificar configuración (CLAUDE.md §pytest)"
fi

# 9. Sync skill scripts ↔ repo scripts
for s in manage.sh mt.sh stripe_heavy_collect.py validate_migrations.sh; do
  [ ! -f "scripts/$s" ] && continue
  if [ ! -f "skills/testing-orchestration/scripts/$s" ]; then
    echo "[WARN] skills/.../scripts/$s ausente; copia desde scripts/$s"
  elif ! diff -q "scripts/$s" "skills/testing-orchestration/scripts/$s" >/dev/null 2>&1; then
    echo "[WARN] scripts/$s diverge de skill copy — sincronizar"
  fi
done

echo "=== Self-check completado: $ERRORS error(es) críticos ==="
[ $ERRORS -eq 0 ] && echo "Skill lista para usar" || echo "Skill NO usable hasta resolver errores [FAIL]"
```

**Criterio de "hecho"**: 0 errores `[FAIL]`. Los `[WARN]` son informativos — se aceptan o se sustituye en `paths:` / vars de entorno.

**Cuándo ejecutar**:
- Primera vez que se usa la skill en un proyecto.
- Tras renombrar paths o estructura.
- Antes de declarar "skill funcional" en el peer doc del proyecto.

---

## Resumen — relación entre workflows

```
G (plan-guardian)
 │
 ├── 0. precondición: status repo limpio
 ├── 1. → ejecuta E (detect tests afectados → subset focalizado refinado)
 ├── 2. arquitecto diseña Service
 ├── 3. unit test + RUN subset (gate temprano) — D si rojo
 ├── 4. Route + RBAC (RBAC checklist 7 capas)
 ├── 5. Integration test
 ├── 6. Build + RUN módulo (gate completo) — D si rojo, max 3
 ├── 7-9. Frontend + refactor consumidores + i18n 4 locales (J si i18n)
 ├── 10. → ejecuta F (manual UI test)
 ├── 11. Docs (manual + bug tracker dual + doc 053 si aprendizaje)
 └── 12. Definition of done

A (restart dev)     ─ pre-requisito de F (manual UI), opcional standalone; incluye smoke /api/health
B (restart test)    ─ pre-requisito de C/D, opcional standalone; incluye sync check scripts
C (run + audit)     ─ ejecutado dentro de D (3, 4) y standalone; incluye freshness check robusto
D (regression loop) ─ invocado por G paso 3 y 6 + standalone
E (detect afectados)─ invocado por G paso 1 + standalone
F (manual UI)       ─ invocado por G paso 10 + standalone
H (migrations)      ─ standalone, auto-trigger por path
I (sprint status)   ─ standalone bajo demanda
J (i18n coherence)  ─ standalone, auto-trigger por path; G paso 9 también; locales dinámicos
K (self-check)      ─ standalone, validar adopción al copiar la skill a un proyecto
```
