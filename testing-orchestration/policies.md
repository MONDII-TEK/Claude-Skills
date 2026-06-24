# Policies — políticas generales de testing

Reglas abstractas que aplican a TODO test automatizado. Para detalles específicos de external providers (Stripe / PayPal) ver [stripe-integration.md](stripe-integration.md). Para auditoría post-run ver [audit.md](audit.md).

## Índice de políticas (17 secciones)

1. Verificación previa anti-colisión
2. Rebuild obligatorio tras cambios de código backend
3. Ejecución secuencial, nunca paralela
4. Captura output a fichero para runs largos
5. Limpieza de zombies antes de re-ejecutar tras fallo
6. Un solo run en background a la vez
7. Tests siempre configuran su propia policy
8. Integration tests no mockean DB
9. Buscar bugs, no tamperar tests
10. Política `xfail` sincronizada con resultados reales
11. Auditoría de impacto frontend tras fix backend confirmado
12. Bug tracker dual — abiertos vs gemelo histórico
13. Acompañamiento con `manage.sh` / `mt.sh`
14. Política de aislamiento de tests flaky
15. Permisos visibilidad vs acción (anti-trampa RBAC)
16. Tests de idempotencia horizontal
17. Old patterns (legacy)

## 1. Verificación previa anti-colisión

Antes de cualquier `test:*`, verificar que no haya contenedores test activos:

```bash
docker ps --format '{{.Names}}' | grep -E '<proyecto>_test-(backend-run|stripe-cli)'
```

Si la salida no está vacía → hay sesión pytest en curso. Esperar o abortar antes de lanzar otra.

**`test:stripe` automatiza esto** vía `_test_stripe_preflight`. Otros `test:*` requieren check manual.

## 2. Rebuild obligatorio tras cambios de código backend

Los tests corren contra la **imagen Docker construida**, no contra código fuente live (salvo el bind mount del directorio de tests declarado en `docker-compose.test.yml` o equivalente — consultar `CLAUDE.md` para los bind mounts del proyecto). Si cambias código backend fuera del directorio de tests, debes rebuild:

- Cambios en código backend (no-tests) → `./scripts/manage.sh build:test`.
- Cambios en deps (`requirements.txt`, `package.json` o equivalentes) → `build:test --no-cache`.
- Cambios solo en directorio de tests → no rebuild necesario (bind mount).

**Default ON**: todo `test:*` rebuilds por defecto. Opt-out con `--no-build` solo si imagen confirmadamente fresh (workflow C freshness check).

## 3. Ejecución secuencial, nunca paralela

Todos los test modules comparten el mismo `test_schema` de `db-test`. Correr dos en paralelo provoca `relation "users" does not exist` (TRUNCATE cruzado).

**Patrón seguro** entre runs consecutivos:

```bash
./scripts/manage.sh test:clean --keep-db   # cerrar run previo
docker ps --format '{{.Names}}' | grep -E 'test|run' || echo "clean"
./scripts/manage.sh test:module <nombre>   # lanzar nuevo
```

**Nunca** concatenar dos `test:*` con `&&` desde Claude Code sin teardown intermedio — el primero puede no haber soltado el container antes de que el segundo arranque.

## 4. Captura output a fichero para runs largos

```bash
./scripts/manage.sh test:stripe lifecycle_paths >/tmp/test_debug.log 2>&1
wc -l /tmp/test_debug.log
grep -nE "PASSED|FAILED|ERROR" /tmp/test_debug.log | head -30
```

`2>&1` obligatorio — pytest y Flask mezclan stderr/stdout. Stdout directo solo para unit tests rápidos (<200 líneas).

## 5. Limpieza de zombies antes de re-ejecutar tras fallo

```bash
./scripts/manage.sh test:clean
docker ps --format '{{.Names}}' | grep <proyecto>_test  # debe estar vacío
```

## 6. Un solo run en background a la vez

Cuando se lanza con `run_in_background: true`, nunca concurrentes — uno completa, validar output, luego el siguiente.

**Prohibido matar un run en curso y arrancar otro sin teardown completo**. Equivale a concurrencia: el proceso interrumpido puede haber quedado a medio TRUNCATE / migrate, schema en estado inconsistente. Síntoma: `relation "users" does not exist` en next run sin cambios de código.

**Secuencia obligatoria si hay que abortar**:
1. `TaskStop` (o `Ctrl+C`).
2. `./scripts/manage.sh test:down`.
3. Verificar `docker ps | grep _test` está vacío.
4. Solo entonces lanzar nuevo.

## 7. Tests siempre configuran su propia policy

Nunca confiar en `SystemSettings` defaults o feature flags. Fijar explícitamente las policies relevantes en setup. Evita acoplamiento a estado global.

```python
# CORRECTO
def setup_method(self):
    SystemSettings.set('membership_switch_policy', 'next_renewal')
    SystemSettings.set('membership_cancellation_policy', 'end_of_period')

# INCORRECTO
def setup_method(self):
    pass  # asume defaults
```

## 8. Integration tests no mockean DB

`test_api/` y `test_stripe/` apuntan a `db-test` real de Docker. No mockear queries ni sesiones — enmascara bugs de migración e integridad referencial.

Mocks de servicios externos (Stripe API, email) sí permitidos en `test_unit/`, no en integration.

## 9. Buscar bugs, no tamperar tests

**Regla canónica**: cuando un test falla, el fix SIEMPRE va en código de producción, nunca en el assert del test, salvo que el assert sea demostrablemente incorrecto desde el diseño.

**Workflow obligatorio ante fallo**:
1. Audit del test (vía `fullstack-architect-reviewer` o equivalente):
   - ¿Setup representa flujo real?
   - ¿Asserts reflejan reglas de negocio documentadas?
   - ¿Números derivables (FIFO, forfeit, prorrateo) o constantes arbitrarias?
   - ¿Failure mode indica bug o limitación de harness?
2. Si test correcto → diagnóstico root cause en producción, fix, re-run.
3. Si test mal diseñado → documentar hallazgo, proponer corrección, validar con usuario.

**Red flags** (NO aceptar):
- Relajar `assert X == 30` a `assert X >= 0` sin justificación.
- Añadir `pytest.approx` donde había igualdad exacta para evadir off-by-one.
- Aumentar timeouts sin evidencia.
- Eliminar asserts tras fallo.
- Mockear/stubbear la rama fallando del código real.
- Añadir `xfail` sin ticket + ETA + causa raíz.

**Cuándo SÍ ajustar test**:
- Arquitecto confirma por escrito que la regla cambió.
- Test asume comportamiento nunca especificado.
- Bug detectado en SETUP del test (fixture mal configurada, policy default no esperada).

## 10. Política `xfail` sincronizada con resultados reales

Markers `@pytest.mark.xfail`, `pytest.xfail()`, skip-por-bug deben reflejar **siempre** estado verificado más reciente. No anotaciones especulativas.

**Cuándo AÑADIR**:
1. Falla reproducible **Y**
2. Causa diagnosticada (bug producción o gap test) **Y**
3. Registrado en bug tracker activo (`051_bug_tracker.md`) con severidad + archivo + fix propuesto **Y**
4. Sin fix mergeado en mismo ciclo.

**Cuándo QUITAR**:
1. Test ejecutado en mismo contexto donde fallaba originalmente **Y**
2. Pasa en ese contexto **Y**
3. Bug tracker actualizado: entrada movida del activo a `051_bug_tracker_history.md` con verdict (CORREGIDO / NO ES BUG / OBSOLETO) + commit del fix.

**Si pasa en isolation pero falla en suite conjunta**, marker NO se retira. Acción: corregir contexto suite (marcar `stripe_heavy`, ajustar orden, añadir cooldown), re-ejecutar.

**Nunca**:
- Quitar xfail "porque creo que ya debería funcionar" sin re-ejecutar.
- Añadir xfail por fallo transitorio sin reproducir.
- Dejar marker desalineado con realidad >1 ciclo.

## 11. Auditoría de impacto frontend tras fix backend confirmado

Cuándo aplica: una vez fix backend confirmado resolutorio (tests + verificación manual si aplica).

1. Identificar endpoints, campos response, códigos error, contratos de payload cambiados.
2. Buscar consumidores en `client/src/` y `mobile/`.
3. Auditar:
   - ¿Sigue funcionando con nuevo contrato?
   - ¿Aprovecha nuevos campos/flags?
   - ¿Respeta i18n (4 locales) y tokens semánticos?
4. Entregar tabla:

   | Endpoint / campo backend | Pantalla | Opción / sección | Tab | Visible para | Verificado |

**Regla**: fix backend sin auditoría frontend = incompleto. Aplica a bugs y features.

## 12. Bug tracker dual — abiertos vs gemelo histórico

**Activo**: `docs/analysis/051_bug_tracker.md` — minimal de bugs abiertos / fixing. Sin historial.

**Gemelo histórico**: `docs/analysis/051_bug_tracker_history.md` — todo cerrado / obsoleto / no-bug confirmado / dups. Append-only.

**Plantillas copiables** (workflow #26 abrir, #27 cerrar): ver [bug-tracker-template.md](bug-tracker-template.md). Incluye plantilla mínima para activo, plantilla rica para gemelo, plantilla NO-BUG, operativa de reapertura, y comprobaciones de integridad ejecutadas en workflow I.

**Reglas operativas**:

- **Al abrir**: entrada nueva en activo siguiendo §1 de la plantilla. Estado `open` o `fixing`. Mínima historia (reproducir).
- **Al cerrar**: en mismo commit que mergea fix, reescribir con §2 de la plantilla:
  - Eliminar entrada del activo.
  - Añadir al gemelo con: ID, fecha cierre, PR/commit, causa raíz, evidencia, fix aplicado, lección si aplica.
- **Al referenciar**: abierto → activo; cerrado → gemelo. Nunca duplicar.
- **Snapshot tras run completo**: solo aplica al activo. Gemelo es append-only.
- **Plan G paso 11** distingue abrir-en-activo vs cerrar-mover-a-gemelo.
- **Verificación de integridad**: workflow I (`/testing-orchestration status`) chequea conteo + IDs duplicados + estados anómalos en el activo (terminales no movidos).

**No hay excepción**. Bugs que reabren se mueven del gemelo al activo (patrón inverso descrito en §6 de la plantilla).

## 13. Acompañamiento con `manage.sh` / `mt.sh`

**`manage.sh`** es la única entrada autorizada para Docker, test:*, env, DB del proyecto — encapsula perfiles, carga `.env`, multi-file compose, pre-flight anti-colisión.

Reglas:
- Nunca `docker compose` / `docker exec` / `docker stop` directos.
- Si falta capacidad → extender `manage.sh`, no bypassear.
- `docker ps` / `docker logs` (read-only) sí permitidos.

**`mt.sh` (helper OPCIONAL, project-specific)**: middleware para flujos manuales contra **proyectos con external billing provider** (Stripe, PayPal o similar). En IronVolt resuelve `BASE_URL`, `ADMIN_TOKEN`, `CLIENT_TOKEN`, `CUSTOMER_ID`, `PM_ID`, `STRIPE_PRICE`, `TEST_USER_ID`, `TEST_PLAN_ID`.

**Si el proyecto destino no usa external billing o no tiene un middleware similar**: ignora esta sección. El patrón canónico (admin token + curl) cubre el resto. La skill no requiere `mt.sh` para funcionar — solo lo usa cuando el proyecto lo expone.

Casos canónicos en IronVolt:
```bash
./scripts/mt.sh --env                              # diagnóstico
./scripts/mt.sh --refresh                          # forzar refresh tokens
./scripts/mt.sh 'curl -s $BASE_URL/api/health'     # comillas SIMPLES obligatorias
./scripts/mt.sh --db "u=User.query.get($TEST_USER_ID); print(u.credits)"
./scripts/mt.sh --restore                          # restore membership test user
./scripts/mt.sh --reset-credits                    # reset créditos
```

**Cuándo NO usar `mt.sh`** (incluso en IronVolt): setup de datos sin Stripe (productos, cursos). Usar admin token + curl directo.

## 14. Política de aislamiento de tests flaky

**Regla**: cualquier test flaky confirmado (no regresión) **debe** moverse a fase aislada con retry-on-failure. **No** se mantiene en fase determinista tolerando fallos. **No** se suprime con `xfail`.

**Markers por tipo**:

| Tipo | Marker | Fase aislada | Retry | Cooldown |
|---|---|---|---|---|
| Stripe lifecycle con clock advances o webhook chains | `stripe_flaky` | Phase 3 en `test:stripe`/`test:full` | 3 attempts | 30s |
| Background task con multiworker / scheduler / DB races | `bg_flaky` | Fase separada en `test:bg`/`test:full` | 3 attempts | 15s |
| API / unit | — (NO existe marker flaky) | — | — | — |

**¿Por qué dos markers separados?**: causas de flakiness son específicas del dominio. `stripe_flaky` necesita cooldown largo para drenar sidecar saturado; `bg_flaky` solo race conditions locales (15s basta).

**API/unit**: si fallan intermitentemente, **es bug** (asserts mal escritos, fixture leaked, dependencia orden). Investigar, no aislar. No existe `api_flaky` ni `unit_flaky`.

**Decisión rápida**:
```
¿test_stripe/ con test_clocks o stripe-cli sidecar?
  → stripe_flaky
¿test_api/test_background_tasks_* con threads/multiworker/leader election?
  → bg_flaky
Otro caso → NO marcar; investigar bug determinista.
```

**Proceso al detectar flakiness**:
1. Confirmar NO regresión: re-run aislado con la clase, verde.
2. Marcar con marker apropiado.
3. Documentar en tabla doc 053 §19 (stripe) o equivalente bg.
4. Commit aislado: `test(flaky): isolate <TestName> into <marker> phase — <reason>`.
5. **NUNCA** `@pytest.mark.xfail` como parche temporal (regla 10 — caso distinto).

## 15. Permisos visibilidad vs acción (anti-trampa RBAC)

Origen: BUG-018 sprint 056. `courses:read` usado como gate de escritura → cualquier rol con read podía operar sobre datos de terceros vía API.

**Anti-patrón**:
```python
# MAL — permiso semántico es "lista catálogo", se abusa como "puede operar"
if not has_permission(user, 'courses:read'):
    return 403
service.cancel_booking_for_other(...)
```

**Regla**:
- Cada permiso tiene **un** significado: `:read` / `:list` → visibilidad; `:manage` / verbos → escritura.
- Para "es staff que puede operar sobre datos de terceros", crear permiso dedicado `<module>:manage` en módulo correcto del dominio. `courses:manage` (catálogo) ≠ `bookings:manage` (operaciones).
- Wildcard `<module>:*` **no** cubre permiso de otro módulo.
- Frontend gatea por **permiso**, nunca por `role.name`.

**Gate UI ≡ permiso backend** (estricto, sin excepciones):
- El permiso del frontend debe ser **exactamente el mismo** que protege la route backend.
- "Equivalente" / "aproximado" / "proxy" → roto.
- Si UI necesita un control que el backend no permite → corregir backend o expectativa de UX. Nunca divergir.

## 16. Tests de idempotencia horizontal

Toda mutación provocada por webhook pasa por `WebhookIdempotencyService.apply_if_fresh(...)` + `.mark_applied(...)`. Toda llamada saliente mutante propaga `idempotency_key` con `outbound_key(...)`.

Tests verifican **3 propiedades por handler + 3 por wrapper saliente**:

**Entrante (handler)**:
1. Fresh event aplica → `apply=True`, lógica corre, `mark_applied` actualiza `last_applied_event_ts`.
2. Duplicate event se salta → `{'status': 'skipped', 'reason': 'duplicate_event'}`.
3. Stale event se salta → `{'status': 'skipped', 'reason': 'stale_event'}`.

**Saliente (wrapper)**:
1. Estabilidad: dos llamadas con inputs lógicos idénticos → mismo `idempotency_key` (retry-safe).
2. Unicidad: inputs distintos → claves distintas.
3. Override: caller pasa `idempotency_key='custom'` → sobrescribe auto-generación.

**Anti-patrones**:
- Mockear `WebhookIdempotencyService` a nivel `models`/`db` — usar siempre el getter para aislar handler del schema real.
- Verificar key en `call_args.args` — los wrappers lo pasan como kwarg por contrato.
- Hardcodear valores SHA-256 — usar `k1 == k2` y `len(k) == 32`.
- Inspeccionar prefijos de `event_id` para saltar guards. Productores sintéticos cumplen contrato (populan `event_ts`).

## 17. Artefactos plantillados (email / documento) — superficies acopladas

Añadir una **plantilla** (email, documento) NO es añadir una fila: es registrar el `template_id` en **N superficies que driftan** (constantes, seeds por variante e idioma, mappers, settings de auto-send, registries de hooks, validación de variables, datos de preview, UI de configuración). Olvidar una produce bugs silenciosos: el envío real funciona pero el toggle es inerte, o el preview muestra `[var]` literal, o no aparece en la UI de config. Antes de dar por hecha una plantilla nueva, **auditar TODAS las superficies** (en este proyecto: ver `docs/analysis/091_email_document_template_surfaces.md`).

Invariantes transversales (agnósticos al proyecto):

1. **Gate de envío automático en UN único punto.** El "enviar automáticamente esta plantilla" se gobierna por un flag por-plantilla y el gate vive en el **punto de encolado** (`enqueue_*`), no en cada caller. Si el flag está OFF → **no se encola** (no encolar-y-descartar en el worker). Derivar la key del flag genéricamente del `template_id` (no un map hardcoded) para que toda plantilla nueva herede el gate sin registro manual. Transaccionales críticos → bypass explícito (`skip_auto_send_check`).
2. **Preview/sample-data declarativo, no opt-in.** Los datos de prueba del preview deben derivarse del **mismo registro declarativo de variables** (cada variable con su `sample_value`), NO de un `handler_map` opt-in que alguien debe acordarse de actualizar. Un `handler_map` opt-in garantiza que **toda plantilla nueva nace con preview roto** mientras el email real sale bien — bug enmascarado.
3. **Una fuente por dato.** Si "envío real" y "preview" leen de fuentes distintas, divergen. Unificar (preview alimentado por el mapper o por el registro de variables).
4. **Test de cobertura anti-drift.** Para cada `template_id` registrado, assert que el preview no deja `[var]` sin resolver y que su toggle de auto-send existe y gatea. Convierte el gap silencioso en fallo de CI.
5. **Variante + idioma.** Si hay variantes (system-default vs clásico/editorial) y multi-idioma, la plantilla nueva se replica en TODAS siguiendo el patrón de una existente — nunca a medias.

## 18. Old patterns (legacy)

Las reglas siguientes ya no aplican o han evolucionado:

<details>
<summary>"Lo histórico vive en git log" (regla §12 doc 053 hasta 2026-04-28)</summary>

Superada por **bug tracker dual** (regla 12 arriba). El histórico vive en `051_bug_tracker_history.md`, no en git log. Razón: navegabilidad y auditabilidad estructurada.
</details>
