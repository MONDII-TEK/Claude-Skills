# Stripe & external providers — políticas específicas

Reglas que aplican solo a `test_stripe/` y similares (PayPal cuando aterrice). Para políticas generales ver [policies.md](policies.md).

## Markers

### `@pytest.mark.stripe_heavy`

Usar en tests que saturan stripe-cli con avances de reloj grandes (>30d), renovaciones múltiples, muchos webhooks encadenados. Una vez marcado:
- Se excluye de phase 1 (`test:stripe` modo light).
- Corre en phase 2 aislado (una clase por invocación pytest + cooldown).

**Cuándo marcar**: tras observar `TimeoutError` de stripe-cli en suite conjunta, con confirmación de que el test pasa en isolation.

**Cuándo NO marcar**: tests rápidos (<60s) o sin clock advances >30d.

### `@pytest.mark.stripe_flaky`

Subset de `stripe_heavy` que exhibe flakiness intermitente bajo carga, **incluso con aislamiento phase 2**. Síntomas: `TimeoutError` esperando webhooks tardíos, o asserts de balance "que no cierran" porque refund/renewal aún no se procesó cuando el test valida estado.

Tratamiento:
- Clases con este marker viven en un fichero dedicado de tests flaky de external providers (path declarado en `CLAUDE.md` §test layout), que importa helpers del fichero estable equivalente del proyecto.
- Cada clase también lleva `stripe_heavy` para que phase 2 las excluya vía `-m 'stripe_heavy and not stripe_flaky'`.
- Phase 3 (`_test_run_flaky_with_retry`) las corre con loop phase 2 (sidecar restart + cooldown) **envuelto en retry-on-failure**: hasta 3 intentos, 30s de cooldown entre intentos. Primer intento exitoso termina la phase.
- `test:stripe:flaky` expone phase 3 standalone para validación dirigida.
- `test:stripe` y `test:full` incluyen phase 3 automáticamente; `--skip-heavy` la omite junto con phase 2.

**Cuándo marcar**: tras observar que pasa en isolation pero falla intermitentemente incluso en phase 2 aislada.

**Cuándo NO**: si pasa siempre en isolation pero falla siempre en full → `stripe_heavy` (phase 2) basta.

### `@pytest.mark.stripe_only`

Tests Stripe-específicos sin paralelo PayPal. Markers actuales:
- `invoice.upcoming` (no existe en PayPal).
- `cancel_at_period_end` subscription.updated (PayPal SUSPENDED es semánticamente distinto).
- BUG-004 subscription_create duplicate guard (Stripe-specific).

Registrado en `pytest.ini`. Los tests de contrato ledger/lifecycle parametrizables siempre cubren ambos providers; los `stripe_only` son la excepción documentada.

## Tests parametrizados por provider (Stripe + PayPal)

Tests de contrato ledger/lifecycle deben verificar invariantes **agnósticas al provider**:

```python
@pytest.mark.parametrize('provider', ['stripe', 'paypal'])
class TestActivationLedgerContract:
    def test_activation_creates_credit_transaction_linked_to_invoice(
        self, client, db_session, subscription_user, subscription_plan, provider,
    ):
        _activate_membership_webhook(provider, client, db_session, user, plan)
        # Mismas aserciones sobre Invoice + CreditTransaction + MembershipHistory
```

Helpers agnósticos en `test_subscription_lifecycle_api.py`: `send_provider_webhook`, `_activate_membership_webhook`, `_renew_membership_webhook`, `_pre_payment_event_webhook`, `_one_time_checkout_webhook`.

**Halt trigger**: si `[stripe]` pasa y `[paypal]` falla en un test parametrizable → bug real, pinpoint por arc reporting pytest. **No** usar `xfail`. Abordarlo primero.

## Two-phase + flaky split

`./scripts/manage.sh test:stripe` ejecuta tres fases:

**Phase 1** (`@pytest.mark.stripe_integration and not stripe_heavy`):
- Invocación pytest única.
- Sidecar stripe-cli compartido.

**Restart sidecar entre phase 1 y phase 2**: tras phase 1, `cmd_test_stripe` llama `_stripe_cli_stop` + `sleep 3` + `_stripe_cli_start` + `sleep 15` para garantizar cola limpia. Necesario porque phase 1 deja backlog que extiende latencias.

**Phase 2** (`@pytest.mark.stripe_heavy and not stripe_flaky`):
- Cada clase en su PROPIA invocación pytest (host-side loop en `_test_run_heavy_isolated`).
- **Restart sidecar entre cada clase** + cooldown 15s. Patrón canónico: "cada heavy empieza con cola vacía".
- Backend persistente phase 2: un único container `test-backend-heavy` mantiene vivo el backend toda la fase, evita race TCP entre sidecar y backend efímero.

**Phase 3** (`@pytest.mark.stripe_flaky`):
- Mismo loop que phase 2 (sidecar restart + cooldown) **+ retry-on-failure**: 3 attempts, cooldown 30s entre intentos.
- Primer intento exitoso termina la phase.
- Si falla 3 → fase rojo, marca `total_result=1`. NO es opt-out de fallos.

## Helper `stripe_heavy_collect.py` + host-side loop

**Arquitectura phase 2** (2026-04-19+): el loop vive en el **host** dentro de `_test_run_heavy_isolated` (`manage.sh`), NO dentro del container. Razón: sidecar `stripe-cli` corre como servicio docker compose en host; su restart solo es invocable desde fuera del container.

**Flujo**:
1. **Host collect**: `docker compose run --rm -T --no-deps backend sh -c "pip install pytest pytest-cov --quiet && python /app/stripe_heavy_collect.py <test_path> -m stripe_heavy"` captura lista de clases heavy a stdout.
2. **Backend persistente phase 2**: `docker compose run -d --name <proyecto>_test-backend-heavy --no-deps ... backend sh -c "pip install pytest pytest-cov --quiet && tail -f /dev/null"` mantiene backend vivo toda la fase. Readiness wait: `while ! docker exec "$backend_name" python -c "import pytest"; do sleep 1; done` (cap 60s).
3. **Host loop**: por cada clase, `docker exec -i -e STRIPE_WEBHOOK_SECRET=… "$backend_name" sh -c "{ python -m pytest <cls> -v; echo \$? > /tmp/pytest_rc; } 2>&1 | tee -a logs/test_results_heavy.log; exit \$(cat /tmp/pytest_rc)"`. `tee` para streaming live; rc via `/tmp/pytest_rc` para no enmascarar exit code.
4. **Entre clases**: `_stripe_cli_harvest_logs` → `_stripe_cli_stop` → `sleep 3` → `_stripe_cli_start` → `_stripe_cli_wait_for_secret` → re-export `STRIPE_WEBHOOK_SECRET` → `sleep 15`. Backend persistente ignora restart sidecar — DNS no cambia.
5. **Teardown phase 2**: `docker stop --time 5 <proyecto>_test-backend-heavy` + `docker rm -f`. Siempre en cleanup aunque loop falle.

**`stripe_heavy_collect.py`**: usa `pytest.main([...], plugins=[_Collector()])` con `pytest_collection_finish(session)` para imprimir línea por clase única con tests seleccionados. Necesario porque pytest 9.0.3 cambió formato default de `--collect-only -q` (rompió grep tradicional). `pytest_collection_finish` corre DESPUÉS del filtro `-m`.

## Captura de logs sidecar — imprescindible

`stripe-cli` sidecar corre en container separado del backend tests. Sus logs (timeline de webhooks, errores DNS, 5xx, timeouts, retries) NO aparecen en pytest. Pytest solo ve lo que el backend responde.

**Harvest automatizado** en `manage.sh`: `_stripe_cli_harvest_logs` vuelca `docker logs <proyecto>_test-stripe-cli-*` al `stripe_cli.log` del run dir + surfacea errores al stdout del run.

Se invoca:
- Antes de cada `_stripe_cli_stop` (preserva logs antes de destruir container).
- Tras cada clase heavy en phase 2 (captura webhooks del último minuto antes del restart).

**Review post-run obligatorio**:
```bash
grep -E "\[ERROR\]|5[0-9]{2}|refused|timeout|no such host" /tmp/test_results_stripe_cli.log | head -30
```

- `[ERROR] Failed to POST` tras restart → race DNS con backend efímero.
- `5xx` del backend → fallo procesando webhook (mirar logs backend).
- `refused` → backend aún no listo.

**Regla canónica**: revisar SIEMPRE backend.log + stripe_cli.log antes de declarar run "verde". Pytest 100% PASSED + ERRORS en sidecar = sospechoso → bugs latentes que se manifestarán en producción.

## Constraint Stripe interval change

**Validado 2026-04-20** en `test_interval_change_feasibility.py` (xfail strict permanente):

Llamar `stripe.Subscription.modify(billing_cycle_anchor='unchanged', items=[{price: ...}])` con price de distinto `recurring.interval` produce:

```
InvalidRequestError: Changing plan intervals. There's no way to leave billing cycle unchanged.
```

**Implicación**:
- Guard `INTERVAL_CHANGE_REQUIRES_IMMEDIATE_POLICY` en `membership_lifecycle_service.py:452-472` queda justificado empíricamente (no precautionary).
- Con `membership_switch_policy=next_renewal`, no se permite cambio entre periodicidades distintas.
- Frontend cierra el camino en `use-subscription-flow.ts` + `subscription-dialog.tsx` con flag `requires_interval_change_confirmation`.

**Procedimiento user-facing**: usuario cancela renovación → plan vigente hasta fin de periodo → contrata nuevo plan libremente al expirar.

**Para tests**: si combinan `next_renewal` + `is_recurring=True` + intervalos distintos, alinear cadencias en fixture o usar `policy=immediate` (salvo que prueben específicamente el bloqueo, en cuyo caso aseverar `status_code=400` + `error_code=INTERVAL_CHANGE_REQUIRES_IMMEDIATE_POLICY`).

**Feasibility test** queda como `@pytest.mark.xfail(strict=True)` — si flipa a XPASS, Stripe cambió API y habría que re-evaluar el guard.

## Playbook tests lifecycle E2E (switch → cancel → expire → idempotencia)

**Origen**: reestructura de `TestFullLifecycleSwitchCancelExpire` al cerrar BUG-012. Patrón reusable para validar ciclo completo sobre Stripe real.

**Principios**:

1. **Siempre driver HTTP**, nunca capa servicio directa. Un switch via `service.switch_plan()` + `stripe.Subscription.cancel()` manual omite webhooks reales. Un POST a `/api/membership/switch` obliga a que Stripe emita eventos naturales (`customer.subscription.updated`, `invoice.payment_succeeded`).

2. **`wait_for_webhook` tras cada acción que dispare webhook**. Cada `lambda` debe invalidar sesión con `db.session.expire_all()` antes de consultar (objetos ORM cacheados del test no reflejan escrituras del worker webhook).

3. **Distinguir semánticamente**:
   - `cancel-renewal` (usuario desactiva auto-renew) → MH `renewal_cancelled` (síncrono) + webhook → MH `pending_cancellation`. NO emite `grace_period`.
   - `cancel_with_policy(end_of_period)` (admin) → sí emite `grace_period`.
   - `subscription.deleted` (período expiró) → MH `expired` + forfeit créditos.

4. **Background task no-op pre-expiración**: `MembershipExpirationTask().execute()` mientras periodo vigente (con `pending_cancellation`) debe ser idempotente — NO tocar créditos ni plan, NO cerrar el MH de cancelación.

5. **Clock advance al final**: `advance_clock(..., seconds=period_end + 1d)` fuerza emisión `customer.subscription.deleted`. `wait_for_webhook` para MH `expired`.

6. **Idempotencia post-expiración**: re-ejecutar `task.execute()` tras expiración. Contar `CreditTransaction.source IN ('membership_expiration', 'membership_cancellation')` antes/después. Deben coincidir, `user.credits` inalterado.

**Skeleton**:
```python
# Step N — switch via HTTP
resp = client.post('/api/membership/switch', json={'new_plan_id': new_plan.id}, headers=headers)
assert resp.status_code == 200
wait_for_webhook(app,
    lambda: (db.session.expire_all() or True) and
        PaymentSubscription.query.filter_by(
            external_subscription_id=sub.id, subscription_plan_id=new_plan.id,
        ).first() is not None,
    timeout=60, description='subscription.updated')

# Step N+1 — cancel-renewal
resp = client.post('/api/membership/cancel-renewal', headers=headers)
assert resp.status_code == 200
wait_for_webhook(app,
    lambda: (db.session.expire_all() or True) and
        MembershipHistory.query.filter_by(
            user_id=user.id, action_type='pending_cancellation',
        ).first() is not None,
    timeout=60, description='pending_cancellation MH')

# Step N+2 — task no-op during grace
task = MembershipExpirationTask()
task.execute()
assert user.credits == credits_before
assert user.subscription_plan_id == new_plan.id

# Step N+3 — advance clock → expiration webhook
stripe.test_helpers.test_clocks.TestClock.advance(
    clock_id, frozen_time=int(sub_period_end.timestamp()) + 86400)
wait_for_webhook(app,
    lambda: (db.session.expire_all() or True) and
        MembershipHistory.query.filter_by(
            user_id=user.id, action_type='expired',
        ).first() is not None,
    timeout=120, description='subscription.deleted → expired')

# Step N+4 — task idempotency
credits_after_expire = user.credits
txs_before = CreditTransaction.query.filter(
    CreditTransaction.user_id == user.id,
    CreditTransaction.source.in_(['membership_expiration', 'membership_cancellation']),
).count()
task.execute()
assert user.credits == credits_after_expire
assert CreditTransaction.query.filter(...).count() == txs_before
```

**Evitar**:
- Triple-paso `service.switch_plan` + `stripe.Subscription.cancel` + `_activate_subscription`. El cancel manual emite `subscription.deleted` espurio que limpia `user.subscription_plan_id` y contamina estado.
- Buscar `grace_period` tras `cancel-renewal`. No se emite en ese path.
- Omitir `db.session.expire_all()` en lambdas de `wait_for_webhook` — timeout sobre ORM cache obsoleto.

## Tests de idempotencia horizontal — patrón concreto

Ver [policies.md](policies.md) §16 para reglas generales. Pattern de test (Fase 5):

```python
@patch('services.payment_service.get_webhook_idempotency_service')
def test_duplicate_invoice_payment_skipped(self, mock_get_svc):
    mock_svc = MagicMock()
    mock_svc.apply_if_fresh.return_value = ServiceResult.ok(
        {'apply': False, 'reason': 'duplicate_event'}
    )
    mock_get_svc.return_value = mock_svc
    handler = PaymentService.__new__(PaymentService)
    handler._logger = MagicMock()
    result = handler._handle_payment_succeeded(fake_event, ...)
    assert result.success and result.data['status'] == 'skipped'
    mock_svc.mark_applied.assert_not_called()
```

**Tests de referencia** (todos pure-unit, sin DB):
- `test_unit/services/test_webhook_idempotency_service.py` — servicio base.
- `test_unit/services/test_subscription_handler_idempotency.py` — Fase 3 (6 handlers suscripción).
- `test_unit/services/test_ecommerce_handler_idempotency.py` — Fase 4.
- `test_unit/services/test_payment_service_handler_idempotency.py` — Fase 5.
- `test_unit/services/test_payment_provider_idempotency_key.py` — Fase 6.
- `test_unit/services/test_payment_service_outbound_keys.py` — Fase 7.

## Stripe CLI manual

Para repro local sin tests automatizados:

```bash
curl -sL https://github.com/stripe/stripe-cli/releases/download/v1.21.0/stripe_1.21.0_linux_x86_64.tar.gz \
  -o /tmp/stripe.tar.gz && tar -xzf /tmp/stripe.tar.gz -C /tmp/

BACKEND_URL="${BACKEND_URL:?exportar BACKEND_URL según CLAUDE.md del proyecto (ej. http://localhost:5001)}"
/tmp/stripe listen --forward-to "$BACKEND_URL/api/payments/webhook/stripe" --api-key "$STRIPE_TEST_SECRET_KEY"
/tmp/stripe trigger invoice.payment_succeeded --api-key "$STRIPE_TEST_SECRET_KEY"
/tmp/stripe test_clocks create --frozen-time=$(date +%s) --api-key "$STRIPE_TEST_SECRET_KEY"
```

API key = `STRIPE_TEST_SECRET_KEY` en `.env`. URL = `BACKEND_URL` exportado según `CLAUDE.md`.
