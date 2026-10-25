#!/usr/bin/env bash
# Branches de PHP compilées (à sourcer après commun.sh) : version complète, Xdebug et OpenSSL de
# chacune. BRANCHE_PHP choisit la branche (./scripts/ci-local.sh php 8.3) ; 7.4 par défaut.

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
