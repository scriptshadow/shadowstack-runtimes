#!/usr/bin/env bash
# Compile PostgreSQL pour macOS arm64 (serveur, clients, modules de contrib sans dépendance externe ;
# sans ICU ni OpenSSL : ShadowStack le lance sur 127.0.0.1 seulement, avec le fournisseur de
# locale intégré), rend ses bibliothèques relatives au paquet, teste le paquet déplacé
# (initdb, démarrage, écriture et lecture d'une valeur accentuée, upper() en Unicode, arrêt
# propre), l'empaquette. Étape en cache : seule une source, une option ou la recette changée la
# refait ; le paquet (copie, vérifications, tests) est toujours refait.
#
#   ./postgresql/construire.sh

source "$(dirname "$0")/../scripts/commun.sh"

VERSION_POSTGRESQL=18.6
SRC="$TRAVAIL/src-postgresql"
INSTALLATION="$TRAVAIL/installation/postgresql-$VERSION_POSTGRESQL"
PAQUET="$TRAVAIL/paquets/postgresql-$VERSION_POSTGRESQL"

# Installation restée écartée par des tests interrompus : remise en place (évite une recompilation)
if [ -d "$INSTALLATION.ecartee" ] && [ ! -e "$INSTALLATION" ]; then
  mv "$INSTALLATION.ecartee" "$INSTALLATION"
fi

options_configure=(
  # Collations par le fournisseur intégré (C.UTF-8) : ni ICU ni locales du système
  --without-icu
  # libedit du système (/usr/lib) pour l'historique de psql ; zlib du système pour pg_dump
  --with-libedit-preferred
  # Bibliothèques reliées au paquet après coup (relier_au_paquet), jamais par un chemin absolu
  --disable-rpath
  CFLAGS="-O2 -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"
  LDFLAGS="-mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"
)

compiler_postgresql() {
  local p
  rm -rf "${SRC:?}" "$INSTALLATION"
  p=$(extraire "postgresql-$VERSION_POSTGRESQL.tar.bz2" "$SRC")
  # world-bin : serveur, clients et contrib, sans la documentation
  (cd "$p" && ./configure --prefix="$INSTALLATION" "${options_configure[@]}" &&
    make -j"$COEURS" world-bin && make install-world-bin)
}

cle_compilation=$(empreinte "$(source_de "postgresql-$VERSION_POSTGRESQL.tar.bz2")" "$(declare -f compiler_postgresql)" \
  "${options_configure[*]}" "$MACOSX_DEPLOYMENT_TARGET")
etape_en_cache "$INSTALLATION/.etape-compilation" "$cle_compilation" \
  "PostgreSQL $VERSION_POSTGRESQL : compilation (serveur, clients, contrib)" compiler_postgresql

# relier_au_paquet <paquet> <préfixe d'origine> : remplace chaque dépendance vers le préfixe
# d'origine (libpq.5.dylib, gravée en chemin absolu par make install) par un chemin relatif au
# binaire (@loader_path), puis re-signe en ad hoc
relier_au_paquet() {
  local paquet="$1" origine="$2" fichier dep cible relatif modifies=0 change
  while IFS= read -r fichier; do
    [[ $(file -b "$fichier") == *Mach-O* ]] || continue
    change=0
    if [[ "$fichier" == *.dylib ]]; then
      install_name_tool -id "@rpath/$(basename "$fichier")" "$fichier"
      change=1
    fi
    while IFS= read -r dep; do
      case "$dep" in "$origine"/*) ;; *) continue ;; esac
      cible="$paquet/${dep#"$origine"/}"
      [ -e "$cible" ] || echec "Dépendance absente du paquet : $dep (${fichier#"$paquet"/})"
      relatif=$(perl -MFile::Spec -e 'print File::Spec->abs2rel($ARGV[0], $ARGV[1])' "$cible" "$(dirname "$fichier")")
      install_name_tool -change "$dep" "@loader_path/$relatif" "$fichier"
      change=1
    done < <(otool -L "$fichier" | tail -n +2 | awk '{print $1}')
    if [ "$change" = 1 ]; then
      codesign --force --sign - "$fichier"
      modifies=$((modifies + 1))
    fi
  done < <(find "$paquet" -type f \( -perm -u+x -o -name '*.dylib' -o -name '*.so' \))
  echo "Bibliothèques reliées au paquet : $modifies binaire(s), re-signés en ad hoc"
}

etape "Paquet : copie nettoyée de l'installation"
rm -rf "$PAQUET"
mkdir -p "$(dirname "$PAQUET")"
cp -R "$INSTALLATION" "$PAQUET"
# Bibliothèques statiques et en-têtes du serveur : inutiles pour lancer PostgreSQL
rm -rf "$PAQUET"/.etape-* "$PAQUET"/lib/*.a "$PAQUET/include/postgresql/server"
relier_au_paquet "$PAQUET" "$INSTALLATION"
retirer_rpaths_absolus "$PAQUET"

etape "Dépendances des binaires"
verifier_liens "$PAQUET"

# tester_postgresql <dossier> : crée un cluster avec le paquet déplacé, le démarre, l'interroge, l'arrête
tester_postgresql() {
  local base="$1" d port=18596 reponse
  d=$(mktemp -d "${TMPDIR:-/tmp}/ssrt-pg.XXXXXX")
  # Port déjà servi (serveur d'un essai interrompu) : le test interrogerait le mauvais serveur
  if "$base/bin/pg_isready" -h 127.0.0.1 -p "$port" >/dev/null 2>&1; then
    echec "Port $port déjà utilisé : arrête le serveur qui l'occupe, puis relance"
  fi
  "$base/bin/initdb" -D "$d/data" -U postgres -A trust -E UTF8 \
    --locale-provider=builtin --builtin-locale=C.UTF-8 --locale=C >"$d/initdb.log" 2>&1 ||
    { cat "$d/initdb.log" >&2; echec "initdb a échoué"; }
  "$base/bin/pg_ctl" -D "$d/data" -l "$d/postgresql.log" -w -t 30 \
    -o "-p $port -k $d -c listen_addresses=127.0.0.1" start >/dev/null ||
    { cat "$d/postgresql.log" >&2; echec "PostgreSQL ne démarre pas"; }
  # Serveur arrêté même si une vérification échoue (echec quitte le script)
  trap '"$base/bin/pg_ctl" -D "$d/data" -m immediate stop >/dev/null 2>&1' EXIT
  reponse=$("$base/bin/psql" -h 127.0.0.1 -p "$port" -U postgres -d postgres -X -q -At \
    -c "CREATE TABLE essai (nom text)" -c "INSERT INTO essai VALUES ('KONÉ Awa')" \
    -c "SELECT nom || '|' || upper(nom) FROM essai") || echec "Requête refusée"
  [ "$reponse" = "KONÉ Awa|KONÉ AWA" ] || echec "Lecture de la valeur : « $reponse »"
  echo "initdb, démarrage, écriture, lecture et upper() Unicode : ok"
  "$base/bin/pg_dump" -h 127.0.0.1 -p "$port" -U postgres -d postgres -t essai | grep -q "KONÉ Awa" ||
    echec "pg_dump : valeur absente de l'export"
  echo "pg_dump : ok"
  trap - EXIT
  "$base/bin/pg_ctl" -D "$d/data" -m fast -w stop >/dev/null || echec "Arrêt de PostgreSQL refusé"
  rm -rf "$d"
}

# L'installation d'origine est écartée pendant les tests : le paquet ne doit rien lui emprunter
etape "Tests sur une copie déplacée"
deplace="$TRAVAIL/deplace"
rm -rf "$deplace"
mkdir -p "$deplace"
cp -R "$PAQUET" "$deplace/"
mv "$INSTALLATION" "$INSTALLATION.ecartee"
tester_postgresql "$deplace/postgresql-$VERSION_POSTGRESQL"
mv "$INSTALLATION.ecartee" "$INSTALLATION"
rm -rf "$deplace"

etape "Paquet"
empaqueter "$PAQUET"
