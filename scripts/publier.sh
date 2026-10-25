#!/usr/bin/env bash
# Publie les paquets <tag> de sortie/ (ex. php-7.4.33 → php-7.4.33-<cible>.tar.gz, ou
# mysql-8.4.13 → ses archives officielles .tar.gz et .zip) et leur .sha256 dans la release
# GitHub <tag> : créée si besoin, fichiers remplacés sinon. Envoi de fichiers seulement :
# aucune exécution GitHub Actions.
#
#   ./scripts/publier.sh <tag> "<titre>" ["<notes>"]

set -euo pipefail

tag="$1"
titre="$2"
notes="${3:-}"
cd "$(dirname "$0")/.."

archives=()
for f in sortie/"$tag"-*.tar.gz sortie/"$tag"-*.zip; do
  [ -f "$f" ] && archives+=("$f")
done
[ ${#archives[@]} -gt 0 ] || { echo "✖ Paquet absent pour $tag dans sortie/ : lancer d'abord ./scripts/ci-local.sh" >&2; exit 1; }

fichiers=()
for f in "${archives[@]}"; do
  [ -f "$f.sha256" ] || { echo "✖ Empreinte absente : $f.sha256" >&2; exit 1; }
  # Empreinte revérifiée juste avant l'envoi
  (cd sortie && shasum -a 256 -c "$(basename "$f").sha256")
  fichiers+=("$f" "$f.sha256")
done

if [ -z "$notes" ]; then
  notes="Compilé en local sur macOS arm64 (scripts/ci-local.sh), depuis le commit $(git rev-parse --short HEAD). Sources et empreintes : sources.txt. Vérification après téléchargement : shasum -a 256 -c <archive>.sha256"
fi

if gh release view "$tag" >/dev/null 2>&1; then
  gh release upload "$tag" "${fichiers[@]}" --clobber
else
  gh release create "$tag" "${fichiers[@]}" --title "$titre" --target main --notes "$notes"
fi
