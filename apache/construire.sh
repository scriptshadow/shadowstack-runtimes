#!/usr/bin/env bash
# Compile Apache httpd pour macOS arm64 : APR, APR-util et PCRE2 en statique, modules compilés dans
# le binaire (aucune bibliothèque à reloger), expat et zlib du système. Apache sert de moteur à
# ShadowStack derrière Caddy : il lit les .htaccess et parle aux pools PHP (proxy_fcgi) ; pas de
# TLS (Caddy le termine). Teste le paquet déplacé (fichier statique, .htaccess avec réécriture,
# en-tête et Require, compression), l'empaquette. Étapes en cache (dépendances, compilation).
#
#   ./apache/construire.sh

source "$(dirname "$0")/../scripts/commun.sh"

VERSION_HTTPD=2.4.69
SRC="$TRAVAIL/src-apache"
DEPS="$TRAVAIL/deps-apache"
INSTALLATION="$TRAVAIL/installation/httpd-$VERSION_HTTPD"
PAQUET="$TRAVAIL/paquets/httpd-$VERSION_HTTPD"
SDK="$(xcrun --show-sdk-path)"

# Installation restée écartée par des tests interrompus : remise en place (évite une recompilation)
if [ -d "$INSTALLATION.ecartee" ] && [ ! -e "$INSTALLATION" ]; then
  mv "$INSTALLATION.ecartee" "$INSTALLATION"
fi

options_httpd=(
  --with-mpm=event
  --enable-mods-static=most
  # Modules dont ShadowStack a besoin, compilés dans le binaire même s'ils ne sont pas dans « most »
  --enable-rewrite=static
  --enable-remoteip=static
  --enable-proxy=static
  --enable-proxy-fcgi=static
  --enable-proxy-balancer=static
  --enable-lbmethod-byrequests=static
  --enable-slotmem-shm=static
  --enable-headers=static
  --enable-expires=static
  --enable-deflate=static
  # Inutiles derrière Caddy, ou demandant des bibliothèques absentes du système
  --disable-ssl
  --disable-lua
  --disable-proxy-html
  --disable-xml2enc
  --disable-brotli
  --disable-http2
  --disable-md
)

construire_dependances() {
  local p a u
  rm -rf "${DEPS:?}" "${SRC:?}"
  p=$(extraire pcre2-10.49.tar.gz "$SRC")
  (cd "$p" && ./configure --prefix="$DEPS" --disable-shared --enable-static --enable-jit && make -j"$COEURS" && make install)
  a=$(extraire apr-1.7.6.tar.gz "$SRC")
  (cd "$a" && ./configure --prefix="$DEPS" --disable-shared --enable-static && make -j"$COEURS" && make install)
  u=$(extraire apr-util-1.6.5.tar.gz "$SRC")
  (cd "$u" && ./configure --prefix="$DEPS" --with-apr="$DEPS" --with-expat="$SDK/usr" --without-crypto \
    --without-ldap --without-pgsql --without-mysql --without-sqlite3 --without-sqlite2 --without-oracle \
    --without-odbc --without-berkeley-db --without-gdbm --without-ndbm --disable-shared --enable-static &&
    make -j"$COEURS" && make install)
}

compiler_httpd() {
  local h
  rm -rf "$INSTALLATION"
  h=$(extraire "httpd-$VERSION_HTTPD.tar.gz" "$SRC")
  (cd "$h" && ./configure --prefix="$INSTALLATION" --with-apr="$DEPS" --with-apr-util="$DEPS" \
    --with-pcre="$DEPS/bin/pcre2-config" --with-z="$SDK/usr" "${options_httpd[@]}" &&
    make -j"$COEURS" && make install)
}

cle_dependances=$(empreinte "$(source_de pcre2-10.49.tar.gz)" "$(source_de apr-1.7.6.tar.gz)" \
  "$(source_de apr-util-1.6.5.tar.gz)" "$(declare -f construire_dependances)" "$MACOSX_DEPLOYMENT_TARGET")
cle_compilation=$(empreinte "$cle_dependances" "$(source_de "httpd-$VERSION_HTTPD.tar.gz")" \
  "$(declare -f compiler_httpd)" "${options_httpd[*]}")
etape_en_cache "$DEPS/.etape-dependances" "$cle_dependances" "PCRE2, APR et APR-util (statiques)" construire_dependances
etape_en_cache "$INSTALLATION/.etape-compilation" "$cle_compilation" "Apache httpd $VERSION_HTTPD : compilation" compiler_httpd

etape "Paquet : copie nettoyée de l'installation"
rm -rf "$PAQUET"
mkdir -p "$(dirname "$PAQUET")"
cp -R "$INSTALLATION" "$PAQUET"
# Documentation, en-têtes, outils de compilation de modules et scripts qui figent les chemins de
# compilation (apachectl, envvars, apxs) : inutiles à ShadowStack, qui lance httpd avec -d et -f
rm -rf "$PAQUET/manual" "$PAQUET/include" "$PAQUET/build" "$PAQUET/man" "$PAQUET/htdocs" \
  "$PAQUET/cgi-bin" "$PAQUET/logs" "$PAQUET/conf/original" "$PAQUET/conf/extra" "$PAQUET/conf/httpd.conf" \
  "$PAQUET/bin/apachectl" "$PAQUET/bin/envvars" "$PAQUET/bin/envvars-std" "$PAQUET/bin/apxs" \
  "$PAQUET/modules" "$PAQUET"/.etape-*
retirer_rpaths_absolus "$PAQUET"

etape "Dépendances des binaires"
verifier_liens "$PAQUET"

# tester_httpd <dossier> : sert un dossier avec un .htaccess depuis le paquet déplacé, l'arrête
tester_httpd() {
  local base="$1" d port=18591 pid module modules entetes page
  # MPM event : « event.c » dans la liste de httpd -l ; liste lue d'abord (pipefail, voir plus bas)
  modules=$("$base/bin/httpd" -l)
  for module in mod_rewrite mod_remoteip mod_proxy_fcgi mod_proxy_balancer mod_lbmethod_byrequests \
    mod_headers mod_deflate mod_expires mod_setenvif mod_access_compat event; do
    grep -q "$module.c" <<<"$modules" || echec "Module absent du binaire : $module"
  done
  echo "Modules compilés dans le binaire : ok"
  d=$(mktemp -d "${TMPDIR:-/tmp}/ssrt-httpd.XXXXXX")
  mkdir -p "$d/www/prive" "$d/logs" "$d/run"
  # Page de taille réaliste : mod_deflate ne compresse pas une réponse minuscule
  { printf 'Bonjour, KONÉ Awa\n'; for _ in $(seq 1 100); do printf 'Ligne de contenu pour la compression\n'; done; } > "$d/www/index.html"
  printf 'secret\n' > "$d/www/prive/secret.txt"
  printf 'RewriteEngine On\nRewriteRule ^reecrit$ index.html [L]\nHeader set X-Essai "oui"\n' > "$d/www/.htaccess"
  printf 'Require all denied\n' > "$d/www/prive/.htaccess"
  cat > "$d/httpd.conf" <<CONF
ServerRoot "$base"
Listen 127.0.0.1:$port
ServerName localhost
PidFile "$d/run/httpd.pid"
DefaultRuntimeDir "$d/run"
ErrorLog "$d/logs/erreurs.log"
LogLevel warn
TypesConfig "$base/conf/mime.types"
AddDefaultCharset utf-8
DocumentRoot "$d/www"
<Directory "$d/www">
    AllowOverride All
    Require all granted
</Directory>
AddOutputFilterByType DEFLATE text/html text/plain
CONF
  "$base/bin/httpd" -d "$base" -f "$d/httpd.conf" -t
  # Port déjà servi (serveur d'un essai interrompu) : le test interrogerait le mauvais serveur
  if curl -s -o /dev/null "http://127.0.0.1:$port/"; then
    echec "Port $port déjà utilisé : arrête le serveur qui l'occupe, puis relance"
  fi
  "$base/bin/httpd" -d "$base" -f "$d/httpd.conf" -DFOREGROUND &
  pid=$!
  # Serveur arrêté même si une vérification échoue (echec quitte le script)
  trap 'kill -TERM "$pid" 2>/dev/null; wait "$pid" 2>/dev/null' EXIT
  for _ in $(seq 1 30); do
    curl -fs "http://127.0.0.1:$port/" >/dev/null 2>&1 && break
    sleep 0.5
  done
  page=$(curl -fs "http://127.0.0.1:$port/") || { cat "$d/logs/erreurs.log" >&2; echec "Fichier statique non servi"; }
  grep -q "KONÉ Awa" <<<"$page" || echec "Fichier statique incomplet"
  page=$(curl -fs "http://127.0.0.1:$port/reecrit") || echec "RewriteRule du .htaccess sans effet"
  grep -q "KONÉ Awa" <<<"$page" || echec "RewriteRule du .htaccess : mauvaise page"
  # En-têtes lus d'abord : avec pipefail, « curl | grep -q » échoue quand grep s'arrête avant curl
  entetes=$(curl -s -D - -o /dev/null "http://127.0.0.1:$port/")
  grep -qi '^x-essai: oui' <<<"$entetes" || echec "Header du .htaccess absent"
  [ "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/prive/secret.txt")" = 403 ] ||
    echec "Require all denied sans effet"
  entetes=$(curl -s -H 'Accept-Encoding: gzip' -D - -o /dev/null "http://127.0.0.1:$port/")
  grep -qi '^content-encoding: gzip' <<<"$entetes" || echec "Compression absente"
  echo "Fichier statique, .htaccess (réécriture, en-tête, Require) et compression : ok"
  trap - EXIT
  kill -TERM "$pid"
  wait "$pid" || echec "Apache s'est arrêté en erreur (code $?)"
  rm -rf "$d"
}

# L'installation d'origine est écartée pendant les tests : le paquet ne doit rien lui emprunter
etape "Tests sur une copie déplacée"
deplace="$TRAVAIL/deplace"
rm -rf "$deplace"
mkdir -p "$deplace"
cp -R "$PAQUET" "$deplace/"
mv "$INSTALLATION" "$INSTALLATION.ecartee"
tester_httpd "$deplace/httpd-$VERSION_HTTPD"
mv "$INSTALLATION.ecartee" "$INSTALLATION"
rm -rf "$deplace"

etape "Paquet"
empaqueter "$PAQUET"
