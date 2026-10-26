#!/usr/bin/env bash
# Compile Redis pour macOS arm64 (serveur seul, allocateur de la libc, sans TLS ni modules : ShadowStack le lance
# sur 127.0.0.1 seulement), teste le paquet déplacé (PING, écriture et lecture d'une valeur
# accentuée, arrêt propre), l'empaquette. Étape en cache : seule une source, une option ou la
# recette changée la refait ; le paquet (copie, vérifications, tests) est toujours refait.
#
#   ./redis/construire.sh

source "$(dirname "$0")/../scripts/commun.sh"

VERSION_REDIS=8.10.2
SRC="$TRAVAIL/src-redis"
INSTALLATION="$TRAVAIL/installation/redis-$VERSION_REDIS"
PAQUET="$TRAVAIL/paquets/redis-$VERSION_REDIS"

# Installation restée écartée par des tests interrompus : remise en place (évite une recompilation)
if [ -d "$INSTALLATION.ecartee" ] && [ ! -e "$INSTALLATION" ]; then
  mv "$INSTALLATION.ecartee" "$INSTALLATION"
fi

options_make=(
  BUILD_TLS=no
  MALLOC=libc
)

compiler_redis() {
  local r
  rm -rf "${SRC:?}" "$INSTALLATION"
  r=$(extraire "redis-$VERSION_REDIS.tar.gz" "$SRC")
  # Serveur seul (src/) : la cible par défaut de Redis 8 compile aussi ses modules (RediSearch,
  # RedisJSON…), qui demandent d'autres outils et ne servent pas ici
  (cd "$r" && make -C src -j"$COEURS" "${options_make[@]}" && make -C src PREFIX="$INSTALLATION" install)
}

cle_compilation=$(empreinte "$(source_de "redis-$VERSION_REDIS.tar.gz")" "$(declare -f compiler_redis)" \
  "${options_make[*]}" "$MACOSX_DEPLOYMENT_TARGET")
etape_en_cache "$INSTALLATION/.etape-compilation" "$cle_compilation" "Redis $VERSION_REDIS : compilation" compiler_redis

etape "Paquet : copie nettoyée de l'installation"
rm -rf "$PAQUET"
mkdir -p "$(dirname "$PAQUET")"
cp -R "$INSTALLATION" "$PAQUET"
rm -rf "$PAQUET"/.etape-*
retirer_rpaths_absolus "$PAQUET"

etape "Dépendances des binaires"
verifier_liens "$PAQUET"

# tester_redis <dossier> : lance redis-server depuis le paquet déplacé, l'interroge, l'arrête
tester_redis() {
  local base="$1" d port=18595 pid reponse
  d=$(mktemp -d "${TMPDIR:-/tmp}/ssrt-redis.XXXXXX")
  # Port déjà servi (serveur d'un essai interrompu) : le test interrogerait le mauvais serveur
  if "$base/bin/redis-cli" -p "$port" ping >/dev/null 2>&1; then
    echec "Port $port déjà utilisé : arrête le serveur qui l'occupe, puis relance"
  fi
  "$base/bin/redis-server" --port "$port" --bind 127.0.0.1 --dir "$d" --save "" --appendonly no \
    --logfile "$d/redis.log" &
  pid=$!
  # Serveur arrêté même si une vérification échoue (echec quitte le script)
  trap 'kill -TERM "$pid" 2>/dev/null; wait "$pid" 2>/dev/null' EXIT
  for _ in $(seq 1 30); do
    "$base/bin/redis-cli" -p "$port" ping >/dev/null 2>&1 && break
    sleep 0.2
  done
  reponse=$("$base/bin/redis-cli" -p "$port" ping) || { cat "$d/redis.log" >&2; echec "Redis ne répond pas"; }
  [ "$reponse" = PONG ] || echec "PING : réponse inattendue « $reponse »"
  "$base/bin/redis-cli" -p "$port" set essai "KONÉ Awa" >/dev/null
  reponse=$("$base/bin/redis-cli" -p "$port" --no-raw get essai)
  [ "$reponse" = '"KON\xc3\x89 Awa"' ] || echec "Lecture de la valeur : « $reponse »"
  echo "PING, écriture et lecture : ok"
  trap - EXIT
  "$base/bin/redis-cli" -p "$port" shutdown nosave >/dev/null 2>&1 || echec "Arrêt de Redis refusé"
  wait "$pid" || echec "Redis s'est arrêté en erreur (code $?)"
  rm -rf "$d"
}

# L'installation d'origine est écartée pendant les tests : le paquet ne doit rien lui emprunter
etape "Tests sur une copie déplacée"
deplace="$TRAVAIL/deplace"
rm -rf "$deplace"
mkdir -p "$deplace"
cp -R "$PAQUET" "$deplace/"
mv "$INSTALLATION" "$INSTALLATION.ecartee"
tester_redis "$deplace/redis-$VERSION_REDIS"
mv "$INSTALLATION.ecartee" "$INSTALLATION"
rm -rf "$deplace"

etape "Paquet"
empaqueter "$PAQUET"
