#!/usr/bin/env bash
# Fonctions communes aux scripts de compilation (à sourcer). Compatible bash 3.2 (macOS).

set -euo pipefail
# Jamais d'arrêt muet : la commande en échec et sa ligne sont affichées (errtrace : aussi dans les fonctions)
set -o errtrace
trap 'printf "\n\033[31m✖ Échec (code %s) ligne %s de %s : %s\033[0m\n" "$?" "$LINENO" "${BASH_SOURCE[0]##*/}" "$BASH_COMMAND" >&2' ERR

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRAVAIL="${TRAVAIL:-$RACINE/travail}"
CACHE="$TRAVAIL/telechargements"
SORTIE="${SORTIE:-$RACINE/sortie}"
CIBLE="${CIBLE:-macos-arm64}"
COEURS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

# Binaires compatibles avec macOS 13 et plus
export MACOSX_DEPLOYMENT_TARGET=13.0

etape() {
  printf '\n\033[1m== %s\033[0m\n' "$*"
}

echec() {
  printf '\n\033[31m✖ %s\033[0m\n' "$*" >&2
  exit 1
}

# telecharger <fichier> : télécharge l'archive listée dans sources.txt, vérifie son SHA-256,
# et affiche son chemin local
telecharger() {
  local fichier="$1" ligne empreinte url calculee
  if ! ligne=$(grep -E "^$fichier[[:space:]]" "$RACINE/sources.txt"); then
    echec "Source inconnue dans sources.txt : $fichier"
  fi
  empreinte=$(printf '%s\n' "$ligne" | awk '{print $2}')
  url=$(printf '%s\n' "$ligne" | awk '{print $3}')
  mkdir -p "$CACHE"
  if [ ! -f "$CACHE/$fichier" ]; then
    curl -fsSL --retry 3 -o "$CACHE/$fichier.partiel" "$url" >&2 || echec "Téléchargement impossible : $url"
    mv "$CACHE/$fichier.partiel" "$CACHE/$fichier"
  fi
  calculee=$(shasum -a 256 "$CACHE/$fichier" | awk '{print $1}')
  if [ "$calculee" != "$empreinte" ]; then
    rm -f "$CACHE/$fichier"
    echec "Empreinte SHA-256 invalide pour $fichier (attendue $empreinte, obtenue $calculee)"
  fi
  printf '%s\n' "$CACHE/$fichier"
}

# extraire <fichier> <dossier parent> : extrait une archive vérifiée, affiche le dossier créé
extraire() {
  local archive dossier
  archive=$(telecharger "$1")
  mkdir -p "$2"
  # sed lit toute la liste : pas de SIGPIPE sur tar (fatal avec pipefail), contrairement à head
  dossier=$(tar -tf "$archive" | sed -n '1{s#^\./##;s#/.*##;p;}')
  rm -rf "${2:?}/$dossier"
  tar -xf "$archive" -C "$2"
  printf '%s\n' "$2/$dossier"
}

# verifier_liens <dossier> : échoue si un binaire Mach-O dépend d'autre chose que du système
# (/usr/lib, /System) ou du paquet lui-même (@rpath, @loader_path, @executable_path).
# Refuse aussi tout LC_RPATH absolu : le paquet doit fonctionner depuis n'importe quel dossier.
verifier_liens() {
  local dossier="$1" fichier fautes=0 nb=0 dep rpath identite
  while IFS= read -r fichier; do
    [[ $(file -b "$fichier") == *Mach-O* ]] || continue
    nb=$((nb + 1))
    # Le nom d'installation propre à une .dylib n'est pas une dépendance
    identite=$(otool -D "$fichier" | tail -n +2)
    while IFS= read -r dep; do
      [ "$dep" = "$identite" ] && continue
      case "$dep" in
        /usr/lib/* | /System/Library/* | @rpath/* | @loader_path/* | @executable_path/*) ;;
        *)
          echo "  ${fichier#"$dossier"/} → $dep" >&2
          fautes=$((fautes + 1))
          ;;
      esac
    done < <(otool -L "$fichier" | tail -n +2 | awk '{print $1}')
    while IFS= read -r rpath; do
      case "$rpath" in
        @*) ;;
        *)
          echo "  ${fichier#"$dossier"/} → LC_RPATH absolu $rpath" >&2
          fautes=$((fautes + 1))
          ;;
      esac
    done < <(otool -l "$fichier" | awk '/LC_RPATH/{getline; getline; print $2}')
  done < <(find "$dossier" -type f \( -perm -u+x -o -name '*.dylib' -o -name '*.so' \))
  [ "$fautes" -eq 0 ] || echec "$fautes dépendance(s) hors système dans $dossier"
  echo "Liens vérifiés : $nb binaires, dépendances limitées au système"
}

# empaqueter <dossier> : crée <nom>-<cible>.tar.gz et son .sha256 dans $SORTIE
empaqueter() {
  local dossier="$1" nom archive
  nom=$(basename "$dossier")
  archive="$nom-$CIBLE.tar.gz"
  mkdir -p "$SORTIE"
  tar -czf "$SORTIE/$archive" -C "$(dirname "$dossier")" "$nom"
  (cd "$SORTIE" && shasum -a 256 "$archive" > "$archive.sha256")
  echo "Paquet : $SORTIE/$archive ($(du -h "$SORTIE/$archive" | awk '{print $1}'))"
  cat "$SORTIE/$archive.sha256"
}
