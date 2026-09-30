# shellcheck shell=sh
# Omnigent mounts the dedicated test identity only on the main host container.
# The init container and local image development do not need test credentials.
if [ -r /mnt/secrets/molecule/token ] && [ -r /mnt/secrets/molecule/ca.crt ]; then
  (
    umask 077
    molecule_config_dir="${HOME}/.config/molecule"
    mkdir -p "$molecule_config_dir"
    chmod 700 "$molecule_config_dir"
    molecule_config_tmp=$(mktemp "$molecule_config_dir/kubeconfig.XXXXXX")
    # Refer to mounted files, so no token is copied into HOME or shell variables.
    cat >"$molecule_config_tmp" <<'CONFIG'
apiVersion: v1
kind: Config
clusters:
  - name: demo
    cluster:
      server: https://kubernetes.default.svc
      certificate-authority: /mnt/secrets/molecule/ca.crt
users:
  - name: molecule-provisioner
    user:
      tokenFile: /mnt/secrets/molecule/token
contexts:
  - name: molecule-tests
    context:
      cluster: demo
      user: molecule-provisioner
      namespace: molecule-tests
current-context: molecule-tests
CONFIG
    mv -f "$molecule_config_tmp" "$molecule_config_dir/kubeconfig"
  ) && export KUBECONFIG="${HOME}/.config/molecule/kubeconfig"
fi
