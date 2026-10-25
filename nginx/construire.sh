#!/usr/bin/env bash
# Compile Nginx pour macOS arm64, PCRE2 (avec JIT) et zlib compilés dans le binaire, teste le paquet
# déplacé (fichier statique, 403, réécriture par expression régulière, gzip), l'empaquette. Nginx sert
# de moteur à ShadowStack derrière Caddy : pas de TLS (Caddy le termine), module realip pour
# l'adresse du visiteur. Étape en cache : seule une source, une option ou la recette changée la
# refait ; le paquet (copie, vérifications, tests) est toujours refait.
#
#   ./nginx/construire.sh

source "$(dirname "$0")/../scripts/commun.sh"

VERSION_NGINX=1.30.6
SRC="$TRAVAIL/src-nginx"
INSTALLATION="$TRAVAIL/installation/nginx-$VERSION_NGINX"
PAQUET="$TRAVAIL/paquets/nginx-$VERSION_NGINX"

# Installation restée écartée par des tests interrompus : remise en place (évite une recompilation)
if [ -d "$INSTALLATION.ecartee" ] && [ ! -e "$INSTALLATION" ]; then
  mv "$INSTALLATION.ecartee" "$INSTALLATION"
fi

options_configure=(
  --with-cc-opt="-O2 -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"
  --with-ld-opt="-mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"
  --with-pcre-jit
  --with-http_realip_module
  --with-threads
  # Inutiles derrière Caddy pour des sites PHP
  --without-http_scgi_module
  --without-http_uwsgi_module
)

compiler_nginx() {
  local n p z
  rm -rf "${SRC:?}" "$INSTALLATION"
  n=$(extraire "nginx-$VERSION_NGINX.tar.gz" "$SRC")
  p=$(extraire pcre2-10.49.tar.gz "$SRC")
  z=$(extraire zlib-1.3.1.tar.gz "$SRC")
  # Préfixe d'installation seulement : ShadowStack lance toujours nginx avec -p et -c
  (cd "$n" && ./configure --prefix="$INSTALLATION" --with-pcre="$p" --with-zlib="$z" \
    "${options_configure[@]}" && make -j"$COEURS" && make install)
}

cle_compilation=$(empreinte "$(source_de "nginx-$VERSION_NGINX.tar.gz")" "$(source_de pcre2-10.49.tar.gz)" \
  "$(source_de zlib-1.3.1.tar.gz)" "$(declare -f compiler_nginx)" "${options_configure[*]}" "$MACOSX_DEPLOYMENT_TARGET")
etape_en_cache "$INSTALLATION/.etape-compilation" "$cle_compilation" "Nginx $VERSION_NGINX : compilation (PCRE2, zlib)" compiler_nginx

etape "Paquet : copie nettoyée de l'installation"
rm -rf "$PAQUET"
mkdir -p "$(dirname "$PAQUET")"
cp -R "$INSTALLATION" "$PAQUET"
# Journaux vides et témoins : ShadowStack écrit les siens ailleurs
rm -rf "$PAQUET/logs" "$PAQUET"/.etape-* "$PAQUET"/conf/*.default
retirer_rpaths_absolus "$PAQUET"

etape "Dépendances des binaires"
verifier_liens "$PAQUET"

# tester_nginx <dossier> : sert un dossier depuis le paquet déplacé, l'interroge, l'arrête
tester_nginx() {
  local base="$1" d port=18590 pid
  d=$(mktemp -d "${TMPDIR:-/tmp}/ssrt-nginx.XXXXXX")
  mkdir -p "$d/www" "$d/logs"
  printf 'Bonjour, KONÉ Awa\n' > "$d/www/index.html"
  cat > "$d/nginx.conf" <<CONF
daemon off;
worker_processes 1;
error_log $d/logs/erreurs.log;
pid $d/nginx.pid;
events { worker_connections 64; }
http {
  include $base/conf/mime.types;
  access_log off;
  client_body_temp_path $d/temp-corps;
  proxy_temp_path $d/temp-proxy;
  fastcgi_temp_path $d/temp-fastcgi;
  gzip on;
  gzip_min_length 1;
  server {
    listen 127.0.0.1:$port;
    root $d/www;
    charset utf-8;
    location /interdit { return 403; }
    location ~ ^/capture/([a-z]+)$ { return 200 "capture \$1"; }
  }
}
CONF
  "$base/sbin/nginx" -p "$d" -c "$d/nginx.conf" -e "$d/logs/demarrage.log" -t
  "$base/sbin/nginx" -p "$d" -c "$d/nginx.conf" -e "$d/logs/demarrage.log" &
  pid=$!
  for _ in $(seq 1 30); do
    curl -fs "http://127.0.0.1:$port/" >/dev/null 2>&1 && break
    sleep 0.5
  done
  curl -fs "http://127.0.0.1:$port/" | grep -q "KONÉ Awa" || { cat "$d/logs/erreurs.log" >&2; echec "Fichier statique non servi"; }
  [ "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/interdit")" = 403 ] || echec "403 attendu"
  [ "$(curl -s "http://127.0.0.1:$port/capture/abc")" = "capture abc" ] || echec "Réécriture PCRE2 en échec"
  curl -s -H 'Accept-Encoding: gzip' -D - -o /dev/null "http://127.0.0.1:$port/" | grep -qi '^content-encoding: gzip' ||
    echec "Compression gzip absente"
  echo "Fichier statique, 403, expression régulière et gzip : ok"
  kill -QUIT "$pid"
  wait "$pid" || echec "Nginx s'est arrêté en erreur (code $?)"
  rm -rf "$d"
}

# L'installation d'origine est écartée pendant les tests : le paquet ne doit rien lui emprunter
etape "Tests sur une copie déplacée"
deplace="$TRAVAIL/deplace"
rm -rf "$deplace"
mkdir -p "$deplace"
cp -R "$PAQUET" "$deplace/"
mv "$INSTALLATION" "$INSTALLATION.ecartee"
tester_nginx "$deplace/nginx-$VERSION_NGINX"
mv "$INSTALLATION.ecartee" "$INSTALLATION"
rm -rf "$deplace"

etape "Paquet"
empaqueter "$PAQUET"
