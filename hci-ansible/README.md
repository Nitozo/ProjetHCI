# hci-ansible : gestion des VM de la HCI (KVM/libvirt + Ceph RBD)

Automatisation Ansible du cycle de vie des VM sur les 3 noeuds (hci-node1/2/3).
A lancer depuis **hci-node1** (noeud de controle).

## Prerequis (une seule fois, sur hci-node1)
    sudo apt install -y ansible
    # hci-node1 doit pouvoir se connecter en SSH a lui-meme et aux autres sans mot de passe :
    ssh-copy-id -o StrictHostKeyChecking=accept-new esgi@hci-node1
    ./hcictl.sh ping

## Commandes (hcictl.sh)
| Action | Commande |
|---|---|
| Importer l'image modele CirrOS dans Ceph | `./hcictl.sh prepare-base` |
| Creer (+demarrer) une VM | `./hcictl.sh create web1 [--mem 256] [--vcpus 1] [--disk 2G] [--node hci-node2]` |
| Demarrer | `./hcictl.sh start web1` |
| Arreter (ACPI / brutal) | `./hcictl.sh stop web1 [--force]` |
| Migrer a chaud | `./hcictl.sh migrate web1 hci-node3` |
| Lister toutes les VM du cluster | `./hcictl.sh list` |
| Infos d'une VM (etat, IP, disques, image Ceph) | `./hcictl.sh info web1` |
| Supprimer (VM + disque Ceph) | `./hcictl.sh delete web1 [--keep-disk] [-y]` |

Sans `--node`, `create` place la VM sur le noeud qui porte le moins de VM en marche.

## Fonctionnement
- Le disque de chaque VM est une image RBD `vms/<nom>` copiee depuis `vms/cirros-base`.
- La VM est declaree dans libvirt via `templates/domain.xml.j2` (disque `network` rbd, secret `client.libvirt`).
  (Le pool de stockage libvirt RBD n'est pas utilise : incompatibilite libvirt 9.0 / Ceph 19.)
- Chaque playbook interroge d'abord les 3 noeuds pour retrouver ou se trouve la VM (`_discover.yml`).
- Migration : `virsh migrate --live --persistent --undefinesource` via qemu+ssh ; pas de copie de disque (Ceph partage).
- Les parametres par defaut sont dans `inventory/group_vars/all.yml`.

## Tests sans cluster
    ANSIBLE_PLAYBOOK=ansible-playbook bash tests/run_tests.sh
Utilise des faux `virsh`/`rbd`/`qemu-img` (tests/mock) : 45 verifications (creation, placement, migration, erreurs, suppression).
