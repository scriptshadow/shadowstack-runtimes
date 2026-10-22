#!/usr/bin/env bash
# Compile en statique les dépendances de PHP 7.4 dans $DEPS. Rien n'est pris dans Homebrew :
# pkg-config ne cherche que dans $DEPS, CMake ignore /opt/homebrew et /usr/local.
#
#   ./php/dependances.sh

source "$(dirname "$0")/../scripts/commun.sh"

DEPS="${DEPS:-$TRAVAIL/deps-php}"
SRC="$TRAVAIL/src-deps-php"

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

mkdir -p "$DEPS" "$SRC"

etape "zlib"
d=$(extraire zlib-1.3.1.tar.gz "$SRC")
(cd "$d" && ./configure --prefix="$DEPS" --static && make -j"$COEURS" && make install)

etape "OpenSSL 1.1.1"
d=$(extraire openssl-1.1.1w.tar.gz "$SRC")
# openssldir = magasin du système : les certificats racine de macOS servent par défaut
(cd "$d" && ./Configure darwin64-arm64-cc no-shared no-tests --prefix="$DEPS" --openssldir=/private/etc/ssl \
  && make -j"$COEURS" && make install_sw)

etape "libxml2 2.9"
d=$(extraire libxml2-2.9.14.tar.xz "$SRC")
autotools "$d" --without-python --without-lzma --without-icu --without-http --without-ftp --with-zlib="$DEPS"

etape "SQLite"
d=$(extraire sqlite-autoconf-3460100.tar.gz "$SRC")
autotools "$d"

etape "Oniguruma (mbstring)"
d=$(extraire onig-6.9.9.tar.gz "$SRC")
autotools "$d"

etape "ICU 72 (intl)"
d=$(extraire icu4c-72_1-src.tgz "$SRC")
(cd "$d/source" && ./runConfigureICU MacOSX --prefix="$DEPS" --enable-static --disable-shared \
  --disable-samples --disable-tests --disable-extras --with-data-packaging=static \
  && make -j"$COEURS" && make install)

etape "libpng"
d=$(extraire libpng-1.6.43.tar.xz "$SRC")
autotools "$d"

etape "libjpeg-turbo"
d=$(extraire libjpeg-turbo-3.0.3.tar.gz "$SRC")
cmake_construire "$d" -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DWITH_TURBOJPEG=OFF

etape "FreeType"
d=$(extraire freetype-2.13.2.tar.xz "$SRC")
autotools "$d" --with-zlib=no --with-bzip2=no --with-png=no --with-harfbuzz=no --with-brotli=no

etape "libzip"
d=$(extraire libzip-1.10.1.tar.xz "$SRC")
cmake_construire "$d" -DENABLE_BZIP2=OFF -DENABLE_LZMA=OFF -DENABLE_ZSTD=OFF -DENABLE_GNUTLS=OFF \
  -DENABLE_MBEDTLS=OFF -DENABLE_OPENSSL=OFF -DENABLE_COMMONCRYPTO=ON -DBUILD_TOOLS=OFF \
  -DBUILD_REGRESS=OFF -DBUILD_OSSFUZZ=OFF -DBUILD_EXAMPLES=OFF -DBUILD_DOC=OFF

etape "curl"
d=$(extraire curl-8.10.1.tar.xz "$SRC")
autotools "$d" --with-openssl="$DEPS" --with-zlib="$DEPS" --with-ca-bundle=/etc/ssl/cert.pem \
  --without-libpsl --without-brotli --without-zstd --without-nghttp2 --without-libidn2 \
  --without-librtmp --without-libssh2 --disable-ldap --disable-docs --disable-manual

etape "Dépendances prêtes"
ls "$DEPS/lib"/*.a
