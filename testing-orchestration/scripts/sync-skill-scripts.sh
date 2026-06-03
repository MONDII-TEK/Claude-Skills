#!/bin/bash
# Pre-commit hook que previene drift entre scripts/ del repo y la copia de la skill.
# Si scripts/<X> cambió en el commit y skills/testing-orchestration/scripts/<X> no
# se actualizó, el commit falla con instrucciones de remedio.
#
# Instalación (en el repo destino):
#   ln -sf "$(pwd)/skills/testing-orchestration/scripts/sync-skill-scripts.sh" \
#          .git/hooks/pre-commit
#   chmod +x .git/hooks/pre-commit
#
# Adaptación al proyecto destino:
#   Si tu proyecto añade orquestadores con nombres distintos (ej. compose.sh,
#   dev.sh, devbox.sh) o renombra los existentes, AMPLIA el regex de WATCHED_SCRIPTS
#   abajo para que el hook detecte drift en esos archivos también.

set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
SKILL_SCRIPTS_DIR="$REPO_ROOT/skills/testing-orchestration/scripts"
REPO_SCRIPTS_DIR="$REPO_ROOT/scripts"

[ ! -d "$SKILL_SCRIPTS_DIR" ] && exit 0  # skill no instalada, no aplicar

# Lista de scripts watched: ampliar al adoptar la skill en otro proyecto
# (añadir nombres separados por |, sin extensión: ej. "mt|compose|dev")
# NOTA: `manage` NO se watchea — la skill ya NO bundlea su propia copia de manage.sh
# (era ~280KB y derivaba constantemente). La skill referencia el `./scripts/manage.sh`
# del proyecto directamente en sus docs. No re-añadir `manage` aquí.
WATCHED_SCRIPTS="${WATCHED_SCRIPTS:-mt|stripe_heavy_collect|validate_migrations}"

CHANGED_REPO_SCRIPTS=$(git diff --cached --name-only --diff-filter=AM | \
  grep -E "^scripts/($WATCHED_SCRIPTS)\.(sh|py)$" || true)

[ -z "$CHANGED_REPO_SCRIPTS" ] && exit 0  # ningún script tracked en este commit

DIVERGENCE=""
for script_path in $CHANGED_REPO_SCRIPTS; do
    script_name="${script_path##*/}"
    skill_copy="$SKILL_SCRIPTS_DIR/$script_name"

    if [ ! -f "$skill_copy" ]; then
        DIVERGENCE+="MISSING in skill: $skill_copy\n"
        continue
    fi

    # Comparar el archivo staged (no working tree) con la copia de la skill
    STAGED_HASH=$(git show ":$script_path" | sha256sum | cut -d' ' -f1)
    SKILL_HASH=$(sha256sum "$skill_copy" | cut -d' ' -f1)

    if [ "$STAGED_HASH" != "$SKILL_HASH" ]; then
        DIVERGENCE+="DIVERGE: $script_path != $skill_copy\n"
    fi
done

if [ -n "$DIVERGENCE" ]; then
    echo "============================================================"
    echo "ERROR pre-commit: skill scripts no sincronizados"
    echo "============================================================"
    echo -e "$DIVERGENCE"
    echo "Remediar:"
    for script_path in $CHANGED_REPO_SCRIPTS; do
        script_name="${script_path##*/}"
        echo "  cp $script_path $SKILL_SCRIPTS_DIR/$script_name"
    done
    echo "  git add $SKILL_SCRIPTS_DIR/"
    echo "  git commit  # reintenta"
    echo ""
    echo "(O bypass temporal con --no-verify si sabes lo que haces.)"
    echo "============================================================"
    exit 1
fi

exit 0
