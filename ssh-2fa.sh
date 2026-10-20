#!/usr/bin/env bash
# ssh-2fa.sh: SSH TOTP 2FA for Debian and Ubuntu (Debian 12+, Ubuntu 22.04+)
# Usage: ./ssh-2fa.sh install | backup | uninstall
set -euo pipefail

[ "$(id -u)" -ne 0 ] || { echo "Run as your normal user, not root."; exit 1; }

DROPIN=/etc/ssh/sshd_config.d/10-2fa.conf
PAM=/etc/pam.d/sshd
SECRET="$HOME/.google_authenticator"
BACKUP="$HOME/2fa-backup"

restart_ssh() { sudo sshd -t && sudo systemctl restart ssh; }

do_backup() {
  [ -f "$SECRET" ] || { echo "No 2FA secret found. Run install first."; exit 1; }
  command -v qrencode >/dev/null || sudo apt install -y qrencode
  mkdir -p "$BACKUP"
  chmod 700 "$BACKUP"
  cp "$SECRET" "$BACKUP/google_authenticator"
  qrencode -o "$BACKUP/qr.png" \
    "otpauth://totp/$USER@$(hostname)?secret=$(head -n1 "$SECRET")&issuer=$(hostname)"
  chmod 600 "$BACKUP"/*
  echo "Backup saved in $BACKUP (qr.png, secret, emergency codes)."
  echo "Copy it off the Pi, then delete it from here if you like:"
  echo "  scp -r $USER@$(hostname):2fa-backup ."
}

do_install() {
  sudo apt update
  sudo apt install -y libpam-google-authenticator qrencode

  # Enroll current user: shows QR code and emergency codes
  google-authenticator -t -d -f -r 3 -R 30 -w 3 -C
  do_backup

  # PAM: ask for the code after the password
  grep -q pam_google_authenticator "$PAM" || \
    sudo sed -i '/@include common-auth/a auth required pam_google_authenticator.so' "$PAM"

  # sshd: password + TOTP via keyboard-interactive
  sudo tee "$DROPIN" >/dev/null <<'EOF'
UsePAM yes
KbdInteractiveAuthentication yes
PasswordAuthentication no
AuthenticationMethods keyboard-interactive
EOF

  restart_ssh
  echo "Done. Test a new SSH login in a second terminal before closing this one."
}

do_uninstall() {
  # Undo config first, then remove the package, so logins never break
  sudo rm -f "$DROPIN"
  sudo sed -i '/pam_google_authenticator/d' "$PAM"
  restart_ssh
  sudo apt remove -y libpam-google-authenticator qrencode
  rm -rf "$SECRET" "$BACKUP"
  echo "2FA removed. SSH is back to password login."
}

case "${1:-}" in
  install)   do_install ;;
  backup)    do_backup ;;
  uninstall) do_uninstall ;;
  *) echo "Usage: $0 install | backup | uninstall"; exit 1 ;;
esac
