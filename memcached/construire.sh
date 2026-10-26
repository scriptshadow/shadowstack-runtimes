#!/usr/bin/env bash
# Compile Memcached pour macOS arm64, libevent compilée en statique dans le binaire (sans TLS ni
# SASL : ShadowStack le lance sur 127.0.0.1 seulement), teste le paquet déplacé (écriture et
# lecture d'une valeur accentuée par le protocole texte, arrêt propre), l'empaquette. Étapes en
# cache : seule une source, une option ou la recette changée les refait ; le paquet (copie,
# vérifications, tests) est toujours refait.
#
#   ./memcached/construire.sh

source "$(dirname "$0")/../scripts/commun.sh"

VERSION_MEMCACHED=1.6.45
VERSION_LIBEVENT=2.1.13-stable
SRC="$TRAVAIL/src-memcached"
DEPS_MC="$TRAVAIL/deps-memcached"
INSTALLATION="$TRAVAIL/installation/memcached-$VERSION_MEMCACHED"
PAQUET="$TRAVAIL/paquets/memcached-$VERSION_MEMCACHED"

# Installation restée écartée par des tests interrompus : remise en place (évite une recompilation)
if [ -d "$INSTALLATION.ecartee" ] && [ ! -e "$INSTALLATION" ]; then
  mv "$INSTALLATION.ecartee" "$INSTALLATION"
fi

drapeaux="-O2 -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"

compiler_libevent() {
  local l
  rm -rf "$DEPS_MC"
  l=$(extraire "libevent-$VERSION_LIBEVENT.tar.gz" "$SRC")
  # Cœur de libevent seulement : ni OpenSSL, ni exemples, ni tests
  (cd "$l" && CFLAGS="$drapeaux" ./configure --prefix="$DEPS_MC" --disable-shared --enable-static \
    --disable-openssl --disable-samples --disable-libevent-regress --disable-debug-mode &&
    make -j"$COEURS" && make install)
}

compiler_memcached() {
  local m
  rm -rf "$INSTALLATION"
  m=$(extraire "memcached-$VERSION_MEMCACHED.tar.gz" "$SRC")
  # Bac à sable de macOS (darwin_priv.c) écarté : le SDK de macOS 27 n'a plus la constante qu'il
  # emploie (kSBXProfileNoInternet). Il ne faisait que couper l'accès à Internet du processus ;
  # ShadowStack lance Memcached sur 127.0.0.1 seulement
  (cd "$m" && CFLAGS="$drapeaux" ac_cv_func_sandbox_init=no ./configure --prefix="$INSTALLATION" --with-libevent="$DEPS_MC" \
    --disable-sasl --disable-tls --disable-docs --disable-coverage &&
    make -j"$COEURS" && make install)
}

cle_libevent=$(empreinte "$(source_de "libevent-$VERSION_LIBEVENT.tar.gz")" "$(declare -f compiler_libevent)" "$drapeaux")
etape_en_cache "$DEPS_MC/.etape-libevent" "$cle_libevent" "libevent $VERSION_LIBEVENT (statique)" compiler_libevent
cle_compilation=$(empreinte "$cle_libevent" "$(source_de "memcached-$VERSION_MEMCACHED.tar.gz")" \
  "$(declare -f compiler_memcached)" "$drapeaux")
etape_en_cache "$INSTALLATION/.etape-compilation" "$cle_compilation" "Memcached $VERSION_MEMCACHED : compilation" compiler_memcached

etape "Paquet : copie nettoyée de l'installation"
rm -rf "$PAQUET"
mkdir -p "$(dirname "$PAQUET")"
cp -R "$INSTALLATION" "$PAQUET"
# En-têtes (protocole binaire) et pages de manuel : inutiles pour lancer Memcached
rm -rf "$PAQUET"/.etape-* "$PAQUET/include" "$PAQUET/share"
retirer_rpaths_absolus "$PAQUET"

etape "Dépendances des binaires"
verifier_liens "$PAQUET"

# tester_memcached <dossier> : lance memcached depuis le paquet déplacé, l'interroge, l'arrête
tester_memcached() {
  local base="$1" port=18597 pid reponse valeur="KONÉ Awa" octets
  # Port déjà servi (serveur d'un essai interrompu) : le test interrogerait le mauvais serveur
  if nc -z 127.0.0.1 "$port" 2>/dev/null; then
    echec "Port $port déjà utilisé : arrête le serveur qui l'occupe, puis relance"
  fi
  "$base/bin/memcached" -l 127.0.0.1 -p "$port" -U 0 -m 16 &
  pid=$!
  # Serveur arrêté même si une vérification échoue (echec quitte le script)
  trap 'kill -TERM "$pid" 2>/dev/null; wait "$pid" 2>/dev/null' EXIT
  for _ in $(seq 1 30); do
    nc -z 127.0.0.1 "$port" 2>/dev/null && break
    sleep 0.2
  done
  # Taille en octets (UTF-8) : É en compte deux
  octets=$(printf '%s' "$valeur" | wc -c | tr -d ' ')
  reponse=$(printf 'set essai 0 0 %s\r\n%s\r\nget essai\r\nquit\r\n' "$octets" "$valeur" | nc 127.0.0.1 "$port" | tr -d '\r')
  [ "$reponse" = "$(printf 'STORED\nVALUE essai 0 %s\n%s\nEND' "$octets" "$valeur")" ] ||
    echec "Écriture et lecture : réponse inattendue « $reponse »"
  echo "Écriture et lecture (protocole texte) : ok"
  trap - EXIT
  kill -TERM "$pid"
  wait "$pid" || echec "Memcached s'est arrêté en erreur (code $?)"
}

# L'installation d'origine est écartée pendant les tests : le paquet ne doit rien lui emprunter
etape "Tests sur une copie déplacée"
deplace="$TRAVAIL/deplace"
rm -rf "$deplace"
mkdir -p "$deplace"
cp -R "$PAQUET" "$deplace/"
mv "$INSTALLATION" "$INSTALLATION.ecartee"
tester_memcached "$deplace/memcached-$VERSION_MEMCACHED"
mv "$INSTALLATION.ecartee" "$INSTALLATION"
rm -rf "$deplace"

etape "Paquet"
empaqueter "$PAQUET"
