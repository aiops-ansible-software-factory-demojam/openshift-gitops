# shellcheck shell=sh
# The ADT image permits passwd updates for OpenShift's arbitrary runtime UID.
# OpenSSH and Ansible need that UID to resolve to a user and HOME directory.
if ! getent passwd "$(id -u)" >/dev/null; then
  (
    flock -x 9
    if ! getent passwd "$(id -u)" >/dev/null; then
      printf 'sandbox-%s:x:%s:%s:Omnigent sandbox:%s:/bin/bash\n' \
        "$(id -u)" "$(id -u)" "$(id -g)" "$HOME" >&9
    fi
  ) 9>>/etc/passwd
fi
