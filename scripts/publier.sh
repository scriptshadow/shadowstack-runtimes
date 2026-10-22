#!/usr/bin/env bash
# Publie le paquet <tag> de sortie/ (ex. php-7.4.33 → php-7.4.33-<cible>.tar.gz et son .sha256)
# dans la release GitHub <tag> : créée si besoin, fichiers remplacés sinon. Envoi de fichiers
# seulement : aucune exécution GitHub Actions.
#
#   ./scripts/publier.sh <tag> "<titre>"

set -euo pipefail

tag="$1"
titre="$2"
cd "$(dirname "$0")/.."

fichiers=(sortie/"$tag"-*.tar.gz sortie/"$tag"-*.tar.gz.sha256)
for f in "${fichiers[@]}"; do
  [ -f "$f" ] || { echo "✖ Paquet absent pour $tag dans sortie/ : lancer d'abord ./scripts/ci-local.sh" >&2; exit 1; }
done
# Empreinte revérifiée juste avant l'envoi
(cd sortie && shasum -a 256 -c "$(basename "${fichiers[1]}")")

if gh release view "$tag" >/dev/null 2>&1; then
  gh release upload "$tag" "${fichiers[@]}" --clobber
else
  gh release create "$tag" "${fichiers[@]}" --title "$titre" --target main \
    --notes "Compilé en local sur macOS arm64 (scripts/ci-local.sh), depuis le commit $(git rev-parse --short HEAD). Sources et empreintes : sources.txt. Vérification après téléchargement : shasum -a 256 -c $(basename "${fichiers[1]}")"
fi
