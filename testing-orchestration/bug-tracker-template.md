# Bug tracker — plantillas copiables

Plantillas literales que la skill `testing-orchestration` usa para mantener el bug tracker dual:

- **Workflow #26** (abrir bug) → plantilla §1 abajo, entrada se añade a `docs/analysis/051_bug_tracker.md` (activo).
- **Workflow #27** (cerrar bug) → plantilla §2 abajo, entrada se **mueve** del activo al gemelo `docs/analysis/051_bug_tracker_history.md` en el **mismo commit** que aplica el fix.

> **Nota de nomenclatura**: `#26`/`#27` son IDs heredados del catálogo de workflows del doc maestro de testing (doc 053); **no** pertenecen al esquema alfabético A-L del resto de la skill. Son, sin más, las operaciones *abrir* y *cerrar* del bug tracker dual. En un proyecto destino puedes renombrarlas: lo que importa es la operativa (abrir en el activo / mover al gemelo en el commit del fix), no el número.

> Política: el activo es **mínimo de bugs abiertos / fixing**. Sin historial. Cuando el bug pasa a estado terminal (CORREGIDO / NO ES BUG / OBSOLETO / DUPLICADO / INFRA TEST mitigado), su entrada deja el activo. Workflow #27 garantiza la atomicidad (movimiento + fix en mismo commit).

---

## §1. Plantilla — Open bug (entrada en activo `051_bug_tracker.md`)

Mantener mínima: lo justo para reproducir y diagnosticar. Detalles extensos (timelines, evidence dumps, post-mortems) van al gemelo cuando se cierre.

```markdown
### BUG-NNN: <título corto del síntoma observable>

**Severidad**: Crítica / Alta / Media / Baja
**Estado**: open / fixing
**Detectado por**: <test que lo cazó / auditoría / report del usuario / manual UI test>
**Archivo**: `<path>:<línea>` (ubicación del bug en producción)
**Tests que cubren**: `<TestClase::test_method>` (PASA / FAILED / xfail si ya existe)

**Descripción**: <síntoma + comportamiento esperado vs observado en 2-4 líneas>

**Causa raíz** (si confirmada): <root cause + cómo se reprodujo>

**Fix propuesto** (si analizado): <esbozo en 2-3 líneas>
```

**Reglas**:
- ID `BUG-NNN` incremental, **nunca reutilizar**. Próximo ID disponible: ver `051_bug_tracker.md` §Numeración.
- IDs descartados / NO-BUG van al gemelo bajo prefijo `NOBUG-NNN` propio (numeración independiente).
- Severidad: Crítica > Alta > Media > Baja (criterios en `051_bug_tracker.md` §Convenciones).
- Si el fix se aplica en el mismo sprint que se descubre: la entrada nunca pasa por el activo — va directamente al gemelo con estado terminal (workflow #27 directo).

---

## §2. Plantilla — Closed bug (mover al gemelo `051_bug_tracker_history.md`)

Cuando un bug se cierra, su entrada **se reescribe** con esta plantilla más rica antes de moverla al gemelo. Mantener la causa raíz, evidencia, fix aplicado y lecciones para post-mortems.

```markdown
### BUG-NNN
**Título**: <título corto> — <ESTADO_TERMINAL>
**Severidad**: <Crítica / Alta / Media / Baja>
**Estado**: **CORREGIDO** (YYYY-MM-DD) / **NO ES BUG** / **OBSOLETO** / **DUPLICADO** / **INFRA TEST mitigado**
**Cerrado**: YYYY-MM-DD
**PR/commit**: `<hash>` o `#<PR>` (para `git log -p -S "BUG-NNN"`)
**Detectado por**: <origen del descubrimiento>
**Archivo**: `<path>:<línea>` (ubicación del bug en producción)
**Tests que cubren**: `<TestClase::test_method>` (PASA tras fix)

**Descripción**: <síntoma + comportamiento esperado vs observado>

**Causa raíz**: <root cause confirmado + cómo se reprodujo>

**Evidencia** (opcional pero recomendado para Severidad Crítica/Alta):
- Timeline observado: <bloque code con timestamps + eventos>
- Logs relevantes: `<run dir>/<archivo>:<línea>` con extract de 3-5 líneas
- Stripe / external state: `<estado API que se observó>`

**Fix aplicado**: <descripción del cambio + path archivo + bloque code 3-10 líneas si aplica>

**Lección** (opcional pero recomendado): <aprendizaje para futuros bugs similares — útil para post-mortems y para alimentar reglas de doc 053 si surge un anti-patrón nuevo>

**Relación con otros bugs** (si aplica): <BUG-MMM absorbido / BUG-PPP duplicado funcional / mismo root cause que BUG-XXX>

**Follow-up no aplicado** (si aplica): <mejora pendiente que no entra en el fix mínimo del cierre — registrar en activo §"Trabajo futuro identificado">
```

**Reglas**:
- **Mismo commit que fix (operación cohesiva, no transaccional)**: el move (eliminar del activo + añadir al gemelo) y el fix de producción + tests de regresión + actualización de xfail viven en **un único commit**. La atomicidad la delega git, no el filesystem (Edit + Edit son operaciones distintas; solo el commit las une). Si el agente falla entre Edit 1 y Edit 2, hay duplicación temporal — el git status lo evidencia y se reconstituye antes del commit. Esto preserva el invariante "el bug aparece exactamente una vez al revisar git history" + `git log -- docs/analysis/051_bug_tracker_history.md` da timeline de cierres.
- **Sin duplicación**: el bug nunca aparece simultáneamente en ambos archivos. Si reabre, mover de vuelta al activo (operación inversa, mismo patrón).
- **Conservar evidencia**: bloques de código, logs, timelines y referencias cruzadas se preservan. El gemelo es append-only y archivo de auditoría — no se trunca por brevedad.
- **Sub-índice por dominio**: en cada migración o cada N entradas, revisar el §"Índice por dominio" del gemelo para reagrupar (Stripe webhooks, membership lifecycle, RBAC, ecommerce, etc.).

---

## §3. Plantilla — NO-BUG (descartado tras análisis)

Cuando un comportamiento observado se confirma como **diseño correcto** (no bug), se documenta como `NOBUG-NNN` en el gemelo bajo §"Bugs descartados (No-Bug)". No vive nunca en el activo.

```markdown
### NOBUG-NNN
**Título**: <síntoma observado que parecía bug>
**Detectado por**: <test / observación que lo levantó>
**Causa real**: <comportamiento by design + ubicación del código que lo implementa>
**Conclusión**: <por qué NO es bug + referencia a la regla de negocio o documentación que lo justifica>
```

**Numeración independiente**: NOBUG-001, NOBUG-002, ... — no comparten secuencia con BUG-NNN.

---

## §4. Operación — workflow #26 (abrir bug)

Pasos que la skill ejecuta cuando dispara workflow #26 (frase `"abrir bug X"` o detección automática de fallo no transitorio):

1. **Leer + asignar ID en una sola operación atómica del Edit**: leer `051_bug_tracker.md` §Numeración para obtener próximo BUG-NNN, e incrementarlo en el mismo Edit que añade la entrada (en lugar de dos Edits separados). Esto evita race conditions en sesiones concurrentes (poco probable en práctica pero correcto).
2. **Rellenar §1 plantilla** con:
   - Título corto del síntoma.
   - Severidad estimada.
   - Estado: `open`.
   - Detectado por: contexto de invocación (test que falló, manual UI report, etc.).
   - Archivo + tests que cubren si están disponibles.
   - Descripción mínima (2-4 líneas).
3. **Añadir** al activo bajo §"Bugs abiertos / fixing", con §Numeración incrementada en el mismo Edit.
4. **Reportar** al usuario el ID asignado + ubicación.

---

## §5. Operación — workflow #27 (cerrar bug + mover a gemelo)

Pasos que la skill ejecuta cuando dispara workflow #27 (frase `"cerrar bug Y"`, fix mergeado detectado):

1. **Localizar** entrada en activo: grep por `BUG-NNN`.
2. **Reescribir** con §2 plantilla (más rica), incluyendo:
   - Estado terminal + fecha cierre + PR/commit hash.
   - Causa raíz confirmada.
   - Evidencia (timeline, logs).
   - Fix aplicado (descripción + path + code).
   - Lección si aplica.
3. **Añadir** al gemelo bajo la sub-sección apropiada del §Índice por dominio.
4. **Eliminar** la entrada original del activo.
5. **Actualizar** §"Resumen tabla — Bugs cerrados Ronda <N>" del gemelo con la nueva fila.
6. **Verificar** integridad: el bug aparece **exactamente una vez** en uno de los dos archivos.
7. **Confirmar** al usuario que el commit que aplica esto debe incluir: el fix de producción + tests + actualización de xfail (si tenía) + estos cambios en bug tracker — **todo atómico**.

---

## §6. Operación — reabrir bug (caso raro)

Si un bug previamente cerrado reaparece (regresión, fix incompleto, comportamiento que vuelve):

1. Localizar entrada en gemelo.
2. Eliminarla del gemelo.
3. Crear nueva entrada en activo con §1 plantilla, **mismo ID original** (`BUG-NNN`) pero estado nuevo:
   - Estado: `open` o `fixing`.
   - Descripción: incluir referencia *"Reapertura de BUG-NNN cerrado YYYY-MM-DD; ver gemelo (commit `<hash>`) para historia previa."*
4. Cuando se vuelva a cerrar, mover de nuevo al gemelo con plantilla §2 incluyendo **dos secciones de cierre** (cierre original + cierre actual) para no perder traza.

**Frecuencia esperada**: muy baja. Si ocurre, es señal de fix incompleto en su momento → lección para post-mortem.

---

## §7. Verificación de integridad (run periódico de la skill)

Workflow I (`/testing-orchestration status`) ejecuta entre otras comprobaciones:

```bash
# Conteo de bugs por archivo
grep -cE "^### BUG-" docs/analysis/051_bug_tracker.md
grep -cE "^### BUG-" docs/analysis/051_bug_tracker_history.md
grep -cE "^### NOBUG-" docs/analysis/051_bug_tracker_history.md

# IDs duplicados (alerta si hay)
{ grep -oE "BUG-[0-9]+" docs/analysis/051_bug_tracker.md;
  grep -oE "BUG-[0-9]+" docs/analysis/051_bug_tracker_history.md; } | \
  sort | uniq -d
# Output esperado: vacío. Si hay líneas → mismo ID en ambos archivos = anomalía.

# Coherencia de numeración (próximo ID anunciado en activo §Numeración)
grep -oE "Próximo ID disponible: \*\*BUG-[0-9]+\*\*" docs/analysis/051_bug_tracker.md

# Bugs activos sin estado open/fixing (anomalía)
awk '/^### BUG-/{title=$0} /^\*\*Estado\*\*:/{if (!/(open|fixing)/) print title": "$0}' \
  docs/analysis/051_bug_tracker.md
# Output esperado: vacío. Si hay líneas → entrada con estado terminal en activo (no se movió).
```

Si alguna comprobación falla, la skill reporta como `[DISCREPANCIA]` en el output del workflow I y propone reparación.
