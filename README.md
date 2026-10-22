# shadowstack-runtimes

Binaires PHP et MariaDB pour **macOS arm64**, compilés pour ShadowStack, un environnement de développement web local. Ni PHP 7.4 ni MariaDB ne publient de binaires officiels pour macOS : ce dépôt les compile, les teste et les publie dans ses [releases](../../releases).

La compilation se fait **en local**, sur un Mac Apple Silicon : ce dépôt n'utilise pas GitHub Actions.

## Paquets

| Paquet | Contenu |
|---|---|
| `php-7.4.33-macos-arm64.tar.gz` | PHP 7.4.33 (CLI, FPM, CGI), Xdebug 3.1.6, OPcache ; extensions courantes compilées dans le binaire (mysqli, pdo_mysql, intl, gd avec JPEG/PNG/FreeType, mbstring, curl, openssl, zip, soap…) |
| `mariadb-10.6.28-macos-arm64.tar.gz` | MariaDB 10.6.28 : serveur, clients, `mariadb-dump`, `mariadb-install-db` |

Chaque paquet :

- **ne dépend que du système** : dépendances compilées en statique (OpenSSL 1.1.1, ICU 72, libxml2, curl… pour PHP ; OpenSSL 3.5, PCRE2, zlib pour MariaDB). La compilation échoue si un binaire référence une bibliothèque hors de `/usr/lib` et `/System` ;
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

`./scripts/ci-local.sh php` ou `./scripts/ci-local.sh mariadb` pour un seul composant. Le script vérifie les outils et l'espace disque (10 Go), compile, teste le paquet sur une copie déplacée et produit le paquet et son empreinte dans `sortie/`.

**Reprise automatique** : chaque étape (chaque dépendance, configuration, compilation, Xdebug) a une empreinte calculée à partir de ses sources, de sa recette, de ses options et des étapes dont elle dépend. Relancer le script ne refait que les étapes dont l'empreinte a changé ; `ccache`, s'il est installé, garde les fichiers déjà compilés. Les caches vivent dans `travail/`.

| Commande | Effet |
|---|---|
| `./scripts/ci-local.sh php --complet` | refait toutes les étapes, sans tenir compte du cache |
| `./scripts/ci-local.sh nettoyer` | libère l'espace : arbres de compilation, dépendances, cache `ccache` (archives téléchargées et `sortie/` gardées) |

Publication d'une release (étape manuelle, après vérification) :

```bash
./scripts/publier.sh php-7.4.33 "PHP 7.4.33 pour macOS arm64"
```

## Licences

Les paquets redistribuent des logiciels sous leurs propres licences :

- PHP : PHP License 3.01 ; Xdebug : Xdebug License 1.03
- MariaDB : GNU GPL v2 ; sources correspondantes : https://archive.mariadb.org/mariadb-10.6.28/source/
- OpenSSL 1.1.1 : licence OpenSSL et SSLeay ; OpenSSL 3.5 : Apache 2.0 ; ICU : licence Unicode ; curl : licence curl ; libxml2, zlib, libpng, libjpeg-turbo, FreeType, libzip, Oniguruma, SQLite : licences libres respectives

Les scripts de ce dépôt servent à reproduire chaque paquet à l'identique à partir de ces sources.

## Contribuer

Commits au format `[emoji] type: description` (exemple : `📦 build: compiler PHP 8.3 pour macOS arm64`). Activer les hooks une fois par clone :

```bash
git config core.hooksPath scripts/hooks
```
