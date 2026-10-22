#!/usr/bin/env bash
# Compile PHP 7.4 (CLI, FPM, CGI) et Xdebug pour macOS arm64, teste le paquet déplacé, l'empaquette.
# Les dépendances doivent avoir été compilées par php/dependances.sh.
# Étapes en cache (configuration, compilation, Xdebug) : seule une étape dont les entrées ont
# changé est refaite ; le paquet (copie, nettoyage, vérifications, tests) est toujours refait.
#
#   ./php/construire.sh

source "$(dirname "$0")/../scripts/commun.sh"

VERSION_PHP=7.4.33
VERSION_XDEBUG=3.1.6
DEPS="${DEPS:-$TRAVAIL/deps-php}"
SRC="$TRAVAIL/src-php"
# Installation de compilation (gardée pour la reprise) et paquet (copie nettoyée de l'installation)
INSTALLATION="$TRAVAIL/installation/php-$VERSION_PHP"
PAQUET="$TRAVAIL/paquets/php-$VERSION_PHP"
SDK="$(xcrun --show-sdk-path)"

[ -d "$DEPS/.etapes" ] || echec "Dépendances absentes : lancer d'abord ./php/dependances.sh"
# Installation restée écartée par des tests interrompus : remise en place (évite une recompilation)
if [ -d "$INSTALLATION.ecartee" ] && [ ! -e "$INSTALLATION" ]; then
  mv "$INSTALLATION.ecartee" "$INSTALLATION"
fi

export PKG_CONFIG_LIBDIR="$DEPS/lib/pkgconfig"
unset PKG_CONFIG_PATH

# Bibliothèques statiques : configure doit recevoir leurs dépendances privées (curl → OpenSSL,
# zlib, frameworks système…), que seul « pkg-config --static » fournit
outils="$TRAVAIL/outils"
mkdir -p "$outils"
pkgconf_reel=$(command -v pkgconf || command -v pkg-config) || echec "pkg-config introuvable"
# PHP_EVAL_LIBLINE (configure de PHP 7.4) découpe « -framework X » en deux mots et casse les tests
# de liaison : le wrapper retire les frameworks, qui passent par LDFLAGS
cat > "$outils/pkg-config-statique" <<SH
#!/bin/sh
sortie=\$("$pkgconf_reel" --static "\$@") || exit \$?
printf '%s\\n' "\$sortie" | sed -E 's/-framework [A-Za-z]+//g'
SH
chmod +x "$outils/pkg-config-statique"
export PKG_CONFIG="$outils/pkg-config-statique"
libs_statiques=$("$pkgconf_reel" --static --libs libcurl libzip) || echec "pkg-config ne trouve pas libcurl ou libzip dans $DEPS"
# libcurl.pc peut omettre les frameworks (SystemConfiguration pour les proxys) : curl-config fait foi
libs_statiques="$libs_statiques $("$DEPS/bin/curl-config" --static-libs)"
# awk plutôt que grep -o : aucun framework n'est pas une erreur
frameworks=$(printf '%s\n' "$libs_statiques" | tr ' ' '\n' | awk '$0 == "-framework" { getline; print "-framework " $0 }' | sort -u | tr '\n' ' ')
echo "Frameworks passés par LDFLAGS : ${frameworks:-aucun}"
# ICU est en C++ : bibliothèque standard C++ de macOS
export LIBS="-lc++"
export CPPFLAGS="-I$DEPS/include"
export LDFLAGS="-L$DEPS/lib $frameworks"
# clang ≥ 16 refuse des constructions C anciennes encore présentes dans PHP 7.4 et ses tests configure ;
# U_DEFINE_FALSE_AND_TRUE : ICU ≥ 68 ne définit plus TRUE/FALSE, employés par ext/intl
export CFLAGS="-O2 -Wno-error=implicit-function-declaration -Wno-error=implicit-int -Wno-error=int-conversion -Wno-error=incompatible-function-pointer-types"
export CXXFLAGS="-O2 -DU_DEFINE_FALSE_AND_TRUE=1"
# Pas de -fvisibility=hidden : avec l'éditeur de liens récent d'Apple, main() devient un symbole
# caché, n'est plus retenu comme point d'entrée, et tout exécutable plante au lancement
# (« Illegal instruction » : premier symptôme, le test de compilation de GD dans configure)
export ax_cv_check_cflags___fvisibility_hidden=no
# libedit du système (readline de la CLI) : macOS ne fournit pas de libedit.pc
export EDIT_CFLAGS="-I$SDK/usr/include"
export EDIT_LIBS="-ledit"

options_php=(
  --prefix="$INSTALLATION"
  --with-config-file-path="$INSTALLATION/etc"
  --with-config-file-scan-dir="$INSTALLATION/etc/conf.d"
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

d="$SRC/php-$VERSION_PHP"
x="$SRC/xdebug-$VERSION_XDEBUG"

configurer_php() {
  extraire "php-$VERSION_PHP.tar.xz" "$SRC" >/dev/null
  if ! (cd "$d" && ./configure "${options_php[@]}"); then
    # Dernier test exécuté : juste avant la section « Cache variables » de config.log
    echo "--- config.log : derniers tests ---" >&2
    awk '/^## Cache variables\. ##/ { exit } { print }' "$d/config.log" | tail -n 60 >&2
    echec "Configuration de PHP en échec"
  fi
}

compiler_php() {
  rm -rf "$INSTALLATION"
  (cd "$d" && make -j"$COEURS" && make install)
}

construire_xdebug() {
  extraire "xdebug-$VERSION_XDEBUG.tgz" "$SRC" >/dev/null
  # phpize s'appuie sur l'autoconf de Homebrew : depuis la 2.72, il ajoute -std=gnu23, où
  # « void f(); » signifie « aucun argument » ; Xdebug 3.1, antérieur à C23, ne compile pas.
  # -std=gnu17, placé après dans la ligne de commande, l'emporte.
  (cd "$x" && "$INSTALLATION/bin/phpize" && CFLAGS="$CFLAGS -std=gnu17" ./configure \
    --with-php-config="$INSTALLATION/bin/php-config" --enable-xdebug && make -j"$COEURS" && make install)
}

# Empreintes : chaque étape inclut celle de la précédente, et la configuration celle des dépendances
cle_configuration=$(empreinte "$(source_de "php-$VERSION_PHP.tar.xz")" "$(declare -f configurer_php)" \
  "${options_php[*]}" "$CFLAGS" "$CXXFLAGS" "$CPPFLAGS" "$LDFLAGS" "$LIBS" "$EDIT_CFLAGS" "$EDIT_LIBS" \
  "$ax_cv_check_cflags___fvisibility_hidden" "$MACOSX_DEPLOYMENT_TARGET" "$(cat "$outils/pkg-config-statique")" \
  "$(cat "$DEPS/.etapes"/*)")
cle_compilation=$(empreinte "$cle_configuration" "$(declare -f compiler_php)")
cle_xdebug=$(empreinte "$cle_compilation" "$(source_de "xdebug-$VERSION_XDEBUG.tgz")" "$(declare -f construire_xdebug)")

# Témoins rangés avec leur résultat : une source ré-extraite ou une installation refaite les invalide
etape_en_cache "$d/.etape-configuration" "$cle_configuration" "PHP $VERSION_PHP : configuration" configurer_php
etape_en_cache "$INSTALLATION/.etape-compilation" "$cle_compilation" "PHP $VERSION_PHP : compilation" compiler_php
etape_en_cache "$INSTALLATION/.etape-xdebug" "$cle_xdebug" "Xdebug $VERSION_XDEBUG" construire_xdebug

etape "Paquet : copie nettoyée de l'installation"
rm -rf "$PAQUET"
mkdir -p "$(dirname "$PAQUET")"
cp -R "$INSTALLATION" "$PAQUET"
# Fichiers inutiles à l'exécution (en-têtes, outils de compilation d'extensions, témoins)
rm -rf "$PAQUET/php/man" "$PAQUET/php/php" "$PAQUET/lib/php/build" "$PAQUET/include" "$PAQUET"/.etape-*
mkdir -p "$PAQUET/etc/conf.d"
# php.ini livré (copie de php.ini-development, comme Homebrew) : sans lui, PHP garde ses valeurs
# internes, dont variables_order = EGPCS, qui remplit $_ENV et casse des applications existantes
# (STiSchools). ShadowStack le passe avec -c ; php.ini-production est fourni à côté.
cp "$d/php.ini-development" "$d/php.ini-production" "$PAQUET/etc/"
cp "$d/php.ini-development" "$PAQUET/etc/php.ini"
retirer_rpaths_absolus "$PAQUET"

etape "Dépendances des binaires"
verifier_liens "$PAQUET"

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

  local ordre
  ordre=$("$php" -c "$p/etc/php.ini" -r 'echo ini_get("variables_order");')
  [ "$ordre" = "GPCS" ] || echec "php.ini livré non pris en compte (variables_order = $ordre)"
  echo "php.ini livré : pris en compte (variables_order = GPCS)"

  "$p/sbin/php-fpm" -n -v | sed -n 1p
  "$p/bin/php-cgi" -n -v | sed -n 1p
}

# L'installation d'origine est écartée pendant les tests : le paquet ne doit rien lui emprunter
etape "Tests sur une copie déplacée"
deplace="$TRAVAIL/deplace"
rm -rf "$deplace"
mkdir -p "$deplace"
cp -R "$PAQUET" "$deplace/"
mv "$INSTALLATION" "$INSTALLATION.ecartee"
tester_php "$deplace/php-$VERSION_PHP"
mv "$INSTALLATION.ecartee" "$INSTALLATION"
rm -rf "$deplace"

etape "Paquet"
empaqueter "$PAQUET"
