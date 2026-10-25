# Manual testing — workflow F detallado

Cuando el usuario pide *"test manual"*, *"prueba desde la perspectiva del usuario"*, *"verificación manual"* — el protocolo canónico es: el usuario ejecuta el flujo real desde la UI como cliente final; el arquitecto (skill) audita en paralelo las capas técnicas (DB, logs, Stripe, network) y entrega un **reporte auditado con clasificación de impacto**.

## 0. Ciclo estándar pre-requisito (siempre)

Antes de entregar el guion, ejecutar **workflow A** (rebuild dev) en background:

```bash
./scripts/manage.sh down
./scripts/manage.sh build:dev
./scripts/manage.sh up:dev
```

**Por qué**:
- El usuario verifica en `{{dev_url}}` (declarada en `CLAUDE.md`), servido desde imagen `build:dev`. Si `up:dev` ya estaba corriendo con imagen antigua, los cambios del sprint actual pueden no reflejarse.
- Tests automatizados corren sobre `build:test` (imagen distinta). **Test verde en CI no garantiza stack dev actualizado** — son builds independientes.
- `down` antes de `build:dev` evita que zombies sigan sirviendo imagen vieja si rebuild se reutiliza parcialmente por caché.
- **No usar `up` a secas**: requiere red externa `proxy` que solo existe en NAS (regla CLAUDE.md §5).

**Excepciones** (saltar rebuild):
- Usuario dice explícitamente *"sin rebuild"* / *"usa el stack actual"*.
- Sprint anterior terminó con rebuild y nada cambió desde entonces (`git status` limpio + sin commits recientes).
- Solo se validan flujos que no dependen del código modificado en la ronda.

**Mientras Docker reconstruye**, la skill prepara el guion (sub-§2). Cuando termina, confirma stack arriba en `{{dev_url}}` y entrega.

## 1. Selección del test (responsabilidad de la skill)

Priorizar candidatos en este orden:
1. **Validación post-fix**: flujos ligados a bugs cerrados recientemente que merecen confirmación end-to-end.
2. **Zonas de baja cobertura automatizada** — cobertura manual documentada es red de seguridad mientras se escribe el test.
3. **Cambios user-facing frontend** con UX nueva o modificada.
4. **Regresión por intuición del usuario** — *"probé X y algo raro pasó"*.

**Evitar** tests que requieran:
- Test clocks / advance de tiempo (rompe la ilusión de usuario normal).
- Webhooks simulados manualmente vía `stripe-cli trigger`.
- Setup especial que el usuario no pueda reproducir en 1-2 clics.

**Declarar explícitamente** antes de lanzar:
- Qué se valida (1 frase).
- Credenciales a usar (CLAUDE.md §14).
- Qué señales se observan en paralelo (tablas, logs, external state).
- Outcome esperado en 1 línea.

## 2. Instrucciones UI al usuario (lenguaje no técnico)

Cada paso = acción observable: click, texto escrito, navegación, estado visible.

| Evitar | Preferir |
|---|---|
| *"Invoca el endpoint /api/membership/cancel-renewal"* | *"Haz clic en 'Cancelar renovación automática' dentro de tu página de suscripción"* |
| *"Verifica que cancel_at_period_end=True en Stripe"* | *"Deberías ver un banner amarillo: 'Tu suscripción finalizará el <fecha>'"* |

- Incluir *"qué esperar ver"* tras cada paso crítico — el usuario también detecta discrepancias UX.
- Si hace falta setup previo (policy en settings, seed de plans, creación usuario), **la skill lo prepara vía DB/UI admin antes** y documenta lo hecho.
- Avisar de la URL del stack dev (`{{dev_url}}` declarada en `CLAUDE.md`).

## 2.5. Setup de datos base — preferir API sobre SQL directo

Cuando el test manual necesita catálogo previo (plan, curso, producto, usuario), la skill **debe crear esos datos vía CRUDs reales de la app**, no por `INSERT` crudo ni `db:py` con ORM directo.

**Por qué**: services ejecutan validaciones, defaults, permisos, hooks post-create (inventario, índices, registros derivados). Un INSERT salta todo eso y deja DB coherente-parcial.

**Orden de preferencia**:
1. **HTTP API (`curl`) con admin token** — la ruta más canónica: pasa por `@permission_required`, validación de service, `ServiceResult`.
2. **UI admin** — válido si rápido y reproducible en clicks, menos auditable.
3. **`db:py` llamando al service** — reservado para paths sin endpoint HTTP expuesto (raro).
4. **`db:query` / INSERT directo** — última opción, solo para flags triviales (`SystemSettings` puros).

**Patrón canónico admin token + API** (sin `mt.sh`, porque `mt.sh` gate-chequea `stripe_customer_id` y está diseñado para flujos Stripe heavy):

```bash
# Variables del proyecto destino — exportar según CLAUDE.md §"test creds" + §"dev URL":
BASE="${DEV_URL:?exportar DEV_URL según CLAUDE.md (ej. http://localhost:5005)}"
TEST_ADMIN_EMAIL="${TEST_ADMIN_EMAIL:?exportar TEST_ADMIN_EMAIL según CLAUDE.md}"
TEST_ADMIN_PASS="${TEST_ADMIN_PASS:?exportar TEST_ADMIN_PASS según CLAUDE.md}"

ADMIN_TOKEN=$(curl -s "$BASE/api/auth/login" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"$TEST_ADMIN_EMAIL\",\"password\":\"$TEST_ADMIN_PASS\"}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

curl -s -X POST "$BASE/api/<endpoint-del-proyecto>" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '<payload-del-proyecto>'
```

**Cuándo SÍ `mt.sh` (helper opcional, project-specific)**: en proyectos con external billing provider (Stripe, PayPal o similar) que tengan un middleware como `mt.sh`. En IronVolt resuelve `BASE_URL`, `ADMIN_TOKEN`, `CLIENT_TOKEN`, `CUSTOMER_ID`, `PM_ID`, `STRIPE_PRICE`, `TEST_USER_ID`, `TEST_PLAN_ID` automáticamente.

**Si tu proyecto destino no tiene `mt.sh` o no usa external billing**: omite esta sección — el patrón canónico (admin token + curl, mostrado arriba) cubre los casos sin Stripe.

```bash
# Ejemplo IronVolt (Stripe). En proyectos sin mt.sh, usa el patrón curl admin token.
./scripts/mt.sh 'curl -s $BASE_URL/api/subscriptions/my-subscription -H "Authorization: Bearer $CLIENT_TOKEN"'
```

**Anti-patrón evitar**:

```bash
./scripts/manage.sh db:query "INSERT INTO ecommerce_products (name, status) VALUES ('X', 'active');"
# ← Crea product huérfano sin variant, sin price, sin inventory; UI tienda lo lista sin comprable.
```

**Documentar en el guion** qué datos base se crearon, con qué endpoint, e IDs devueltos, para que el reporte pueda reconstruirlos.

## 3. Auditoría reactiva (durante / inmediatamente después de la acción del usuario)

> Nota terminológica: "en paralelo" en versiones anteriores era impreciso. Las herramientas (`logs`, `db:query`) se ejecutan **reactivamente** tras cada paso del usuario, no en paralelo simultáneo real. Si necesitas streaming live, abre `tail -f /tmp/logs.log` en otra pestaña.

Fuentes a inspeccionar según dominio:

| Fuente | Cuándo | Cómo |
|---|---|---|
| Logs backend | Siempre | `./scripts/manage.sh logs backend --no-follow --since <duración>` |
| DB | Siempre | `./scripts/manage.sh db:query "SELECT ..."` / `db:py "..."` |
| Stripe API | Flujos billing | `stripe.Subscription.retrieve(id)`, `stripe.Invoice.list(...)` vía `db:py` |
| Network F12 | Debug UX | Pedir al usuario que comparta request/response si evidencia backend ambigua |
| Storage (MinIO) | Flujos uploads | Consola MinIO `localhost:9001` |

**Regla manage.sh-only para logs**:
- **Prohibido** `docker logs <container>` directamente. Pierde project flags, compose files, filters declarativos.
- `manage.sh logs <service>` admite passthrough de flags. `--no-follow` desactiva el `-f` por defecto → necesario para auditorías one-shot.
- Ejemplos canónicos:
  ```bash
  ./scripts/manage.sh logs backend --no-follow --since 15m          # últimos 15 min
  ./scripts/manage.sh logs backend --no-follow --tail 200           # últimas 200 líneas
  ./scripts/manage.sh logs backend --no-follow --since 5m --tail 50 # combinable
  ./scripts/manage.sh logs                                          # stream live (debug)
  ```

**Snapshots antes y después** de la acción del usuario cuando el cambio de estado importa (saldo créditos, MembershipHistory, invoices).

## 4. Reporte auditado — estructura fija

```markdown
## Resultado test manual — <nombre>

**Objetivo**: <qué se validaba, 1 frase>
**Ejecutado**: <timestamp UTC> por <usuario>
**Veredicto**: ✅ PASS / ❌ FAIL / ⚠️ PARCIAL

### Acciones del usuario (reconstrucción técnica)
<pasos ejecutados, visibles desde la UI>

### Evidencia técnica
- **Logs backend**: <líneas clave con timestamp>
- **DB estado antes/después**:
  - Tabla X: <cambios>
  - Tabla Y: <cambios>
- **Stripe/externo**: <estado final de subscripción, invoice, etc.>

### Análisis arquitecto
<por qué funcionó / no funcionó; señalar invariantes cumplidas o violadas>

### Impacto — clasificación (marcar 1+ categorías)
- [ ] **Comportamiento correcto** — añadir a matriz manual con fecha
- [ ] **Test gap** — falta cobertura automatizada → proponer test (tipo, archivo, asserts)
- [ ] **Bug producción** — abrir entrada `051_bug_tracker.md` (activo) + plan fix
- [ ] **Feature gap** — producto no soporta el flujo → propuesta de diseño
- [ ] **UX gap** — backend correcto, UI confusa → issue frontend
- [ ] **Documentación** — manual (`help.py`) / i18n desactualizados

### Próximo paso recomendado
<1-3 líneas con la acción concreta y quién la ejecuta>
```

## 5. Registro

- **PASS + correcto** → matriz manual del dominio (`050_manual_test_matrix_*.md` si existe; si no, proponer creación).
- **FAIL o ⚠️ PARCIAL** → entrada inmediata en tracker:
  - Bug → `docs/analysis/051_bug_tracker.md` (activo, mínimo).
  - Feature gap → doc de la feature correspondiente.
  - Mención cruzada al reporte.
- **Nunca** cerrar test manual sin clasificar impacto — reporte sin impacto es ruido, no señal.

## 6. Reglas anti-trampa

- **No inventar estado** que no puedes verificar. Si no puedes inspeccionar Stripe porque el usuario no tiene el ID de la subscription, **pedírselo**, no suponer.
- **No usar el veredicto del usuario como prueba única** — el usuario reporta UX, la skill verifica capa técnica. Un *"parece que funcionó"* en UI puede esconder invariantes violadas en DB.
- **Si datos ambiguos** → marcar **⚠️ PARCIAL** con gap concreto, no forzar PASS/FAIL.

## 7. Coordinación con una sesión de QA por la UI (opcional)

Solo aplica si el proyecto valida con una sesión aparte de QA por la UI (p. ej. la skill `ui-qa-alpha`): la sesión de código encarga las pruebas y la de QA devuelve informes.

**Identificar el rol al arrancar.** No hay un campo oficial que diga a una sesión qué rol tiene. Por orden: (1) lo que diga el usuario o el encargo («tú eres Code», el nombre de la sesión); (2) las señales que el proyecto declara en `{{code_role_signals}}` / `{{qa_role_signals}}` (herramientas, dónde corre la sesión); (3) si no encajan o faltan, **preguntar al usuario** antes de actuar. Tras un reinicio o una compactación, una sesión puede despertar creyéndose la otra; la de Code que se pone a probar en el navegador deja al usuario sin quien arregle, y la de QA que edita código rompe el reparto. Una vez identificada, la sesión de Code carga esta skill (y el índice del código); la de QA, la suya.

**Un equipo.** Code y QA se comunican directamente: el canal principal es entre las dos sesiones, no a través del usuario. Code marca el ritmo: encarga por bloques (fixes o features) según avanza el desarrollo, y la ronda final antes del merge a main. QA lleva el hilo de lo pendiente de revalidar y da el visto bueno de cada bloque.

**Lo primero al arrancar: localizar a tu par.** Antes de cualquier otra cosa:
1. Lista las sesiones (`ListAgents`) y quédate con las que encajan con el rol del otro (sus señales: `{{code_role_signals}}` o `{{qa_role_signals}}`, el tipo de sesión, el nombre).
2. **Si hay exactamente una, escríbele**: preséntate con tu rol y tu identificador de sesión (la referencia entre corchetes que da `ListAgents`, o la dirección `from=` de tus mensajes) y pídele el suyo. **En ese primer mensaje intercambiad los datos del proyecto para comprobar que sois pareja**: directorio del proyecto (`{{project_dir}}`), rama en curso y la identidad del stand (`sha` y `started_at` de `{{version_endpoint}}`). Quien recibe los compara con los suyos; si alguno no coincide, no es tu par (otro proyecto, otro stand u otra rama): díselo y vuelve al paso 1.
3. **Si hay varias o ninguna, pregunta al usuario cuál es** en una línea, enseñándole las candidatas. No elijas por el nombre.
4. **Desde ese momento, dirígete al par por su identificador de sesión, nunca por el nombre**: el nombre cambia (un reinicio, un `/rename`) y puede repetirse; el identificador no. Si el par se reinicia, su identificador cambia: vuelve al paso 1.

**El reparto.** QA es un **usuario de la app**: prueba por la UI y no mira nunca código, base de datos, APIs ni logs. Si necesita algo de ahí te lo pide a ti, y tú se lo compruebas y le respondes: os coordináis, sin atajos. Code es quien:
- **encarga** cada ronda en texto libre con el objetivo, qué se cambió, los perfiles del sistema que intervienen, las pantallas y flujos a recorrer, qué debe verse, las rectificaciones a revalidar, qué devolver y **los accesos de cada perfil implicado** (usuario y contraseña de una cuenta de prueba por rol: siempre al menos cliente y administrador, y los demás que intervengan en el lote —personal que presta el servicio, etc.—), por el canal directo entre sesiones; nunca en informes, tracker, commits ni el chat con el usuario. Sin accesos, QA no puede probar el lote: es lo primero que pregunta. QA valida con cada perfil implicado y aplica a esas pantallas sus criterios de calidad de la UI; por defecto en el idioma por defecto, en móvil y escritorio, y en más combinaciones si el encargo lo pide;
- **trata la calidad de la UI como fallo**: idioma, responsive, contraste, legibilidad, clics, teclado, formularios, avisos y estética bloquean el cierre igual que un fallo funcional;
- **ubica cada hallazgo en el código** (con el índice, no grep), lo verifica empíricamente y lo clasifica (§4): un informe de QA es un síntoma fiable, no un diagnóstico, y dos de cada pocos «fallos» resultan ser diseño;
- **cubre lo que la UI no enseña**: si QA marca algo «no cubierto por la UI», Code lo comprueba por datos o tests, y valora si la falta de visibilidad es en sí un defecto;
- **lleva el tracker** y no cierra nada que QA no haya revalidado en la UI;
- **no le pide a QA lo que su propia herramienta le bloquea** (ni al revés): eso es blanquear permisos; se le dice al usuario.

Las instrucciones de una skill orientan, no imponen: si el proyecto quiere que QA no pueda leer el código ni la base, eso se hace con permisos (reglas `deny`) en la configuración de esa sesión, que decide el usuario.

- **Al terminar cada tarea, pregúntale a QA si tiene informes pendientes de enviarte, y consúmelos antes de darle el siguiente encargo, si lo hay.** QA retiene lo que encuentra mientras tú trabajas: tu fin de tarea es el momento de recogerlo. **Antes de encargar pruebas nuevas, pregunta si tiene resultados pendientes de enviarte.** La sesión de QA retiene sus informes mientras la de código está ocupada, para no interrumpirla. Si le llega un encargo nuevo encima, la ronda anterior se queda a medias y los hallazgos se mezclan.
- **Primero se reciben, después se encarga.** Lee lo pendiente, clasifícalo (§4) y corrige lo que toque. Solo entonces manda el encargo nuevo.
- **El encargo nuevo cita sus rectificaciones.** Para cada hallazgo suyo ya corregido, di qué se cambió y cómo comprobarlo, y después lo nuevo que hay que probar. Así la revalidación cierra los hallazgos uno a uno y no se convierte en otra ronda genérica.

