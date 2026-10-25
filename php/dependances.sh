#!/usr/bin/env bash
# Compile en statique les dépendances de PHP (branche BRANCHE_PHP, cf. php/versions.sh) dans $DEPS.
# Rien n'est pris dans Homebrew :
# pkg-config ne cherche que dans $DEPS, CMake ignore /opt/homebrew et /usr/local.
# Chaque dépendance a son propre cache : seule une dépendance modifiée (ou l'une de celles dont
# elle dépend) est recompilée.
#
#   ./php/dependances.sh

source "$(dirname "$0")/../scripts/commun.sh"
source "$(dirname "$0")/versions.sh"

SRC="$TRAVAIL/src-deps-php-$BRANCHE_PHP"
TEMOINS="$DEPS/.etapes"

export PKG_CONFIG_LIBDIR="$DEPS/lib/pkgconfig"
unset PKG_CONFIG_PATH
export CPPFLAGS="-I$DEPS/include"
export LDFLAGS="-L$DEPS/lib"
export CFLAGS="-O2"
export CXXFLAGS="-O2"

cmake_options=(
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_INSTALL_PREFIX="$DEPS"
  -DCMAKE_INSTALL_LIBDIR=lib
  -DCMAKE_PREFIX_PATH="$DEPS"
  -DCMAKE_IGNORE_PREFIX_PATH="/opt/homebrew;/usr/local"
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET"
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5
  -DBUILD_SHARED_LIBS=OFF
)

# autotools <dossier> [options configure…]
autotools() {
  local dossier="$1"
  shift
  (cd "$dossier" && ./configure --prefix="$DEPS" --disable-shared --enable-static "$@" && make -j"$COEURS" && make install)
}

# cmake_construire <dossier> [options cmake…]
cmake_construire() {
  local dossier="$1"
  shift
  cmake -S "$dossier" -B "$dossier/build" "${cmake_options[@]}" "$@"
  cmake --build "$dossier/build" -j"$COEURS"
  cmake --install "$dossier/build"
}

# dependance <nom> <archive> "<dépendances requises>" <fonction de construction>
# Empreinte : archive, recette, options communes, et empreintes des dépendances requises
dependance() {
  local nom="$1" archive="$2" requises="$3" fonction="$4" requise
  local parties=(
    "$(source_de "$archive")"
    "$(declare -f "$fonction" autotools cmake_construire)"
    "$CFLAGS" "$CXXFLAGS" "$CPPFLAGS" "$LDFLAGS" "$MACOSX_DEPLOYMENT_TARGET" "${cmake_options[*]}"
  )
  for requise in $requises; do
    parties+=("$(cat "$TEMOINS/$requise")")
  done
  etape_en_cache "$TEMOINS/$nom" "$(empreinte "${parties[@]}")" "$nom" "$fonction"
}

construire_zlib() {
  local d
  d=$(extraire zlib-1.3.1.tar.gz "$SRC")
  (cd "$d" && ./configure --prefix="$DEPS" --static && make -j"$COEURS" && make install)
}

construire_openssl() {
  local d
  d=$(extraire "$ARCHIVE_OPENSSL" "$SRC")
  # openssldir = magasin du système : les certificats racine de macOS servent par défaut ;
  # --libdir=lib : OpenSSL 3 installerait sinon dans lib64 selon la plateforme
  (cd "$d" && ./Configure darwin64-arm64-cc no-shared no-tests --prefix="$DEPS" --libdir=lib \
    --openssldir=/private/etc/ssl && make -j"$COEURS" && make install_sw)
}

construire_libxml2() {
  local d
  d=$(extraire libxml2-2.9.14.tar.xz "$SRC")
  autotools "$d" --without-python --without-lzma --without-icu --without-http --without-ftp --with-zlib="$DEPS"
}

construire_sqlite() {
  local d
  d=$(extraire sqlite-autoconf-3460100.tar.gz "$SRC")
  # Métadonnées de colonnes : requises par pdo_sqlite (sqlite3_column_table_name)
  CFLAGS="$CFLAGS -DSQLITE_ENABLE_COLUMN_METADATA=1" autotools "$d"
}

construire_oniguruma() {
  local d
  d=$(extraire onig-6.9.9.tar.gz "$SRC")
  autotools "$d"
}

construire_icu() {
  local d
  d=$(extraire icu4c-72_1-src.tgz "$SRC")
  (cd "$d/source" && ./runConfigureICU MacOSX --prefix="$DEPS" --enable-static --disable-shared \
    --disable-samples --disable-tests --disable-extras --with-data-packaging=static \
    && make -j"$COEURS" && make install)
}

construire_libpng() {
  local d
  d=$(extraire libpng-1.6.43.tar.xz "$SRC")
  autotools "$d"
}

construire_libjpeg() {
  local d
  d=$(extraire libjpeg-turbo-3.0.3.tar.gz "$SRC")
  cmake_construire "$d" -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DWITH_TURBOJPEG=OFF
}

construire_freetype() {
  local d
  d=$(extraire freetype-2.13.2.tar.xz "$SRC")
  autotools "$d" --with-zlib=no --with-bzip2=no --with-png=no --with-harfbuzz=no --with-brotli=no
}

construire_libzip() {
  local d
  d=$(extraire libzip-1.10.1.tar.xz "$SRC")
  cmake_construire "$d" -DENABLE_BZIP2=OFF -DENABLE_LZMA=OFF -DENABLE_ZSTD=OFF -DENABLE_GNUTLS=OFF \
    -DENABLE_MBEDTLS=OFF -DENABLE_OPENSSL=OFF -DENABLE_COMMONCRYPTO=ON -DBUILD_TOOLS=OFF \
    -DBUILD_REGRESS=OFF -DBUILD_OSSFUZZ=OFF -DBUILD_EXAMPLES=OFF -DBUILD_DOC=OFF
}

construire_curl() {
  local d
  d=$(extraire curl-8.10.1.tar.xz "$SRC")
  autotools "$d" --with-openssl="$DEPS" --with-zlib="$DEPS" --with-ca-bundle=/etc/ssl/cert.pem \
    --without-libpsl --without-brotli --without-zstd --without-nghttp2 --without-libidn2 \
    --without-librtmp --without-libssh2 --disable-ldap --disable-docs --disable-manual
}

mkdir -p "$DEPS" "$SRC" "$TEMOINS"

dependance zlib zlib-1.3.1.tar.gz "" construire_zlib
dependance openssl "$ARCHIVE_OPENSSL" "" construire_openssl
dependance libxml2 libxml2-2.9.14.tar.xz "zlib" construire_libxml2
dependance sqlite sqlite-autoconf-3460100.tar.gz "" construire_sqlite
dependance oniguruma onig-6.9.9.tar.gz "" construire_oniguruma
dependance icu icu4c-72_1-src.tgz "" construire_icu
dependance libpng libpng-1.6.43.tar.xz "zlib" construire_libpng
dependance libjpeg libjpeg-turbo-3.0.3.tar.gz "" construire_libjpeg
dependance freetype freetype-2.13.2.tar.xz "" construire_freetype
dependance libzip libzip-1.10.1.tar.xz "zlib" construire_libzip
dependance curl curl-8.10.1.tar.xz "zlib openssl" construire_curl

# Sources extraites : inutiles une fois installées (une dépendance à refaire est ré-extraite)
rm -rf "${SRC:?}"

etape "Dépendances prêtes"
cat "$TEMOINS"/* | shasum -a 256 | awk '{print "Empreinte de l'\''ensemble : " $1}'
