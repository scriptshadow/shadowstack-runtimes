#!/usr/bin/env bash
# Publie les paquets de sortie/ dans la release GitHub <tag> (créée si besoin, fichiers remplacés sinon).
#
#   ./scripts/publier.sh <tag> "<titre>"

set -euo pipefail

tag="$1"
titre="$2"
cd "$(dirname "$0")/.."

fichiers=(sortie/*.tar.gz sortie/*.sha256)
[ -e "${fichiers[0]}" ] || { echo "✖ Aucun paquet dans sortie/" >&2; exit 1; }

if gh release view "$tag" >/dev/null 2>&1; then
  gh release upload "$tag" "${fichiers[@]}" --clobber
else
  gh release create "$tag" "${fichiers[@]}" --title "$titre" \
    --notes "Compilé par GitHub Actions depuis le commit $(git rev-parse --short HEAD). Sources et empreintes : sources.txt."
fi
