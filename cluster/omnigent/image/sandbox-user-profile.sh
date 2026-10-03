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

# HOME is mounted empty for each sandbox. Seed only a new cache, preserving
# environments and collection versions installed by an existing session.
if [ -d /opt/demo-dev ]; then
  sandbox_pre_commit_home=${PRE_COMMIT_HOME:-$HOME/.cache/pre-commit}
  if [ ! -e "$sandbox_pre_commit_home/db.db" ]; then
    mkdir -p "$sandbox_pre_commit_home"
    cp /opt/demo-dev/pre-commit/db.db "$sandbox_pre_commit_home/db.db"
  fi
  if [ ! -d "$HOME/.ansible/collections/ansible_collections" ]; then
    mkdir -p "$HOME/.ansible/collections"
    cp -R /opt/demo-dev/collections/ansible_collections "$HOME/.ansible/collections/"
  fi
  unset sandbox_pre_commit_home
fi
