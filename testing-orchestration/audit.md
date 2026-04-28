# Audit — protocolo post-run del run dir unificado

Tras cualquier `test:*`, el arquitecto **debe** abrir `logs/test_runs/<UTC-ts>_<label>/` antes de emitir veredicto. Leer solo `summary.log` no es suficiente: el resumen refleja exit code de pytest, no regresiones silenciosas (errores de container, webhook no entregado, DB no truncada, migraciones no aplicadas).

## Fuente única de auditoría

**Dir unificado del host**: `logs/test_runs/<ts>_<label>/`. Append-only durante run, **inmutable post-run**.

**NO auditar archivos legacy del volumen Docker** (`logs/test_results.log`, `logs/test_results_heavy.log`): son quick-view para `test:logs`, reflejan solo última fase / última invocación pytest, se sobrescriben entre runs.

## Cuándo se audita

- **Al final del run completo** (tras `_test_finalize_run_dir` single-phase, tras fase 5 o teardown en `test:full`).
- **Nunca** intermedio entre fases — logs de containers (db-test, stripe-cli) se consolidan al teardown.
- Si run abortado (failfast, kill, excepción): auditar igual con lo que haya. Distinguir ausencia esperada (fase no alcanzada) vs anómala (fase corrió pero log no capturado).

## Checklist por archivo

### `summary.log` — ALWAYS

```bash
cat "${RUN_DIR}summary.log"
```

Confirma:
- `rc` por fase + timestamps.
- Detectar saltos sospechosos (fase larga que termina <2s sugiere abort temprano no reportado).

### `backend.log` — ALWAYS

```bash
grep -nE "PASSED|FAILED|ERROR|CRITICAL|InternalError|OperationalError|MigrationError|psycopg2" \
  "${RUN_DIR}backend.log" | head -30
```

Buscar:
- `ERROR` / `CRITICAL` / tracebacks no-xfail.
- `InternalError`, `OperationalError`, `MigrationError`, `psycopg2` crashes.
- `FAILED` de pytest con contexto completo (no solo última línea).

### `backend_heavy.log` — solo si fase 2 corrió

```bash
[ -f "${RUN_DIR}backend_heavy.log" ] && \
  grep -nE "FAILED|ERROR|TimeoutError" "${RUN_DIR}backend_heavy.log" | head -20
```

Mismo patrón que backend.log, por clase.

### `db_test.log` — solo si `db-test` arrancó

```bash
[ -f "${RUN_DIR}db_test.log" ] && \
  grep -nE "FATAL|deadlock|database system is ready|restart" "${RUN_DIR}db_test.log" | head -10
```

Verificar:
- Arranque limpio (`database system is ready`).
- Sin `FATAL`, `deadlock detected`, restarts inesperados.

### `stripe_cli.log` — solo si sidecar arrancó

```bash
[ -f "${RUN_DIR}stripe_cli.log" ] && \
  grep -nE "\[ERROR\]|5[0-9]{2}|refused|timeout|no such host" "${RUN_DIR}stripe_cli.log" | head -20
```

Confirmar:
- Forwarding activo, eventos entregados.
- Sin `403`/`401`/`connection refused`/`timeout`/`no such host` al backend.

## Matriz de cobertura (derivada del setup real)

La cobertura esperada se deriva del setup que cada invocación levanta. **No** es fija por tipo de test.

| Archivo | Cuándo es exigible |
|---|---|
| `backend.log` | **Siempre** (cualquier `test:*` levanta backend-run) |
| `db_test.log` | Solo si run arranca `db-test`. Convención: todos los `test:module/api/bg/stripe/full` lo hacen. `test:unit` puede o no según fixtures (los que usan `db_session` sí, los puros con mocks no) |
| `stripe_cli.log` | Solo si run arranca sidecar — fase `test:stripe` (light o heavy) o fases 4-5 de `test:full`. `test:stripe --heavy-only` sin clases que usen sidecar → basta confirmar forwarding activo, no tráfico |
| `backend_heavy.log` | Solo si corrió ≥1 clase `stripe_heavy` (fase 5 full o `test:stripe --heavy-only`) |

**Reglas**:
- Archivo exigible faltante / vacío → **DISCREPANCIA**: investigar fallo de captura (`docker logs` tras container eliminado), arranque sidecar, bug en `_test_init_run_dir`/`_db_test_harvest_logs`/`_stripe_cli_harvest_logs`.
- Archivo no exigible (contenedor no levantado): **N/A** justificado, no DISCREPANCIA.

## Veredicto al usuario

Estructura fija:

```markdown
## Auditoría run — <RUN_DIR>

### Resumen pytest
- Fase 1/N: PASS / FAIL / SKIP — <count>
- ...

### Path del run
`logs/test_runs/<ts>_<label>/`

### Errores significativos
- `backend.log:line` — <descripción + contexto 2-3 líneas>
- `backend_heavy.log:line` — ...
- `stripe_cli.log:line` — ...
- `db_test.log:line` — ...

### Cobertura de logs
- `summary.log`: [OK]
- `backend.log`: [OK] / [DISCREPANCIA: vacío pese a fase 1 corriendo]
- `backend_heavy.log`: [OK] / [N/A: fase heavy no corrió]
- `db_test.log`: [OK] / [N/A: test:unit puro] / [DISCREPANCIA: db-test arrancó pero log vacío]
- `stripe_cli.log`: [OK con N eventos forwarded] / [N/A: no es test:stripe]

### Si hubo fases [SKIP] (failfast)
- Fase X cortó la cadena por fallo en fase Y

### Próximo paso recomendado
- Si verde: proceder a frontend / merge / siguiente paso del plan G.
- Si rojo: workflow D loop con scope = <subset>.
- Si DISCREPANCIA: investigar harness antes de decidir si run válido.
```

## Reglas anti-trampa

- **Nunca veredicto solo con exit code**. Run verde con `db_test.log` vacío (cuando db-test corrió) o `stripe_cli.log` sin eventos (cuando fase stripe corrió tests dependientes del sidecar) es **caso de estudio**, no éxito.
- **Si datos ambiguos** → marcar **⚠️ PARCIAL** con gap concreto, no forzar PASS/FAIL.
- **Antes de declarar verde** un run con fase stripe: revisar SIEMPRE tanto `backend.log` (pytest + errores app) como `stripe_cli.log` (sidecar). Run con pytest 100% PASSED + ERRORS en sidecar es sospechoso — bugs latentes que se manifestarán en producción.
