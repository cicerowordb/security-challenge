#!/usr/bin/env bash
set -euo pipefail

CREDENTIALS_FILE="${CREDENTIALS_FILE:-/run/credentials.txt}"

if [[ ! -r "$CREDENTIALS_FILE" ]]; then
  echo "Arquivo de credenciais nao encontrado: $CREDENTIALS_FILE" >&2
  exit 1
fi

groupadd -f smbusers
mkdir -p /srv/smb/labshare
chown root:smbusers /srv/smb/labshare
chmod 2770 /srv/smb/labshare

while IFS=: read -r user pass; do
  [[ -z "${user:-}" ]] && continue
  [[ "$user" == \#* ]] && continue

  if ! id "$user" >/dev/null 2>&1; then
    useradd -M -s /usr/sbin/nologin -N "$user"
  fi

  usermod -aG smbusers "$user"
  printf '%s\n%s\n' "$pass" "$pass" | smbpasswd -s -a "$user" >/dev/null
  smbpasswd -e "$user" >/dev/null
  echo "Usuario SMB configurado: $user"
done < "$CREDENTIALS_FILE"

mkdir -p /var/log/samba /var/lib/samba/private /run/samba

smbd --foreground --no-process-group &
SMBD_PID=$!
nmbd --foreground --no-process-group &
NMBD_PID=$!

trap 'kill "$SMBD_PID" "$NMBD_PID" 2>/dev/null || true' TERM INT
wait -n "$SMBD_PID" "$NMBD_PID"
