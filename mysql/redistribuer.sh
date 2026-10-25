#!/usr/bin/env bash
# MySQL : binaires officiels d'Oracle, redistribués tels quels (pas de compilation). Les archives
# de sources.txt sont téléchargées et vérifiées (SHA-256 noté, MD5 publié par Oracle recoupé à
# l'ajout), l'archive macOS est testée sur une copie déplacée (dépendances, initialisation,
# démarrage, requêtes, trigger, utilisateur à mot de passe, export), puis les deux archives sont
# copiées inchangées dans sortie/ avec leur .sha256 : même empreinte que chez Oracle.
#
#   ./mysql/redistribuer.sh

source "$(dirname "$0")/../scripts/commun.sh"

VERSION_MYSQL=8.4.13
ARCHIVE_MACOS="mysql-$VERSION_MYSQL-macos15-arm64.tar.gz"
ARCHIVE_WINDOWS="mysql-$VERSION_MYSQL-winx64.zip"

# tester_mysql <dossier> : initialise, démarre, interroge et arrête un serveur depuis la copie
tester_mysql() {
  local base="$1" donnees port=3399 socket client pid i
  donnees=$(mktemp -d "${TMPDIR:-/tmp}/ssrt-mysql.XXXXXX")
  # Chemin court : un socket Unix est limité à 103 caractères sous macOS
  socket="/tmp/ssrt-$$.sock"
  client=("$base/bin/mysql" --no-defaults -h127.0.0.1 -P"$port" -uroot --default-character-set=utf8mb4)

  "$base/bin/mysqld" --no-defaults --basedir="$base" --datadir="$donnees/data" \
    --log-error="$donnees/initialisation.log" --initialize-insecure ||
    { cat "$donnees/initialisation.log" >&2; echec "Initialisation impossible"; }

  # X Protocol coupé : son port 33060 est souvent pris par un autre MySQL
  "$base/bin/mysqld" --no-defaults --basedir="$base" --datadir="$donnees/data" --port="$port" \
    --bind-address=127.0.0.1 --socket="$socket" --pid-file="$donnees/test.pid" --mysqlx=OFF \
    --log-error="$donnees/erreurs.log" --character-set-server=utf8mb4 &
  pid=$!

  for i in $(seq 1 60); do
    "$base/bin/mysqladmin" --no-defaults -h127.0.0.1 -P"$port" -uroot ping >/dev/null 2>&1 && break
    sleep 1
  done
  "$base/bin/mysqladmin" --no-defaults -h127.0.0.1 -P"$port" -uroot ping ||
    { cat "$donnees/erreurs.log" >&2; echec "Le serveur ne démarre pas"; }

  "${client[@]}" <<'SQL'
CREATE DATABASE essai CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
USE essai;
CREATE TABLE notes (id INT AUTO_INCREMENT PRIMARY KEY, eleve VARCHAR(40), note DECIMAL(4,2), journal VARCHAR(80));
CREATE TRIGGER notes_ai BEFORE INSERT ON notes FOR EACH ROW SET NEW.journal = CONCAT('ajout ', NEW.eleve);
INSERT INTO notes (eleve, note) VALUES ('KONÉ Awa', 15.5), ('Élève', 12);
SELECT VERSION(), COUNT(*), GROUP_CONCAT(journal) FROM notes;
CREATE USER 'essai'@'127.0.0.1' IDENTIFIED BY 'mot-de-passe-essai';
GRANT ALL ON essai.* TO 'essai'@'127.0.0.1';
SQL
  # Utilisateur à mot de passe par TCP, sans TLS : authentification caching_sha2_password complète
  "$base/bin/mysql" --no-defaults -h127.0.0.1 -P"$port" -uessai -pmot-de-passe-essai --ssl-mode=DISABLED \
    --get-server-public-key -e "SELECT CURRENT_USER()" essai >/dev/null ||
    echec "Connexion par mot de passe refusée"
  "$base/bin/mysqldump" --no-defaults -h127.0.0.1 -P"$port" -uroot --triggers essai > "$donnees/export.sql"
  grep -q "KONÉ Awa" "$donnees/export.sql" || echec "Export incomplet"
  echo "Requêtes, trigger, utilisateur à mot de passe et export : ok"

  "$base/bin/mysqladmin" --no-defaults -h127.0.0.1 -P"$port" -uroot shutdown
  wait "$pid" || echec "Le serveur s'est arrêté en erreur (code $?)"
  rm -rf "$donnees"
}

etape "Archives officielles (empreintes de sources.txt)"
macos=$(telecharger "$ARCHIVE_MACOS")
windows=$(telecharger "$ARCHIVE_WINDOWS")
echo "Vérifiées : $ARCHIVE_MACOS, $ARCHIVE_WINDOWS"

etape "Tests sur une copie déplacée (macOS)"
deplace="$TRAVAIL/deplace"
rm -rf "$deplace"
mkdir -p "$deplace"
tar -xzf "$macos" -C "$deplace"
# Binaires de débogage d'Oracle (mysqld-debug, greffons debug/) : LC_RPATH absolu vers la machine
# de compilation d'Oracle. ShadowStack ne les lance jamais ; retirés de la copie vérifiée (l'archive
# redistribuée reste celle d'Oracle, inchangée)
rm -f "$deplace/mysql-$VERSION_MYSQL-macos15-arm64/bin/mysqld-debug"
rm -rf "$deplace/mysql-$VERSION_MYSQL-macos15-arm64/lib/plugin/debug"
verifier_liens "$deplace/mysql-$VERSION_MYSQL-macos15-arm64"
"$deplace/mysql-$VERSION_MYSQL-macos15-arm64/bin/mysqld" --no-defaults --version
tester_mysql "$deplace/mysql-$VERSION_MYSQL-macos15-arm64"
rm -rf "$deplace"

etape "Paquets (archives officielles inchangées)"
mkdir -p "$SORTIE"
for archive in "$macos" "$windows"; do
  nom=$(basename "$archive")
  cp "$archive" "$SORTIE/$nom"
  (cd "$SORTIE" && shasum -a 256 "$nom" > "$nom.sha256")
  cat "$SORTIE/$nom.sha256"
done
