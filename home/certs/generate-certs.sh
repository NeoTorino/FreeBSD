#!/usr/local/bin/zsh

# Set filenames
CA_KEY="my-ca.key"
CA_CERT="my-ca.crt"
CA_SERIAL="my-ca.srl"

ENTITY_KEY="entity.key"
ENTITY_CSR="entity.csr"
ENTITY_CERT="entity.crt"
CERT_EXT="cert_ext.cnf"

# Subject details
CA_SUBJ="/C=US/ST=CA/L=SanFrancisco/O=MyOrg/OU=IT/CN=MyRootCA"
ENTITY_SUBJ="/C=US/ST=CA/L=SanFrancisco/O=MyOrg/OU=Dev/CN=mydomain.local"

echo "==> Generating CA private key..."
openssl genrsa -out $CA_KEY 4096
chmod 600 $CA_KEY

echo "==> Generating self-signed CA certificate..."
openssl req -x509 -new -nodes -key $CA_KEY -sha256 -days 3650 -out $CA_CERT -subj "$CA_SUBJ"
chmod 644 $CA_CERT

echo "==> Generating entity private key..."
openssl genrsa -out $ENTITY_KEY 2048
chmod 600 $ENTITY_KEY

echo "==> Generating certificate signing request (CSR)..."
openssl req -new -key $ENTITY_KEY -out $ENTITY_CSR -subj "$ENTITY_SUBJ"
chmod 644 $ENTITY_CSR

echo "==> Creating certificate extension file..."
cat > $CERT_EXT <<EOF
basicConstraints = CA:FALSE
subjectAltName = @alt_names
[alt_names]
DNS.1 = mydomain.local
EOF
chmod 600 $CERT_EXT

echo "==> Signing entity CSR with CA..."
openssl x509 -req -in $ENTITY_CSR -CA $CA_CERT -CAkey $CA_KEY -CAcreateserial \
  -out $ENTITY_CERT -days 825 -sha256 -extfile $CERT_EXT
chmod 644 $ENTITY_CERT
chmod 600 $CA_SERIAL

echo "==> Cleaning up extension file..."
rm -f $CERT_EXT

echo "✅ Done."
echo "Generated files:"
echo "  CA:        $CA_KEY (600), $CA_CERT (644), $CA_SERIAL (600)"
echo "  Entity:    $ENTITY_KEY (600), $ENTITY_CSR (644), $ENTITY_CERT (644)"

