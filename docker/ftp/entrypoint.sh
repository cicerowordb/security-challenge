#!/usr/bin/env bash
set -euo pipefail

CREDENTIALS_FILE="${CREDENTIALS_FILE:-/run/credentials.txt}"

if [[ ! -r "$CREDENTIALS_FILE" ]]; then
  echo "Arquivo de credenciais nao encontrado: $CREDENTIALS_FILE" >&2
  exit 1
fi

while IFS=: read -r user pass; do
  [[ -z "${user:-}" ]] && continue
  [[ "$user" == \#* ]] && continue

  if id "$user" >/dev/null 2>&1; then
    if [[ "$user" == "root" ]]; then
      home="/root"
    else
      home="/home/$user"
    fi
    usermod -d "$home" -s /bin/bash "$user"
  else
    home="/home/$user"
    if getent group "$user" >/dev/null 2>&1; then
      useradd -m -d "$home" -s /bin/bash -g "$user" "$user"
    else
      useradd -m -d "$home" -s /bin/bash "$user"
    fi
  fi

  mkdir -p "$home"
  chown "$user" "$home"
  printf '%s:%s\n' "$user" "$pass" | chpasswd -c SHA512
  echo "Usuario FTP configurado: $user"
done < "$CREDENTIALS_FILE"

mkdir -p /var/run/vsftpd/empty
chmod 0555 /var/run/vsftpd/empty

if [[ -f /etc/pam.d/common-auth ]] && ! grep -q 'pam_unix\.so.*nodelay' /etc/pam.d/common-auth; then
  sed -i 's/^\(auth[[:space:]].*pam_unix\.so.*\)$/\1 nodelay/' /etc/pam.d/common-auth
fi

/usr/sbin/vsftpd /etc/vsftpd.conf &
VSFTPD_PID=$!

trap 'kill "$VSFTPD_PID" 2>/dev/null || true' TERM INT
wait "$VSFTPD_PID"
