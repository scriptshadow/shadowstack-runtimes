#!/usr/bin/env bash
# Compilation locale, à la place d'une CI distante (aucun GitHub Actions tant que le PO ne l'a pas
# décidé) : même enchaînement que les anciens workflows, sur le Mac.
#
#   ./scripts/ci-local.sh php [7.4|8.3] [--complet]   dépendances, PHP, Xdebug, tests, paquet (7.4 par défaut)
#   ./scripts/ci-local.sh mariadb [--complet]   OpenSSL 3.5, MariaDB, tests, paquet
#   ./scripts/ci-local.sh mysql                 MySQL officiel vérifié, testé et redistribué tel quel
#   ./scripts/ci-local.sh nginx [--complet]     Nginx (PCRE2, zlib), tests, paquet
#   ./scripts/ci-local.sh tout [--complet]      les deux
#   ./scripts/ci-local.sh nettoyer              libère l'espace (caches et arbres de compilation)
#
# Reprise automatique : une étape dont rien n'a changé (sources, recette, options) n'est pas
# refaite, et ccache garde les fichiers déjà compilés. --complet force toutes les étapes.
# Les paquets et leur .sha256 sont dans sortie/. La publication est une étape séparée et manuelle :
#   ./scripts/publier.sh <tag> "<titre>"

source "$(dirname "$0")/commun.sh"

ESPACE_MINIMUM_GO=10
debut=$(date +%s)

usage() {
  echo "Usage : ./scripts/ci-local.sh php [7.4|8.3]|mariadb|mysql|nginx|tout [--complet]" >&2
  echo "        ./scripts/ci-local.sh nettoyer" >&2
  exit 2
}

verifier_outils() {
  local manquants=() outil
  for outil in cmake pkgconf autoconf make perl curl shasum otool install_name_tool codesign; do
    command -v "$outil" >/dev/null 2>&1 || manquants+=("$outil")
  done
  [ -x "$(brew --prefix bison 2>/dev/null)/bin/bison" ] || manquants+=("bison (Homebrew)")
  [ ${#manquants[@]} -eq 0 ] || echec "Outils de compilation absents : ${manquants[*]} (brew install cmake pkgconf autoconf bison ccache)"
  if command -v ccache >/dev/null 2>&1; then
    echo "Outils de compilation présents, ccache actif ($CCACHE_DIR, ${CCACHE_MAXSIZE} au plus)"
  else
    echo "Outils de compilation présents ; ccache absent, compilation sans cache (brew install ccache)"
  fi
}

verifier_espace() {
  local libre
  libre=$(df -g "$RACINE" | awk 'NR == 2 { print $4 }')
  [ "$libre" -ge "$ESPACE_MINIMUM_GO" ] || echec "Espace disque insuffisant : ${libre} Go libres, ${ESPACE_MINIMUM_GO} Go nécessaires (./scripts/ci-local.sh nettoyer libère les caches)"
  echo "Espace disque : ${libre} Go libres"
}

# Copies de travail du paquet : refaites à chaque exécution, inutiles ensuite
nettoyer_copies() {
  rm -rf "${TRAVAIL:?}/paquets" "${TRAVAIL:?}/deplace"
}

# Libère tout l'espace : arbres de compilation, installations, dépendances, cache ccache.
# Les archives téléchargées (vérifiées par SHA-256) et les paquets de sortie/ sont gardés.
nettoyer_tout() {
  local avant
  avant=$(du -sh "$TRAVAIL" 2>/dev/null | awk '{print $1}')
  rm -rf "${TRAVAIL:?}"/src-* "${TRAVAIL:?}"/deps-* "${TRAVAIL:?}/installation" "${TRAVAIL:?}/paquets" \
    "${TRAVAIL:?}/deplace" "${TRAVAIL:?}/ccache" "${TRAVAIL:?}/ccache-bin" "${TRAVAIL:?}/outils"
  echo "Espace libéré (travail/ : ${avant:-0} → $(du -sh "$TRAVAIL" | awk '{print $1}')). Archives téléchargées et sortie/ conservées."
}

construire_php() {
  "$RACINE/php/dependances.sh"
  "$RACINE/php/construire.sh"
  nettoyer_copies
}

construire_mariadb() {
  "$RACINE/mariadb/construire.sh"
  nettoyer_copies
}

cible="${1:-}"
case "$cible" in
  nettoyer)
    nettoyer_tout
    exit 0
    ;;
  php | mariadb | mysql | nginx | tout) ;;
  *) usage ;;
esac
shift
for option in "$@"; do
  case "$option" in
    --complet) export COMPLET=1 ;;
    7.4 | 8.3)
      [ "$cible" = php ] || usage
      export BRANCHE_PHP="$option"
      ;;
    *) usage ;;
  esac
done

etape "Vérifications préalables"
# MySQL n'est pas compilé : seuls curl, shasum et otool servent (outils du système)
[ "$cible" = mysql ] || verifier_outils
verifier_espace
if command -v ccache >/dev/null 2>&1; then
  ccache --zero-stats >/dev/null
fi

case "$cible" in
  php) construire_php ;;
  mariadb) construire_mariadb ;;
  mysql)
    "$RACINE/mysql/redistribuer.sh"
    nettoyer_copies
    ;;
  nginx)
    "$RACINE/nginx/construire.sh"
    nettoyer_copies
    ;;
  tout)
    construire_php
    construire_mariadb
    ;;
esac

etape "Résultat"
ls -lh "$SORTIE"
if command -v ccache >/dev/null 2>&1; then
  # Première occurrence de chaque ligne : ccache les répète par niveau de cache
  ccache --show-stats | awk '/Hits|Misses|Cache size/ && !vu[$1]++ { print "ccache : " $0 }'
fi
printf '\n\033[32m✔ ci-local %s OK (%s min)\033[0m\n' "$cible" "$((($(date +%s) - debut) / 60))"
