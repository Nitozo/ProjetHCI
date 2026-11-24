#!/usr/bin/env bash
# hcictl.sh - gestion des VM de la HCI (KVM/libvirt + Ceph) via Ansible
set -euo pipefail
cd "$(dirname "$0")"
PB=playbooks
ANSIBLE="${ANSIBLE_PLAYBOOK:-ansible-playbook}"

usage() {
  cat <<USAGE
Usage : $0 <commande> [arguments]

  create <nom> [--mem MiB] [--vcpus N] [--disk 2G] [--node hci-nodeX] [--image base] [--no-start]
  start   <nom>
  stop    <nom> [--force]
  delete  <nom> [--keep-disk] [-y]
  migrate <nom> <noeud-destination>
  list
  info    <nom>
  prepare-base [--node hci-nodeX] [--image nom] [--url URL]
  ping                      teste la connexion Ansible vers les 3 noeuds
USAGE
  exit "${1:-1}"
}

[ $# -ge 1 ] || usage
cmd="$1"; shift
EXTRA=()
need_name() {
  [ $# -ge 1 ] || { echo "Erreur : nom de VM manquant" >&2; usage; }
  [[ "$1" =~ ^[A-Za-z][A-Za-z0-9_-]{0,31}$ ]] || { echo "Erreur : nom de VM invalide '$1' (lettres, chiffres, - et _ ; 32 max)" >&2; exit 1; }
}

case "$cmd" in
  create)
    need_name "$@"; name="$1"; shift
    EXTRA+=(-e "vm_name=$name")
    while [ $# -gt 0 ]; do
      case "$1" in
        --mem)      EXTRA+=(-e "vm_memory_mib=$2"); shift 2 ;;
        --vcpus)    EXTRA+=(-e "vm_vcpus=$2"); shift 2 ;;
        --disk)     EXTRA+=(-e "vm_disk_size=$2"); shift 2 ;;
        --node)     EXTRA+=(-e "node=$2"); shift 2 ;;
        --image)    EXTRA+=(-e "base_image=$2"); shift 2 ;;
        --no-start) EXTRA+=(-e "start_after_create=false"); shift ;;
        *) echo "Option inconnue : $1" >&2; usage ;;
      esac
    done
    exec "$ANSIBLE" "$PB/create_vm.yml" "${EXTRA[@]}" ;;
  start)
    need_name "$@"; exec "$ANSIBLE" "$PB/start_vm.yml" -e "vm_name=$1" ;;
  stop)
    need_name "$@"; name="$1"; shift
    [ "${1:-}" = "--force" ] && EXTRA+=(-e "force=true")
    exec "$ANSIBLE" "$PB/stop_vm.yml" -e "vm_name=$name" "${EXTRA[@]}" ;;
  delete)
    need_name "$@"; name="$1"; shift; yes=0
    for a in "$@"; do
      case "$a" in
        --keep-disk) EXTRA+=(-e "keep_disk=true") ;;
        -y|--yes) yes=1 ;;
        *) echo "Option inconnue : $a" >&2; usage ;;
      esac
    done
    if [ "$yes" -eq 0 ]; then
      read -r -p "Supprimer definitivement la VM '$name' ? [o/N] " rep
      [[ "$rep" =~ ^[oOyY]$ ]] || { echo "Annule."; exit 0; }
    fi
    exec "$ANSIBLE" "$PB/delete_vm.yml" -e "vm_name=$name" "${EXTRA[@]}" ;;
  migrate)
    [ $# -ge 2 ] || { echo "Usage : $0 migrate <nom> <noeud-destination>" >&2; exit 1; }
    need_name "$@"
    exec "$ANSIBLE" "$PB/migrate_vm.yml" -e "vm_name=$1" -e "dest=$2" ;;
  list)
    exec "$ANSIBLE" "$PB/list_vms.yml" ;;
  info)
    need_name "$@"; exec "$ANSIBLE" "$PB/info_vm.yml" -e "vm_name=$1" ;;
  prepare-base)
    while [ $# -gt 0 ]; do
      case "$1" in
        --node)  EXTRA+=(-e "node=$2"); shift 2 ;;
        --image) EXTRA+=(-e "base_image=$2"); shift 2 ;;
        --url)   EXTRA+=(-e "base_image_url=$2"); shift 2 ;;
        *) echo "Option inconnue : $1" >&2; usage ;;
      esac
    done
    exec "$ANSIBLE" "$PB/prepare_base.yml" "${EXTRA[@]}" ;;
  ping)
    exec "${ANSIBLE%-playbook}" hci -m ping ;;
  -h|--help|help) usage 0 ;;
  *) echo "Commande inconnue : $cmd" >&2; usage ;;
esac
