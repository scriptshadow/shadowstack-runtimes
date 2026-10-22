#!/usr/bin/env bash
# Compilation locale, à la place d'une CI distante (aucun GitHub Actions tant que le PO ne l'a pas
# décidé) : même enchaînement que les anciens workflows, sur le Mac.
#
#   ./scripts/ci-local.sh php        dépendances (en cache local), PHP, Xdebug, tests, paquet
#   ./scripts/ci-local.sh mariadb    OpenSSL 3.5, MariaDB, tests, paquet
#   ./scripts/ci-local.sh tout       les deux
#
# Les paquets et leur .sha256 sont dans sortie/. La publication est une étape séparée et manuelle :
#   ./scripts/publier.sh <tag> "<titre>"

source "$(dirname "$0")/commun.sh"

ESPACE_MINIMUM_GO=10
debut=$(date +%s)

verifier_outils() {
  local manquants=() outil
  for outil in cmake pkgconf autoconf make perl curl shasum otool; do
    command -v "$outil" >/dev/null 2>&1 || manquants+=("$outil")
  done
  [ -x "$(brew --prefix bison 2>/dev/null)/bin/bison" ] || manquants+=("bison (Homebrew)")
  [ ${#manquants[@]} -eq 0 ] || echec "Outils de compilation absents : ${manquants[*]} (brew install cmake pkgconf autoconf bison)"
  echo "Outils de compilation présents"
}

verifier_espace() {
  local libre
  libre=$(df -g "$RACINE" | awk 'NR == 2 { print $4 }')
  [ "$libre" -ge "$ESPACE_MINIMUM_GO" ] || echec "Espace disque insuffisant : ${libre} Go libres, ${ESPACE_MINIMUM_GO} Go nécessaires"
  echo "Espace disque : ${libre} Go libres"
}

# Cache local des dépendances de PHP : même clé que l'ancien workflow (dependances.sh + commun.sh)
dependances_php() {
  local deps="$TRAVAIL/deps-php" cle
  cle=$(cat "$RACINE/php/dependances.sh" "$RACINE/scripts/commun.sh" | shasum -a 256 | awk '{print $1}')
  if [ -f "$deps/.cle-cache" ] && [ "$(cat "$deps/.cle-cache")" = "$cle" ]; then
    echo "Dépendances de PHP : cache local à jour"
    return
  fi
  rm -rf "${deps:?}"
  "$RACINE/php/dependances.sh"
  printf '%s\n' "$cle" > "$deps/.cle-cache"
}

# Sources extraites et paquets intermédiaires : supprimés après chaque compilation réussie
nettoyer() {
  rm -rf "${TRAVAIL:?}/src-$1" "${TRAVAIL:?}/src-deps-$1" "${TRAVAIL:?}/paquets" "${TRAVAIL:?}/deplace"
  echo "Fichiers intermédiaires supprimés (cache des dépendances et téléchargements conservés)"
}

construire_php() {
  etape "PHP : dépendances"
  dependances_php
  "$RACINE/php/construire.sh"
  nettoyer php
}

construire_mariadb() {
  "$RACINE/mariadb/construire.sh"
  nettoyer mariadb
}

case "${1:-}" in
  php | mariadb | tout) ;;
  *)
    echo "Usage : ./scripts/ci-local.sh php|mariadb|tout" >&2
    exit 2
    ;;
esac

etape "Vérifications préalables"
verifier_outils
verifier_espace

case "$1" in
  php) construire_php ;;
  mariadb) construire_mariadb ;;
  tout)
    construire_php
    construire_mariadb
    ;;
esac

etape "Résultat"
ls -lh "$SORTIE"
printf '\n\033[32m✔ ci-local %s OK (%s min)\033[0m\n' "$1" "$((($(date +%s) - debut) / 60))"
