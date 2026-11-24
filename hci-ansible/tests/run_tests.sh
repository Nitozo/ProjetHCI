#!/usr/bin/env bash
# Tests de bout en bout avec virsh/rbd simules (aucun hyperviseur requis)
set -uo pipefail
cd "$(dirname "$0")/.."
export MOCK_STATE; MOCK_STATE=$(mktemp -d)
export PATH="$PWD/tests/mock:$PATH"
export ANSIBLE_INVENTORY="$PWD/tests/inventory.yml"
export ANSIBLE_PLAYBOOK="${ANSIBLE_PLAYBOOK:-ansible-playbook}"
H=./hcictl.sh; fail=0; n=0
ok()  { n=$((n+1)); echo "  [OK]   $1"; }
ko()  { n=$((n+1)); fail=$((fail+1)); echo "  [FAIL] $1"; }
run() { "$@" >"$MOCK_STATE/out.log" 2>&1; }
expect_ok()   { local d="$1"; shift; if run "$@"; then ok "$d"; else ko "$d"; tail -15 "$MOCK_STATE/out.log"; fi; }
expect_fail() { local d="$1"; shift; if run "$@"; then ko "$d (devait echouer)"; else ok "$d"; fi; }
where() { for x in "$MOCK_STATE"/hci-node*/"$1".xml; do [ -e "$x" ] && basename "$(dirname "$x")"; done; }
state() { cat "$MOCK_STATE/$1/$2.state"; }

echo "== Syntaxe"
for p in playbooks/[a-z]*.yml; do expect_ok "syntax-check $p" "$ANSIBLE_PLAYBOOK" --syntax-check "$p" -e vm_name=x -e dest=hci-node2; done
echo "== Image de base"
expect_ok "prepare-base (fichier local)" env x=1 "$ANSIBLE_PLAYBOOK" playbooks/prepare_base.yml -e image_file=/etc/hostname
[ -f "$MOCK_STATE/rbd/cirros-base" ] && ok "image cirros-base dans le pool" || ko "image cirros-base absente"
echo "== Creation / placement"
expect_ok "create vm1" $H create vm1 --mem 128
expect_ok "create vm2 (autre noeud par equilibrage)" $H create vm2 --disk 1G
expect_ok "create vm3 sur node3" $H create vm3 --node hci-node3 --no-start
[ "$(where vm1)" != "$(where vm2)" ] && ok "vm1 et vm2 sur des noeuds differents ($(where vm1), $(where vm2))" || ko "placement"
[ "$(where vm3)" = hci-node3 ] && [ "$(state hci-node3 vm3)" = "shut off" ] && ok "vm3 sur node3, arretee" || ko "vm3"
grep -q "<memory unit='MiB'>128</memory>" "$MOCK_STATE/$(where vm1)/vm1.xml" && ok "XML : memoire 128 MiB" || ko "XML memoire"
grep -q "name='vms/vm1'" "$MOCK_STATE/$(where vm1)/vm1.xml" && ok "XML : disque rbd vms/vm1" || ko "XML disque"
grep -q "3f1c8a52-7d4e-4b8a-9c2e-5a6b7c8d9e01" "$MOCK_STATE/$(where vm1)/vm1.xml" && ok "XML : secret ceph" || ko "XML secret"
echo "== Erreurs attendues"
expect_fail "create doublon" $H create vm1
expect_fail "nom invalide" $H create "bad name!"
expect_fail "image de base absente" $H create vm9 --image inexistante
[ -z "$(where vm9)" ] && [ ! -f "$MOCK_STATE/rbd/vm9" ] && ok "aucun residu pour vm9" || ko "residu vm9"
expect_fail "start VM inconnue" $H start nope
expect_fail "migrate vers le meme noeud" $H migrate vm1 "$(where vm1)"
expect_fail "migrate vers noeud inconnu" $H migrate vm1 hci-node9
echo "== Cycle de vie"
expect_ok "start vm3" $H start vm3
[ "$(state hci-node3 vm3)" = running ] && ok "vm3 running" || ko "vm3 non running"
expect_ok "start vm3 idempotent" $H start vm3
expect_ok "list" $H list
grep -q "vm1" "$MOCK_STATE/out.log" && ok "list affiche vm1" || ko "list sans vm1"
expect_ok "info vm1" $H info vm1
grep -q "192.168.122.50" "$MOCK_STATE/out.log" && ok "info affiche l'IP" || ko "info sans IP"
expect_ok "stop vm3" $H stop vm3
[ "$(state hci-node3 vm3)" = "shut off" ] && ok "vm3 arretee" || ko "vm3 pas arretee"
expect_ok "stop --force vm1" $H stop vm1 --force
echo "== Migration"
src=$(where vm2); dst=hci-node3; [ "$src" = hci-node3 ] && dst=hci-node1
expect_ok "migrate live vm2 $src -> $dst" $H migrate vm2 "$dst"
[ "$(where vm2)" = "$dst" ] && [ "$(state "$dst" vm2)" = running ] && ok "vm2 sur $dst et running" || ko "vm2 mal placee"
expect_ok "migrate offline vm1 (arretee)" $H migrate vm1 hci-node2
[ "$(where vm1)" = hci-node2 ] && ok "vm1 sur node2" || ko "vm1 mal placee"
echo "== Suppression"
expect_ok "delete vm2 (running)" $H delete vm2 -y
[ -z "$(where vm2)" ] && [ ! -f "$MOCK_STATE/rbd/vm2" ] && ok "vm2 et son disque supprimes" || ko "vm2 residuelle"
expect_ok "delete vm1 --keep-disk" $H delete vm1 --keep-disk -y
[ -z "$(where vm1)" ] && [ -f "$MOCK_STATE/rbd/vm1" ] && ok "vm1 supprimee, disque conserve" || ko "keep-disk"
expect_fail "delete image de base protegee" $H delete cirros-base -y
expect_ok "delete vm3" $H delete vm3 -y
echo; echo "$((n-fail))/$n tests OK"; rm -rf "$MOCK_STATE"; [ $fail -eq 0 ]
