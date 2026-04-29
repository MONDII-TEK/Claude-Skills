# Claude-Skills

Catálogo de skills [Claude Code](https://claude.com/claude-code) mantenido por **MONDII-TEK**. Cada subdirectorio es una skill independiente, instalable en cualquier proyecto consumidor.

## Skills disponibles

| Skill | Descripción | Stack objetivo |
|---|---|---|
| [`testing-orchestration/`](./testing-orchestration) | Orquesta ciclo de testing Python/Flask + Docker, guardian de plan→test→fix→regression para features y fixes. Cubre unit/API/bg/Stripe, reset+rebuild de stacks, test→fix→re-run loop, manual test orchestration, migration ID validation, i18n coherence checking. | Python/Flask + Docker |

> Fuente original: [IronVolt](https://github.com/MONDII-TEK/IronVolt) — proyecto de referencia donde nació la skill. La skill está diseñada **agnóstica al proyecto**: las variables de adopción (`{{backend_path}}`, `{{frontend_path}}`, etc.) se resuelven al instalar leyendo el `CLAUDE.md` del proyecto destino.

---

## `testing-orchestration` — referencia rápida

### Comandos de activación (slash explícitos)

Determinista — el usuario teclea el slash:

| Comando | Workflow | Args | Para qué sirve |
|---|---|---|---|
| `/testing-orchestration` | — | sin args | Carga la skill manualmente |
| `/testing-orchestration design <título>` | **G** plan-guardian | título freeform | Diseñar plan de test antes de empezar feature/fix (Service→Unit→Route→Integration→Build+RUN→Frontend→i18n→Manual→Docs) |
| `/testing-orchestration run <test:cmd>` | **C** run + audit | comando `manage.sh` con flags | Ejecutar `test:unit / test:module / test:api / test:bg / test:stripe / test:full` y auditar el run dir generado |
| `/testing-orchestration restart-dev` | **A** restart dev | sin args | `down → build prod/dev/test → up:dev` (ciclo de rebuild completo) |
| `/testing-orchestration restart-test` | **B** restart test | sin args | Bajar test stack zombi y rebuild de la imagen test (pre-req limpio para `test:*`) |
| `/testing-orchestration affected` | **E** detect afectados | sin args (lee `git diff`) | Identificar qué tests cubren el cambio actual y proponer `test:module` mínimo |
| `/testing-orchestration manual <feature>` | **F** manual UI | nombre del flujo | Orquestar test manual desde la perspectiva del usuario en navegador |
| `/testing-orchestration audit <run-dir>` | Audit standalone | path al run dir | Auditar `logs/test_runs/<ts>_<label>/` post-run (summary, errors, flaky markers) |
| `/testing-orchestration validate-migrations` | **H** validate migrations | sin args | Validar Alembic (IDs duplicados, branches no intencionados, orphan `down_revision`) |
| `/testing-orchestration status` | **I** sprint status | sin args | Reporte ejecutivo: últimos runs, bugs activos/cerrados, markers vivos, drift scripts↔skill |
| `/testing-orchestration self-check` | **K** self-check | sin args | Verificar adopción de la skill al proyecto destino (CLAUDE.md, docker stack, env vars) |

### Auto-trigger (modelo decide — sin teclear)

Frases típicas que activan la skill por **description match**:

| Trigger phrase | Workflow probable |
|---|---|
| "voy a añadir feature" / "diseñar plan" | G — plan-guardian |
| "test:module …" / "test:stripe …" / "test:full" / "test:bg" / "test:unit" | C — run + audit |
| "down y rebuild" / "rebuild test image" | A o B (restart) |
| "qué tests cubren …" / "regression check" | E — detect afectados |
| "manual test from user perspective" | F — manual UI |
| "fix and re-run" | D — test → fix → re-run loop |
| "valida migraciones" | H — validate migrations |
| "report status" | I — sprint status |
| "actualiza i18n" / "i18n missing locale" / "añade traducción" | J — i18n coherence |
| `manage.sh` / `mt.sh` mencionado | C / D según contexto |

### Workflows (resumen)

| Letra | Nombre | Cuándo se activa | Resultado |
|---|---|---|---|
| **G** | Plan-guardian | Antes de empezar feature/fix | Plantilla de plan + checklist de capas a cubrir |
| **A** | Restart dev | "down y rebuild de todo" | Stack dev limpio en `up:dev` |
| **B** | Restart test stack | Antes de un `test:*` con zombi suspect | Test stack limpio, imagen test fresh |
| **C** | Run + audit | Cualquier `test:*` invocado | Ejecuta + audita run dir + reporta markers |
| **D** | Test → fix → re-run | Test rojo + fix aplicado | Loop sequencial hasta verde sin regresiones |
| **E** | Detect afectados | Hay cambios staged/unstaged | Lista mínima de `test:*` que cubre el cambio |
| **F** | Manual UI test | Feature user-facing nueva | Checklist navegador + golden path + edge cases |
| **H** | Validate migrations | Antes de commit con nueva migración | Pasa/falla con dups, branches, orphans |
| **I** | Sprint status | Reporte periódico | Snapshot ejecutivo de runs/bugs/markers |
| **J** | i18n coherence | Cambio de strings UI | Verifica 4 locales sincronizados (es/en/fr/it) |
| **K** | Self-check adopción | Tras instalar skill en otro repo | Reporta gaps de adopción (CLAUDE.md, env, paths) |

### Scripts incluidos (`testing-orchestration/scripts/`)

| Script | Lenguaje | Para qué sirve |
|---|---|---|
| [`manage.sh`](./testing-orchestration/scripts/manage.sh) | bash | Copia de referencia del orquestador del proyecto fuente. Se usa como **espejo** para detectar drift contra `<proyecto>/scripts/manage.sh` (ver `sync-skill-scripts.sh`). No se ejecuta directamente por la skill. |
| [`mt.sh`](./testing-orchestration/scripts/mt.sh) | bash | Copia de referencia del helper `mt.sh` (manual test middleware con env: `BASE_URL`, `ADMIN_TOKEN`, `STRIPE_KEY`, restore membership, reset credits, force token refresh). Mismo rol: detectar drift. |
| [`stripe_heavy_collect.py`](./testing-orchestration/scripts/stripe_heavy_collect.py) | python | Colecciona class-level nodeids para pytest 9+ (que cambió formato `--collect-only -q` de flat a tree). Lo usa el corredor de stripe_heavy para invocar pytest con isolación class-by-class. |
| [`sync-skill-scripts.sh`](./testing-orchestration/scripts/sync-skill-scripts.sh) | bash | Pre-commit hook que falla el commit si `scripts/<X>` cambió pero `skills/testing-orchestration/scripts/<X>` no. Previene drift entre orquestador del repo y la copia de la skill. Adaptable vía `WATCHED_SCRIPTS` env var. |
| [`validate_migrations.sh`](./testing-orchestration/scripts/validate_migrations.sh) | bash | Validador de Alembic: detecta IDs de revisión duplicados, branches no intencionados (multiple migraciones con mismo parent), y orphan `down_revision` references. Parametrizable vía `MIGRATIONS_DIR`. Invocado por workflow H. |

### Documentación detallada (dentro de la skill)

| Archivo | Contenido |
|---|---|
| [`SKILL.md`](./testing-orchestration/SKILL.md) | Entry point + adopción al proyecto + invariants + triggers |
| [`workflows.md`](./testing-orchestration/workflows.md) | Detalle paso a paso de cada workflow A-K |
| [`commands-reference.md`](./testing-orchestration/commands-reference.md) | Referencia exhaustiva de slash commands + ejemplos |
| [`policies.md`](./testing-orchestration/policies.md) | Markers (`xfail`/`xpass`/`stripe_heavy`/`bg_heavy`), políticas de retry, exclusión |
| [`stripe-integration.md`](./testing-orchestration/stripe-integration.md) | Patrones específicos para tests Stripe (sidecar, test_clocks, webhooks) |
| [`manual-testing.md`](./testing-orchestration/manual-testing.md) | Guía operativa de tests manuales (workflow F) |
| [`plan-template.md`](./testing-orchestration/plan-template.md) | Plantilla de plan-guardian (workflow G) |
| [`bug-tracker-template.md`](./testing-orchestration/bug-tracker-template.md) | Esquema de `051_bug_tracker.md` (activo) + `_history.md` (cerrado) |
| [`audit.md`](./testing-orchestration/audit.md) | Patrón de auditoría post-run (workflow C/D/F) |

---

## Instalación en un proyecto consumidor

Hay tres rutas. Elige según cómo quieras gestionar la dependencia:

### Opción A — Submodule (recomendada)

Pin del SHA exacto en el repo consumidor. Cambios en la skill no afectan al consumidor hasta que éste haga bump explícito. Útil cuando la skill evoluciona y quieres versionado controlado.

```bash
# Una sola vez, en el proyecto consumidor:
git submodule add https://github.com/MONDII-TEK/Claude-Skills.git skills
git commit -m "chore: add Claude-Skills submodule"

# Para que Claude Code la descubra (auto-discovery):
# El proyecto debe tener (o añadir) un comando que copie skills/<name>/
# a .claude/skills/<name>/. En IronVolt eso es:
./scripts/manage.sh install:skill testing-orchestration
```

> **Por qué copia y no symlink**: algunos runtimes que indexan `.claude/skills/` con `find -L` o `realpath` no resuelven symlinks de forma fiable durante cold-start. La copia es portable, runtime-friendly y permite distribuir `.claude/skills/` standalone.

#### Clones nuevos del repo consumidor

```bash
git clone --recursive <consumer-repo-url>
# o si ya clonaste sin --recursive:
git submodule update --init --recursive
```

#### Adoptar una nueva versión publicada en `main`

```bash
git submodule update --remote skills
git add skills
git commit -m "chore(skill): bump testing-orchestration to <new-SHA>"
./scripts/manage.sh install:skill testing-orchestration --force
```

### Opción B — Clone standalone fuera del proyecto

Si no quieres acoplar git a la skill o usas la skill en múltiples proyectos sin versionarla por proyecto:

```bash
# Clona en cualquier lugar, p.ej. ~/skills-cache/
git clone https://github.com/MONDII-TEK/Claude-Skills.git ~/skills-cache/claude-skills

# Copia la skill al proyecto destino:
cp -R ~/skills-cache/claude-skills/testing-orchestration/ \
      <project-root>/.claude/skills/testing-orchestration/
```

Pros: cero acoplamiento. Contras: sincronización manual; nadie te avisa si la upstream cambia.

### Opción C — Copia directa (one-shot)

Para experimentar o llevarte la skill a un proyecto que nunca volverá a actualizarse:

```bash
# Descarga el tarball del repo y extrae solo la skill:
curl -sSL https://github.com/MONDII-TEK/Claude-Skills/archive/refs/heads/main.tar.gz \
  | tar -xz --strip-components=1 -C <project-root>/.claude/skills/ \
        Claude-Skills-main/testing-orchestration
```

Sin git, sin historia, sin updates. La opción más rápida pero la menos mantenible.

## Convenciones

- **Cada skill = un subdirectorio** con `SKILL.md` en su raíz (formato Claude Code: frontmatter `name` + `description`).
- **Documentación cruzada** dentro de la skill: `workflows.md`, `commands-reference.md`, `policies.md`, `manual-testing.md`, etc.
- **Scripts** que la skill provee viven en `<skill>/scripts/` y son sincronizables al proyecto consumidor según las instrucciones de cada skill.
- **Nombres de skill**: lowercase + hyphens, deben empezar por letra. Validado por `cmd_install_skill` en proyectos consumidores que reusen el patrón de IronVolt.

## Workflow para colaborar en la skill desde un consumidor

Cuando trabajas en un proyecto que tiene Claude-Skills como submodule y quieres editar la skill:

```bash
cd skills                              # entras al submodule
git checkout main                      # asegúrate de estar en main
# ...edita SKILL.md, workflows.md, etc.
git add .
git commit -m "feat(skill): X"
git push origin main                   # publica en Claude-Skills
cd ..
git add skills                         # actualiza el pin en el consumidor
git commit -m "chore(skill): bump to <new-SHA>"
./scripts/manage.sh install:skill <skill-name> --force   # refresca .claude/skills/
```

## Estado y compatibilidad

- **Repo público y reutilizable**: el contenido es agnóstico. Resolver placeholders de adopción (`{{backend_path}}`, etc.) leyendo `CLAUDE.md` del proyecto destino — ver `testing-orchestration/SKILL.md` §"Adopción al proyecto" para el listado completo de variables.
- **Sin breaking changes en `main` sin tag**: cuando una skill cambie de forma incompatible, se etiquetará con `vX.Y.Z`. Consumidores con submodule pueden pinear a un tag (`git submodule update --remote --depth 1` + checkout del tag dentro del submodule).

## Licencia

Ver [LICENSE](./LICENSE) (a definir — heredada de IronVolt si aplica).

---

Mantenido por [MONDII-TEK](https://github.com/MONDII-TEK).
