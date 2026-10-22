#!/usr/bin/env bash
# Compile PHP 7.4 (CLI, FPM, CGI) et Xdebug pour macOS arm64, teste le paquet déplacé, l'empaquette.
# Les dépendances doivent avoir été compilées par php/dependances.sh.
#
#   ./php/construire.sh

source "$(dirname "$0")/../scripts/commun.sh"

VERSION_PHP=7.4.33
VERSION_XDEBUG=3.1.6
DEPS="${DEPS:-$TRAVAIL/deps-php}"
SRC="$TRAVAIL/src-php"
PREFIXE="$TRAVAIL/paquets/php-$VERSION_PHP"
SDK="$(xcrun --show-sdk-path)"

[ -f "$DEPS/lib/libssl.a" ] || echec "Dépendances absentes : lancer d'abord ./php/dependances.sh"

export PKG_CONFIG_LIBDIR="$DEPS/lib/pkgconfig"
unset PKG_CONFIG_PATH
export CPPFLAGS="-I$DEPS/include"
export LDFLAGS="-L$DEPS/lib"
# clang ≥ 16 refuse des constructions C anciennes encore présentes dans PHP 7.4 et ses tests configure ;
# U_DEFINE_FALSE_AND_TRUE : ICU ≥ 68 ne définit plus TRUE/FALSE, employés par ext/intl
export CFLAGS="-O2 -Wno-error=implicit-function-declaration -Wno-error=implicit-int -Wno-error=int-conversion -Wno-error=incompatible-function-pointer-types"
export CXXFLAGS="-O2 -DU_DEFINE_FALSE_AND_TRUE=1"

options_php=(
  --prefix="$PREFIXE"
  --with-config-file-path="$PREFIXE/etc"
  --with-config-file-scan-dir="$PREFIXE/etc/conf.d"
  --enable-fpm
  --enable-cgi
  --disable-phpdbg
  --without-pear
  # JIT de PCRE désactivé : instable sous macOS arm64 avant PHP 8
  --without-pcre-jit
  --with-openssl
  --with-curl
  --with-zlib
  --with-zip
  --with-bz2="$SDK/usr"
  --with-iconv="$SDK/usr"
  --with-libedit
  --enable-mbstring
  --enable-intl
  --enable-bcmath
  --enable-calendar
  --enable-exif
  --enable-sockets
  --enable-soap
  --enable-pcntl
  --enable-sysvsem
  --enable-sysvshm
  --enable-sysvmsg
  --enable-shmop
  --enable-gd
  --with-jpeg
  --with-freetype
  --with-mysqli=mysqlnd
  --with-pdo-mysql=mysqlnd
  --with-sqlite3
  --with-pdo-sqlite
  --enable-opcache
)

etape "PHP $VERSION_PHP : configuration"
d=$(extraire "php-$VERSION_PHP.tar.xz" "$SRC")
rm -rf "$PREFIXE"
(cd "$d" && ./configure "${options_php[@]}")

etape "PHP $VERSION_PHP : compilation"
(cd "$d" && make -j"$COEURS" && make install)

etape "Xdebug $VERSION_XDEBUG"
x=$(extraire "xdebug-$VERSION_XDEBUG.tgz" "$SRC")
(cd "$x" && "$PREFIXE/bin/phpize" && ./configure --with-php-config="$PREFIXE/bin/php-config" --enable-xdebug \
  && make -j"$COEURS" && make install)

# Fichiers inutiles à l'exécution
rm -rf "$PREFIXE/php/man" "$PREFIXE/php/php" "$PREFIXE/lib/php/build" "$PREFIXE/include"
mkdir -p "$PREFIXE/etc/conf.d"

etape "Dépendances des binaires"
verifier_liens "$PREFIXE"

# tester_php <dossier> : tests sur un paquet déplacé (aucun php.ini : tout est passé en -d)
tester_php() {
  local p="$1" php ext
  php="$p/bin/php"
  # Pas de « | head » ici ni plus bas : avec pipefail, le SIGPIPE ferait échouer la commande
  ext=$(find "$p/lib/php/extensions" -maxdepth 1 -type d -name 'no-debug-*' | sed -n 1p)
  [ -n "$ext" ] || echec "Dossier des extensions introuvable"

  "$php" -n -v
  local manquantes=() m modules version
  modules=$("$php" -n -m)
  for m in bcmath calendar ctype curl date dom exif fileinfo filter gd hash iconv intl json \
    libxml mbstring mysqli mysqlnd openssl pcntl pcre pdo pdo_mysql pdo_sqlite posix readline \
    session simplexml soap sockets sqlite3 tokenizer xml xmlreader xmlwriter zip zlib; do
    grep -qix "$m" <<<"$modules" || manquantes+=("$m")
  done
  [ ${#manquantes[@]} -eq 0 ] || echec "Extensions absentes : ${manquantes[*]}"
  echo "Extensions : toutes présentes"

  "$php" -n -r '
    $f = new IntlDateFormatter("fr_FR", IntlDateFormatter::FULL, IntlDateFormatter::NONE, "Africa/Abidjan");
    $verifs = [
      "intl"     => $f->format(0) === "jeudi 1 janvier 1970",
      "gd jpeg"  => gd_info()["JPEG Support"] === true,
      "gd ft"    => gd_info()["FreeType Support"] === true,
      "gd png"   => gd_info()["PNG Support"] === true,
      "pcre"     => preg_match("/^é+$/u", "ééé") === 1,
      "mbstring" => mb_strtoupper("élève") === "ÉLÈVE",
      "openssl"  => strpos(OPENSSL_VERSION_TEXT, "OpenSSL 1.1.1") === 0,
      "curl"     => strpos(curl_version()["ssl_version"], "OpenSSL") === 0,
      "zip"      => class_exists("ZipArchive"),
      "sqlite"   => (new PDO("sqlite::memory:"))->query("select 1")->fetchColumn() == 1,
    ];
    foreach ($verifs as $nom => $ok) { echo str_pad($nom, 10), $ok ? "ok" : "ÉCHEC", "\n"; }
    exit(in_array(false, $verifs, true) ? 1 : 0);
  ' || echec "Vérifications fonctionnelles en échec"

  "$php" -n -d zend_extension="$ext/opcache.so" -d opcache.enable_cli=1 -r 'exit(opcache_get_status() === false ? 1 : 0);' \
    || echec "OPcache ne se charge pas"
  version=$("$php" -n -d zend_extension="$ext/xdebug.so" -v)
  grep -q "with Xdebug v$VERSION_XDEBUG" <<<"$version" || echec "Xdebug ne se charge pas"
  echo "OPcache et Xdebug : chargés"

  "$p/sbin/php-fpm" -n -v | sed -n 1p
  "$p/bin/php-cgi" -n -v | sed -n 1p
}

etape "Tests sur une copie déplacée"
deplace="$TRAVAIL/deplace"
rm -rf "$deplace"
mkdir -p "$deplace"
cp -R "$PREFIXE" "$deplace/"
mv "$PREFIXE" "$PREFIXE.origine"
tester_php "$deplace/php-$VERSION_PHP"
mv "$PREFIXE.origine" "$PREFIXE"
rm -rf "$deplace"

etape "Paquet"
empaqueter "$PREFIXE"
