#!/usr/bin/env bash
# Branches de PHP compilées (à sourcer après commun.sh) : version complète, Xdebug et OpenSSL de
# chacune. BRANCHE_PHP choisit la branche (./scripts/ci-local.sh php 8.3) ; 7.4 par défaut.
#
# REVISION_PHP : révision du paquet pour une même version de PHP (1 : première publication,
# php-7.4.33-macos-arm64.tar.gz ; 2 et plus : php-7.4.33-r2-macos-arm64.tar.gz, release
# php-7.4.33-r2). Une archive publiée n'est jamais remplacée : le catalogue de ShadowStack fixe
# son empreinte. Révision 2 : pgsql et pdo_pgsql (libpq 18 statique), extension memcached.
REVISION_PHP=2
# Extension memcached (PECL), compilée à part comme Xdebug, avec libmemcached statique
VERSION_MEMCACHED_EXT=3.4.0

BRANCHE_PHP="${BRANCHE_PHP:-7.4}"
case "$BRANCHE_PHP" in
  7.4)
    VERSION_PHP=7.4.33
    VERSION_XDEBUG=3.1.6
    # PHP 7.4 ne compile pas avec OpenSSL 3
    ARCHIVE_OPENSSL=openssl-1.1.1w.tar.gz
    OPENSSL_ATTENDU="OpenSSL 1.1.1"
    # Nom historique du dossier : le cache des dépendances déjà compilées reste valable
    DEPS_BRANCHE="$TRAVAIL/deps-php"
    ;;
  8.3)
    VERSION_PHP=8.3.36
    VERSION_XDEBUG=3.5.3
    # OpenSSL 3.5 LTS, comme MariaDB (OpenSSL 1.1.1 n'est plus maintenu)
    ARCHIVE_OPENSSL=openssl-3.5.9.tar.gz
    OPENSSL_ATTENDU="OpenSSL 3.5"
    DEPS_BRANCHE="$TRAVAIL/deps-php8"
    ;;
  *) echec "Branche de PHP inconnue : $BRANCHE_PHP (7.4 ou 8.3)" ;;
esac
DEPS="${DEPS:-$DEPS_BRANCHE}"
