# Claude-Skills

Catálogo de skills [Claude Code](https://claude.com/claude-code) mantenido por **MONDII-TEK**. Cada subdirectorio es una skill independiente, instalable en cualquier proyecto consumidor.

## Skills disponibles

| Skill | Descripción | Stack objetivo |
|---|---|---|
| [`testing-orchestration/`](./testing-orchestration) | Orquesta ciclo de testing Python/Flask + Docker, guardian de plan→test→fix→regression para features y fixes. Cubre unit/API/bg/Stripe, reset+rebuild de stacks, test→fix→re-run loop, manual test orchestration, migration ID validation, i18n coherence checking. | Python/Flask + Docker |

> Fuente original: [IronVolt](https://github.com/MONDII-TEK/IronVolt) — proyecto de referencia donde nació la skill. La skill está diseñada **agnóstica al proyecto**: las variables de adopción (`{{backend_path}}`, `{{frontend_path}}`, etc.) se resuelven al instalar leyendo el `CLAUDE.md` del proyecto destino.

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
