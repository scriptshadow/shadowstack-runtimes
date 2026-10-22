#!/usr/bin/env bash
# Compile MariaDB pour macOS arm64 avec ses dépendances embarquées (OpenSSL 3.5 statique, PCRE2, zlib),
# teste le paquet déplacé (initialisation, démarrage, requêtes, greffon, export), l'empaquette.
# Étapes en cache (OpenSSL, configuration, compilation) : seule une étape dont les entrées ont
# changé est refaite ; le paquet (copie, nettoyage, vérifications, tests) est toujours refait.
#
#   ./mariadb/construire.sh

source "$(dirname "$0")/../scripts/commun.sh"

VERSION_MARIADB=10.6.28
SRC="$TRAVAIL/src-mariadb"
DEPS="$TRAVAIL/deps-mariadb"
# Installation de compilation (gardée pour la reprise) et paquet (copie nettoyée de l'installation)
INSTALLATION="$TRAVAIL/installation/mariadb-$VERSION_MARIADB"
PAQUET="$TRAVAIL/paquets/mariadb-$VERSION_MARIADB"

# Installation restée écartée par des tests interrompus : remise en place (évite une recompilation)
if [ -d "$INSTALLATION.ecartee" ] && [ ! -e "$INSTALLATION" ]; then
  mv "$INSTALLATION.ecartee" "$INSTALLATION"
fi

# pkg-config limité aux dépendances compilées ici : sans cela, le connecteur client trouve le
# GnuTLS de Homebrew et le paquet en dépendrait
export PKG_CONFIG_LIBDIR="$DEPS/lib/pkgconfig"
unset PKG_CONFIG_PATH

# MariaDB exige un bison plus récent que celui de macOS (2.3) : celui de Homebrew sert à la
# compilation seulement, le paquet n'en dépend pas
if command -v brew >/dev/null 2>&1 && [ -d "$(brew --prefix bison 2>/dev/null)/bin" ]; then
  export PATH="$(brew --prefix bison)/bin:$PATH"
fi

options_cmake=(
  -DCMAKE_BUILD_TYPE=RelWithDebInfo
  -DCMAKE_INSTALL_PREFIX="$INSTALLATION"
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET"
  -DCMAKE_IGNORE_PREFIX_PATH="/opt/homebrew;/usr/local"
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5
  -DCOMPILATION_COMMENT="ShadowStack"
  # Dépendances embarquées : le paquet ne dépend que du système. OpenSSL plutôt que WolfSSL :
  # avec WolfSSL, le connecteur client de la 10.6 exige GnuTLS (absent de macOS)
  -DWITH_SSL="$DEPS"
  -DOPENSSL_USE_STATIC_LIBS=TRUE
  -DWITH_PCRE=bundled
  -DWITH_ZLIB=bundled
  -DWITH_JEMALLOC=no
  -DWITH_UNIT_TESTS=OFF
  -DCONC_WITH_UNIT_TESTS=OFF
  -DWITH_EMBEDDED_SERVER=OFF
  -DWITH_WSREP=OFF
  -DWITH_MARIABACKUP=OFF
  -DINSTALL_MYSQLTESTDIR=
  -DINSTALL_SQLBENCHDIR=
  # Greffons qui demandent des bibliothèques externes (Boost, ODBC, curl, Kerberos, PAM…)
  -DPLUGIN_ROCKSDB=NO
  -DPLUGIN_MROONGA=NO
  -DPLUGIN_SPIDER=NO
  -DPLUGIN_OQGRAPH=NO
  -DPLUGIN_CONNECT=NO
  -DPLUGIN_S3=NO
  -DPLUGIN_COLUMNSTORE=NO
  -DPLUGIN_AUTH_GSSAPI=NO
  # Greffon du connecteur client : valeurs DYNAMIC, STATIC ou OFF (pas NO)
  -DPLUGIN_AUTH_GSSAPI_CLIENT=OFF
  -DPLUGIN_AUTH_PAM=NO
  -DPLUGIN_AUTH_PAM_V1=NO
  -DPLUGIN_PROVIDER_BZIP2=NO
  -DPLUGIN_PROVIDER_LZ4=NO
  -DPLUGIN_PROVIDER_LZMA=NO
  -DPLUGIN_PROVIDER_LZO=NO
  -DPLUGIN_PROVIDER_SNAPPY=NO
)

d="$SRC/mariadb-$VERSION_MARIADB"

construire_openssl() {
  local o
  rm -rf "${DEPS:?}"
  o=$(extraire openssl-3.5.9.tar.gz "$SRC")
  # openssldir = magasin du système : les certificats racine de macOS servent par défaut
  (cd "$o" && ./Configure darwin64-arm64-cc no-shared no-tests no-docs --prefix="$DEPS" --libdir=lib \
    --openssldir=/private/etc/ssl && make -j"$COEURS" && make install_sw)
  rm -rf "${o:?}"
}

configurer_mariadb() {
  extraire "mariadb-$VERSION_MARIADB.tar.gz" "$SRC" >/dev/null
  cmake -S "$d" -B "$d/build" "${options_cmake[@]}"
}

compiler_mariadb() {
  rm -rf "$INSTALLATION"
  cmake --build "$d/build" -j"$COEURS"
  cmake --install "$d/build"
}

# Empreintes : chaque étape inclut celle de la précédente
cle_openssl=$(empreinte "$(source_de openssl-3.5.9.tar.gz)" "$(declare -f construire_openssl)" "$MACOSX_DEPLOYMENT_TARGET")
cle_configuration=$(empreinte "$cle_openssl" "$(source_de "mariadb-$VERSION_MARIADB.tar.gz")" \
  "$(declare -f configurer_mariadb)" "${options_cmake[*]}")
cle_compilation=$(empreinte "$cle_configuration" "$(declare -f compiler_mariadb)")

# Témoins rangés avec leur résultat : des dépendances, une source ou une installation refaites les invalident
etape_en_cache "$DEPS/.etape-openssl" "$cle_openssl" "OpenSSL 3.5 (statique)" construire_openssl
etape_en_cache "$d/.etape-configuration" "$cle_configuration" "MariaDB $VERSION_MARIADB : configuration" configurer_mariadb
etape_en_cache "$INSTALLATION/.etape-compilation" "$cle_compilation" "MariaDB $VERSION_MARIADB : compilation" compiler_mariadb

etape "Paquet : copie nettoyée de l'installation"
rm -rf "$PAQUET"
mkdir -p "$(dirname "$PAQUET")"
cp -R "$INSTALLATION" "$PAQUET"
# Fichiers inutiles à l'exécution (tests, en-têtes, documentation, bibliothèques statiques, témoins)
rm -rf "$PAQUET/mysql-test" "$PAQUET/sql-bench" "$PAQUET/include" "$PAQUET/man" \
  "$PAQUET/docs" "$PAQUET/lib/pkgconfig" "$PAQUET/lib"/*.a "$PAQUET"/.etape-*
retirer_rpaths_absolus "$PAQUET"

etape "Dépendances des binaires"
verifier_liens "$PAQUET"

# tester_mariadb <dossier> : initialise, démarre, interroge et arrête un serveur depuis le paquet déplacé
tester_mariadb() {
  local base="$1" donnees port=3399 socket client pid i
  donnees=$(mktemp -d "${TMPDIR:-/tmp}/ssrt-donnees.XXXXXX")
  # Chemin court : un socket Unix est limité à 103 caractères sous macOS
  socket="/tmp/ssrt-$$.sock"
  client=("$base/bin/mariadb" --no-defaults -h127.0.0.1 -P"$port" -uroot --default-character-set=utf8mb4)

  "$base/scripts/mariadb-install-db" --no-defaults --basedir="$base" --datadir="$donnees" \
    --auth-root-authentication-method=normal --skip-test-db >/dev/null

  "$base/bin/mariadbd" --no-defaults --basedir="$base" --datadir="$donnees" --port="$port" \
    --bind-address=127.0.0.1 --socket="$socket" --pid-file="$donnees/test.pid" \
    --log-error="$donnees/erreurs.log" --character-set-server=utf8mb4 &
  pid=$!

  for i in $(seq 1 60); do
    "$base/bin/mariadb-admin" --no-defaults -h127.0.0.1 -P"$port" -uroot ping >/dev/null 2>&1 && break
    sleep 1
  done
  "$base/bin/mariadb-admin" --no-defaults -h127.0.0.1 -P"$port" -uroot ping \
    || { cat "$donnees/erreurs.log" >&2; echec "Le serveur ne démarre pas"; }

  "${client[@]}" <<'SQL'
CREATE DATABASE essai CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
USE essai;
CREATE TABLE notes (id INT AUTO_INCREMENT PRIMARY KEY, eleve VARCHAR(40), note DECIMAL(4,2), journal VARCHAR(80));
CREATE TRIGGER notes_ai BEFORE INSERT ON notes FOR EACH ROW SET NEW.journal = CONCAT('ajout ', NEW.eleve);
INSERT INTO notes (eleve, note) VALUES ('KONÉ Awa', 15.5), ('Élève', 12);
SELECT VERSION(), COUNT(*), GROUP_CONCAT(journal) FROM notes;
INSTALL SONAME 'metadata_lock_info';
UNINSTALL SONAME 'metadata_lock_info';
SQL
  "$base/bin/mariadb-dump" --no-defaults -h127.0.0.1 -P"$port" -uroot --triggers essai > "$donnees/export.sql"
  grep -q "KONÉ Awa" "$donnees/export.sql" || echec "Export incomplet"
  echo "Requêtes, trigger, greffon dynamique et export : ok"

  "$base/bin/mariadb-admin" --no-defaults -h127.0.0.1 -P"$port" -uroot shutdown
  wait "$pid" || echec "Le serveur s'est arrêté en erreur (code $?)"
  rm -rf "$donnees"
}

# L'installation d'origine est écartée pendant les tests : le paquet ne doit rien lui emprunter
etape "Tests sur une copie déplacée"
deplace="$TRAVAIL/deplace"
rm -rf "$deplace"
mkdir -p "$deplace"
cp -R "$PAQUET" "$deplace/"
mv "$INSTALLATION" "$INSTALLATION.ecartee"
tester_mariadb "$deplace/mariadb-$VERSION_MARIADB"
mv "$INSTALLATION.ecartee" "$INSTALLATION"
rm -rf "$deplace"

etape "Paquet"
empaqueter "$PAQUET"
