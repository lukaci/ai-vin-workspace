#!/usr/bin/env bash
# Monta in sola lettura il bucket S3 della cache in .s3/ (remote rclone "ai-vin").
# Uso: s3-mount.sh mount | start | umount
#   mount  resta in primo piano e smonta alla chiusura del terminale (usato dal task di VS Code)
#   start  monta in background e ritorna subito; resta montato fino a "umount"
set -euo pipefail

REMOTE="ai-vin:ai-vin-service-cache-iurxvp"
MOUNT_DIR="$(cd "$(dirname "$0")/.." && pwd)/.s3"
RCLONE_OPTS=(--read-only --use-server-modtime)

is_mounted() { findmnt -n "$MOUNT_DIR" >/dev/null 2>&1; }

do_umount() {
  if is_mounted; then
    fusermount3 -u "$MOUNT_DIR" 2>/dev/null || fusermount3 -uz "$MOUNT_DIR"
    echo "[s3] smontato $MOUNT_DIR"
  else
    echo "[s3] $MOUNT_DIR non è montato"
  fi
}

# Esce con 1 se il bucket è già montato, altrimenti prepara il punto di mount.
prepare() {
  if is_mounted; then
    if ls "$MOUNT_DIR" >/dev/null 2>&1; then
      echo "[s3] $MOUNT_DIR è già montato"
      return 1
    fi
    # mount rimasto appeso dopo la morte di rclone
    fusermount3 -uz "$MOUNT_DIR"
  fi
  mkdir -p "$MOUNT_DIR"
}

do_mount() {
  prepare || return 0
  # alla chiusura del terminale (SIGHUP) rclone non termina da solo: smontiamo noi
  trap do_umount EXIT
  trap 'exit 0' HUP INT TERM

  echo "[s3] monto $REMOTE in $MOUNT_DIR (sola lettura)"
  rclone mount "$REMOTE" "$MOUNT_DIR" "${RCLONE_OPTS[@]}" &
  wait $!
}

do_start() {
  prepare || return 0
  rclone mount "$REMOTE" "$MOUNT_DIR" "${RCLONE_OPTS[@]}" --daemon
  echo "[s3] montato in background $REMOTE in $MOUNT_DIR (sola lettura); per smontare: $0 umount"
}

case "${1:-mount}" in
  mount) do_mount ;;
  start) do_start ;;
  umount) do_umount ;;
  *) echo "Uso: $0 mount | start | umount" >&2; exit 2 ;;
esac
