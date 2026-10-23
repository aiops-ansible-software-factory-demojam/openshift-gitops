# Read-only package access and public signing trust, never production access.
if [ -r /mnt/secrets/invoice/material.json ]; then
  export INVOICE_MATERIAL_FILE=/mnt/secrets/invoice/material.json
  export INVOICE_SIGNING_KEY_FILE=/mnt/secrets/invoice/signing-key.pem
fi
