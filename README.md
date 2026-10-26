# shadowstack-runtimes

Binaires PHP, MariaDB, PostgreSQL, Redis, Memcached, Nginx et Apache pour **macOS arm64**, compilés pour ShadowStack, un environnement de développement web local. Ni PHP, ni MariaDB, ni PostgreSQL, ni Redis, ni Memcached, ni Nginx, ni Apache ne publient de binaires officiels pour macOS : ce dépôt les compile, les teste et les publie dans ses [releases](../../releases). MySQL publie les siens : ses archives officielles y sont redistribuées telles quelles, après vérification et tests, pour que ShadowStack garde une adresse stable (Oracle ne sert que la dernière version de chaque branche).

La compilation se fait **en local**, sur un Mac Apple Silicon : ce dépôt n'utilise pas GitHub Actions.

## Paquets

| Paquet | Contenu |
|---|---|
| `php-7.4.33-macos-arm64.tar.gz` | PHP 7.4.33 (CLI, FPM, CGI), Xdebug 3.1.6, OPcache ; extensions courantes compilées dans le binaire (mysqli, pdo_mysql, intl, gd avec JPEG/PNG/FreeType, mbstring, curl, openssl, zip, soap…) ; OpenSSL 1.1.1 |
| `php-8.3.36-macos-arm64.tar.gz` | PHP 8.3.36, mêmes binaires et extensions, Xdebug 3.5.3, OPcache ; OpenSSL 3.5 |
| `php-7.4.33-r2-macos-arm64.tar.gz`, `php-8.3.36-r2-macos-arm64.tar.gz` | Révision 2 des deux paquets PHP : mêmes binaires et extensions, plus `pgsql` et `pdo_pgsql` (libpq 18 statique, avec l'OpenSSL de la branche) et l'extension `memcached` 3.4.0 (`memcached.so`, libmemcached 1.1.4 statique, sans SASL), à charger avec `extension=memcached`. Une archive publiée n'est jamais remplacée : chaque reconstruction d'une même version de PHP prend un nouveau numéro (`REVISION_PHP`, `php/versions.sh`) |
| `mariadb-10.6.28-macos-arm64.tar.gz` | MariaDB 10.6.28 : serveur, clients, `mariadb-dump`, `mariadb-install-db` |
| `nginx-1.30.6-macos-arm64.tar.gz` | Nginx 1.30.6 (stable), moteur web derrière Caddy : PCRE2 10.49 avec JIT et zlib compilés dans le binaire, modules realip et threads ; sans TLS (Caddy le termine) |
| `httpd-2.4.69-macos-arm64.tar.gz` | Apache httpd 2.4.69 (MPM event), moteur web derrière Caddy qui lit les `.htaccess` : OpenSSL 3.5, APR 1.7.6, APR-util 1.6.5 et PCRE2 10.49 en statique, modules compilés dans le binaire (rewrite, proxy_fcgi, balancer, remoteip, headers, deflate, ssl…) ; mod_ssl sert à la liaison entre Caddy et Apache |
| `redis-8.10.2-macos-arm64.tar.gz` | Redis 8.10.2, service optionnel de ShadowStack (127.0.0.1) : serveur seul, allocateur de la libc, sans TLS ni modules (RediSearch, RedisJSON…) ; `redis-server`, `redis-cli` et outils. Licence AGPLv3 (l'une des licences de Redis 8), sources dans `sources.txt` |
| `postgresql-18.6-macos-arm64.tar.gz` | PostgreSQL 18.6, service optionnel de ShadowStack (127.0.0.1) : serveur, clients (`psql`, `pg_dump`, `pg_restore`…), modules de contrib sans dépendance externe (`pg_trgm`, `unaccent`, `hstore`, `citext`…) ; sans ICU ni OpenSSL (collations par le fournisseur intégré `C.UTF-8`), libedit et zlib du système ; `libpq` reliée au paquet (`@loader_path`) |
| `memcached-1.6.45-macos-arm64.tar.gz` | Memcached 1.6.45, service optionnel de ShadowStack (127.0.0.1) : libevent 2.1.13 compilée dans le binaire, sans TLS ni SASL ; bac à sable de macOS écarté (le SDK de macOS 27 n'a plus son API) |
| `mysql-8.4.13-macos15-arm64.tar.gz`, `mysql-8.4.13-winx64.zip` | MySQL 8.4.13 LTS, archives officielles d'Oracle inchangées (même SHA-256 ; MD5 publié par Oracle recoupé). L'archive macOS exige macOS 15 |

Chaque paquet compilé :

- **ne dépend que du système** : dépendances compilées en statique (OpenSSL 1.1.1 pour PHP 7.4 ou 3.5 pour PHP 8.3, ICU 72, libxml2, curl… pour PHP ; OpenSSL 3.5, PCRE2, zlib pour MariaDB). La compilation échoue si un binaire référence une bibliothèque hors de `/usr/lib` et `/System` ;
- **fonctionne depuis n'importe quel dossier** : les tests tournent sur une copie déplacée ;
- est accompagné de son empreinte SHA-256 (`.sha256`) ;
- vise macOS 13 et plus.

## Sources

Toutes les archives sources sont listées dans [`sources.txt`](sources.txt) avec leur URL officielle et leur empreinte SHA-256, vérifiée avant chaque compilation.

## Compiler en local

Prérequis : Xcode (outils en ligne de commande) et, depuis Homebrew, `cmake`, `pkgconf`, `autoconf` et `bison` (outils de compilation uniquement : les paquets n'en dépendent pas).

```bash
brew install cmake pkgconf autoconf bison ccache
./scripts/ci-local.sh tout
```

`./scripts/ci-local.sh php` (PHP 7.4), `./scripts/ci-local.sh php 8.3` `./scripts/ci-local.sh mariadb`, `./scripts/ci-local.sh nginx`, `./scripts/ci-local.sh apache`, `./scripts/ci-local.sh redis`, `./scripts/ci-local.sh postgresql` ou `./scripts/ci-local.sh memcached` pour un seul composant ; `./scripts/ci-local.sh mysql` vérifie, teste et copie dans `sortie/` les archives officielles de MySQL (sans compilation). Les branches de PHP (version complète, Xdebug, OpenSSL) sont décrites dans [`php/versions.sh`](php/versions.sh) ; chacune a son propre jeu de dépendances dans `travail/`. Le script vérifie les outils et l'espace disque (10 Go), compile, teste le paquet sur une copie déplacée et produit le paquet et son empreinte dans `sortie/`.

**Reprise automatique** : chaque étape (chaque dépendance, configuration, compilation, Xdebug) a une empreinte calculée à partir de ses sources, de sa recette, de ses options et des étapes dont elle dépend. Relancer le script ne refait que les étapes dont l'empreinte a changé ; `ccache`, s'il est installé, garde les fichiers déjà compilés. Les caches vivent dans `travail/`.

| Commande | Effet |
|---|---|
| `./scripts/ci-local.sh php 8.3 --complet` | refait toutes les étapes, sans tenir compte du cache |
| `./scripts/ci-local.sh nettoyer` | libère l'espace : arbres de compilation, dépendances, cache `ccache` (archives téléchargées et `sortie/` gardées) |

Publication d'une release (étape manuelle, après vérification) :

```bash
./scripts/publier.sh php-8.3.36 "PHP 8.3.36 pour macOS arm64"
```

## Licences

Les paquets redistribuent des logiciels sous leurs propres licences :

- PHP : PHP License 3.01 ; Xdebug : Xdebug License 1.03 ; extension memcached : PHP License 3.01 ; libmemcached : licence BSD
- MariaDB : GNU GPL v2 ; sources correspondantes : https://archive.mariadb.org/mariadb-10.6.28/source/
- Nginx : licence BSD à 2 clauses ; PCRE2 : licence BSD
- Apache httpd, APR, APR-util : licence Apache 2.0
- PostgreSQL : PostgreSQL License (licence libre de type BSD)
- Memcached, libevent : licence BSD
- MySQL Community Server : GNU GPL v2 (licence et notices dans l'archive : `LICENSE`, `README`) ; sources correspondantes : https://dev.mysql.com/downloads/mysql/8.4.html (« Source Code »)
- OpenSSL 1.1.1 : licence OpenSSL et SSLeay ; OpenSSL 3.5 : Apache 2.0 ; ICU : licence Unicode ; curl : licence curl ; libxml2, zlib, libpng, libjpeg-turbo, FreeType, libzip, Oniguruma, SQLite : licences libres respectives

Les scripts de ce dépôt servent à reproduire chaque paquet à l'identique à partir de ces sources.

## Contribuer

Commits au format `[emoji] type: description` (exemple : `📦 build: compiler PHP 8.3 pour macOS arm64`). Activer les hooks une fois par clone :

```bash
git config core.hooksPath scripts/hooks
```
