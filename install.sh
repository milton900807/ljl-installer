#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="$(pwd)"

PODMAN_YML="$INSTALL_DIR/ljl_podman.yml"
ENV_CONFIG_JS="$INSTALL_DIR/env_config.js"
NGINX_CONFIG="$INSTALL_DIR/nginx.conf"
LJLPTX_SH="$INSTALL_DIR/ljlptx.start.sh"
LJLPTX_SHUTDOWN_SH="$INSTALL_DIR/ljlptx.shutdown.sh"
LJLUSERS_DIR="$INSTALL_DIR/ljlusers"

mkdir -p "$LJLUSERS_DIR"

echo "Installing files into: $INSTALL_DIR"
echo "User files will be stored in: $LJLUSERS_DIR"

read -r -p "Tenant ID [11111111-2222-4333-8444-555555555555]: " TENANT_ID
TENANT_ID="${TENANT_ID:-11111111-2222-4333-8444-555555555555}"

read -r -p "Client ID [aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee]: " CLIENT_ID
CLIENT_ID="${CLIENT_ID:-aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee}"

read -r -p "SharePoint host [mysharepoint.sharepoint.com]: " SHAREPOINT_HOST
SHAREPOINT_HOST="${SHAREPOINT_HOST:-mysharepoint.sharepoint.com}"

read -r -p "Theme [La Jolla Labs]: " THEME
THEME="${THEME:-La Jolla Labs}"

read -r -p "Offtarget URL [https://levenshtein.lajollalabs.com/levenshtein/]: " OFFTARGET_URL
OFFTARGET_URL="${OFFTARGET_URL:-https://levenshtein.lajollalabs.com/levenshtein/}"

read -r -p "App host [https://data.lajollalabs.com]: " APP_HOST
APP_HOST="${APP_HOST:-https://data.lajollalabs.com}"
APP_HOST="${APP_HOST%/}"

API_URL="${APP_HOST}/ionworks"
REDIRECT_URL="$APP_HOST"
POST_REDIRECT_URL="$APP_HOST"

read -r -p "Nginx server name [*.lajollalabs.com]: " NGINX_SERVER_NAME
NGINX_SERVER_NAME="${NGINX_SERVER_NAME:-*.lajollalabs.com}"

read -r -p "SSL certificate file name in this folder [ljl.crt]: " SSL_CERT_FILE
SSL_CERT_FILE="${SSL_CERT_FILE:-ljl.crt}"

read -r -p "SSL certificate key file name in this folder [ljl.key]: " SSL_KEY_FILE
SSL_KEY_FILE="${SSL_KEY_FILE:-ljl.key}"

SSL_CERT="/ljconfig/$SSL_CERT_FILE"
SSL_KEY="/ljconfig/$SSL_KEY_FILE"

cat > "$ENV_CONFIG_JS" <<EOF
(function (window) {
  window["env"] = window["env"] || {};

  window["env"]["tenant-id"] = "$TENANT_ID";
  window["env"]["clientId"] = "$CLIENT_ID";
  window["env"]["sharepoint_host"] = "$SHAREPOINT_HOST";
  window["env"]["theme"] = "$THEME";
  window["env"]["apiUrl"] = "$API_URL";
  window["env"]["appHost"] = "$APP_HOST";
  window["env"]["offtarget"] = "$OFFTARGET_URL";

  window["env"]["menu"] = [
    { "label": "Home", "path": "screen/editor" },
    { "label": "Files", "path": "screen/fb" },
    { "label": "Apps", "path": "ljl/apps" }
  ];

  window["env"]["redirectURL"] = "$REDIRECT_URL";
  window["env"]["postRedirectURL"] = "$POST_REDIRECT_URL";
  window["env"]["init"] = "/app/ljl/init.js";
  window["env"]["install"] = "ljl/dev/install-tools.js";
  window["env"]["auth"] = "b2c";
  window["env"]["canSignUp"] = true;

  window["env"]["data"] = [
    {
      "label": "RNASeq",
      "script": "ljl/data/big-data.js",
      "data": "/rnaseq",
      "server": "$API_URL"
    },
    {
      "label": "Constrained Elements",
      "script": "ljl/data/conservation-data.js",
      "data": "conservation",
      "server": "$API_URL"
    },
    {
      "label": "ClinVar",
      "script": "ljl/screens/menu/data/clinvar.js",
      "data": "clinvar",
      "server": "$API_URL"
    },
    {
      "label": "IP-DB",
      "script": "ljl/screens/menu/ip-menu.js",
      "data": "/ip",
      "server": "$API_URL"
    },
    {
      "label": "RNA-binding proteins",
      "script": "ljl/screens/menu/rna-binding-menu.js",
      "data": "/rna-binding",
      "server": "$API_URL"
    }
  ];
})(this);
EOF

cat > "$PODMAN_YML" <<EOF
services:
  ljlserver:
    image: docker.io/lajollacove/ljlserver:latest
    container_name: ljlserver
    restart: unless-stopped
    environment:
      - LJLUSERS=/root/ljusers
      - USERDATA=/root/ljusers
      - LJL_USER_DATA=/root/ljusers
    volumes:
      - ./ljlusers:/root/ljusers

  ljldataserver:
    image: docker.io/lajollacove/ljldataserver:latest
    container_name: ljldataserver
    restart: unless-stopped

  ljlsplice_acceptor:
    image: docker.io/lajollacove/ljsplice_acceptor:latest
    container_name: ljlsplice_acceptor
    restart: unless-stopped

  ljlsplice_donor:
    image: docker.io/lajollacove/ljsplice_donor:latest
    container_name: ljlsplice_donor
    restart: unless-stopped

  ljlev:
    image: docker.io/lajollacove/ljlev:latest
    container_name: ljlev
    restart: unless-stopped

  ljldb:
    image: docker.io/lajollacove/ljconfig_ljldb:latest
    container_name: ljldb
    restart: unless-stopped
    volumes:
      - ljldb_data:/var/lib/postgresql/data

  ljlptx:
    image: docker.io/lajollacove/ljlptx:latest
    container_name: ljlptx
    restart: unless-stopped
    depends_on:
      - ljlserver
      - ljldataserver
      - ljlsplice_acceptor
      - ljlsplice_donor
      - ljlev
      - ljldb
    extra_hosts:
      - "ljlserver:\${LJLSERVER_IP}"
      - "ljldataserver:\${LJLDATASERVER_IP}"
      - "ljlsplice_acceptor:\${LJLSPLICE_ACCEPTOR_IP}"
      - "ljlsplice_donor:\${LJLSPLICE_DONOR_IP}"
    volumes:
      - ./:/ljconfig:ro
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    ports:
      - "80:80"
      - "443:443"
    command: >
      sh -lc '
        set -ex;
        cp -f /ljconfig/env_config.js /eln/assets/env.js;
        nginx -t;
        exec nginx -g "daemon off;";
      '

volumes:
  ljldb_data:

networks:
  default:
    name: ljconfig_default
EOF

cat > "$NGINX_CONFIG" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $NGINX_SERVER_NAME;

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $NGINX_SERVER_NAME;

    ssl_certificate $SSL_CERT;
    ssl_certificate_key $SSL_KEY;

    error_log /var/log/nginx/error.log warn;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers on;
    ssl_ecdh_curve secp384r1;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;
    ssl_stapling off;
    ssl_stapling_verify on;

    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;

    add_header Strict-Transport-Security "max-age=63072000; includeSubdomains";
    add_header X-Frame-Options SAMEORIGIN;
    add_header X-Content-Type-Options nosniff;

    root /eln;

    proxy_connect_timeout 10s;
    proxy_send_timeout 240s;
    proxy_read_timeout 240s;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location /ln {
        if (\$http_user_agent ~* "LinkedInBot") {
            proxy_pass http://ljlserver:8080;
            break;
        }

        try_files \$uri \$uri/ /index.html;
    }

    location /ionworks/ {
        proxy_pass http://ljlserver:8080/;
        mirror_request_body on;
    }

    location /levenshtein/ {
        proxy_pass $OFFTARGET_URL;
    }

    location /ljdata/ {
        proxy_pass http://ljldataserver:1313/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
    }

    location /ljacceptor/ {
        proxy_pass http://ljlsplice_acceptor:8501/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /ljdonor/ {
        proxy_pass http://ljlsplice_donor:8502/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

cat > "$LJLPTX_SH" <<'EOF'
#!/usr/bin/env bash
set -euxo pipefail

COMPOSE_DIR="${COMPOSE_DIR:-$(pwd)}"
COMPOSE_FILE="${COMPOSE_FILE:-ljl_podman.yml}"
VENV_DIR="$COMPOSE_DIR/.venv"
MAX_LOGIN_ATTEMPTS=3

cd "$COMPOSE_DIR"

mkdir -p ./ljlusers

if ! command -v podman >/dev/null 2>&1; then
  echo "ERROR: podman is not installed."
  echo "Install it with:"
  echo "  sudo apt update"
  echo "  sudo apt install -y podman"
  exit 1
fi

if [[ ! -d "$VENV_DIR" ]]; then
  echo "Creating local Python venv: $VENV_DIR"
  python3 -m venv "$VENV_DIR"
fi

source "$VENV_DIR/bin/activate"

if ! command -v podman-compose >/dev/null 2>&1; then
  echo "Installing podman-compose into local venv..."
  python -m pip install --upgrade pip
  python -m pip install podman-compose
fi

echo "PWD=$(pwd)"
echo "USER=$USER"
echo "PATH=$PATH"

if command -v podman-compose >/dev/null 2>&1; then
  COMPOSE_CMD=(podman-compose)
elif [[ -x "$VENV_DIR/bin/podman-compose" ]]; then
  COMPOSE_CMD=("$VENV_DIR/bin/podman-compose")
elif podman compose version >/dev/null 2>&1; then
  COMPOSE_CMD=(podman compose)
else
  echo "ERROR: neither podman-compose nor podman compose is available"
  exit 1
fi

echo "Using compose command: ${COMPOSE_CMD[*]}"

TEST_IMAGE="docker.io/lajollacove/ljlserver:latest"

pull_test_image() {
  podman pull "$TEST_IMAGE"
}

dockerhub_login_with_retries() {
  local attempt=1

  while [[ "$attempt" -le "$MAX_LOGIN_ATTEMPTS" ]]; do
    echo
    echo "Docker Hub login attempt $attempt of $MAX_LOGIN_ATTEMPTS"
    podman logout docker.io >/dev/null 2>&1 || true

    read -r -p "Docker Hub username: " DOCKER_USER
    if [[ -z "$DOCKER_USER" ]]; then
      echo "ERROR: username cannot be blank"
      attempt=$((attempt + 1))
      continue
    fi

    if podman login docker.io -u "$DOCKER_USER"; then
      echo "Login accepted. Testing image pull..."

      if pull_test_image; then
        echo "Docker Hub credentials verified."
        return 0
      fi

      echo "Login succeeded, but image pull still failed."
      echo "Confirm this account has access to docker.io/lajollacove/ljlserver:latest."
    else
      echo "Docker Hub login failed."
    fi

    attempt=$((attempt + 1))
  done

  echo
  echo "ERROR: Docker Hub authentication failed after $MAX_LOGIN_ATTEMPTS attempts."
  echo "Use a Docker Hub access token as the password if 2FA is enabled."
  exit 1
}

echo "Checking Docker Hub credentials..."

set +e
pull_test_image >/tmp/ljlptx_docker_pull_test.log 2>&1
PULL_STATUS=$?
set -e

if [[ "$PULL_STATUS" -ne 0 ]]; then
  echo "Initial Docker Hub pull failed."
  cat /tmp/ljlptx_docker_pull_test.log || true
  dockerhub_login_with_retries
else
  echo "Docker Hub credentials verified."
fi

echo "Pulling images from Docker Hub..."

IMAGES=(
  "docker.io/lajollacove/ljlserver:latest"
  "docker.io/lajollacove/ljldataserver:latest"
  "docker.io/lajollacove/ljsplice_acceptor:latest"
  "docker.io/lajollacove/ljsplice_donor:latest"
  "docker.io/lajollacove/ljlev:latest"
  "docker.io/lajollacove/ljconfig_ljldb:latest"
  "docker.io/lajollacove/ljlptx:latest"
)

for image in "${IMAGES[@]}"; do
  echo "Pulling $image..."

  if ! podman pull "$image"; then
    echo
    echo "Pull failed for $image."
    dockerhub_login_with_retries
    podman pull "$image"
  fi
done

echo "Cleaning up old containers and pods..."

podman rm -f \
  ljlptx \
  ljlserver \
  ljldataserver \
  ljlsplice_acceptor \
  ljlsplice_donor \
  ljlev \
  ljldb \
  ljconf_ljlptx_1 \
  ljconf_ljlserver_1 \
  ljconf_ljldataserver_1 \
  ljconf_ljlsplice_acceptor_1 \
  ljconf_ljlsplice_donor_1 \
  ljconf_ljlev_1 \
  ljconf_ljldb_1 \
  ljconfig_ljlptx_1 \
  ljconfig_ljlserver_1 \
  ljconfig_ljldataserver_1 \
  ljconfig_ljlsplice_acceptor_1 \
  ljconfig_ljlsplice_donor_1 \
  ljconfig_ljlev_1 \
  ljconfig_ljldb_1 \
  2>/dev/null || true

podman pod rm -f ljconf 2>/dev/null || true
podman pod rm -f ljconfig 2>/dev/null || true
podman pod rm -f ljconfig_default 2>/dev/null || true
podman pod rm -f pod_ljconfig_default 2>/dev/null || true

rm -f "$HOME/.config/cni/net.d/ljconfig_default.conflist" 2>/dev/null || true

echo "Starting upstream services first..."
"${COMPOSE_CMD[@]}" -f "./$COMPOSE_FILE" up -d \
  ljlserver \
  ljldataserver \
  ljlsplice_acceptor \
  ljlsplice_donor \
  ljlev \
  ljldb

sleep 5

get_ip() {
  local name="$1"
  podman inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$name" 2>/dev/null || true
}

export LJLSERVER_IP="$(get_ip ljlserver)"
export LJLDATASERVER_IP="$(get_ip ljldataserver)"
export LJLSPLICE_ACCEPTOR_IP="$(get_ip ljlsplice_acceptor)"
export LJLSPLICE_DONOR_IP="$(get_ip ljlsplice_donor)"

echo "Resolved IPs:"
echo "  LJLSERVER_IP=$LJLSERVER_IP"
echo "  LJLDATASERVER_IP=$LJLDATASERVER_IP"
echo "  LJLSPLICE_ACCEPTOR_IP=$LJLSPLICE_ACCEPTOR_IP"
echo "  LJLSPLICE_DONOR_IP=$LJLSPLICE_DONOR_IP"

if [[ -z "$LJLSERVER_IP" || -z "$LJLDATASERVER_IP" || -z "$LJLSPLICE_ACCEPTOR_IP" || -z "$LJLSPLICE_DONOR_IP" ]]; then
  echo "ERROR: one or more upstream IPs are blank"
  podman ps -a
  exit 1
fi

echo "Starting ljlptx with extra_hosts..."
"${COMPOSE_CMD[@]}" -f "./$COMPOSE_FILE" up -d ljlptx

echo "Final container state:"
podman ps -a

echo "ljlptx logs:"
podman logs --tail 100 ljlptx 2>/dev/null || true

echo
echo "User files should persist under:"
echo "  $(pwd)/ljlusers"
EOF

cat > "$LJLPTX_SHUTDOWN_SH" <<'EOF'
#!/usr/bin/env bash
set -euxo pipefail

COMPOSE_DIR="${COMPOSE_DIR:-$(pwd)}"
COMPOSE_FILE="${COMPOSE_FILE:-ljl_podman.yml}"
VENV_DIR="$COMPOSE_DIR/.venv"

cd "$COMPOSE_DIR"

if [[ -f "$VENV_DIR/bin/activate" ]]; then
  source "$VENV_DIR/bin/activate"
fi

if command -v podman-compose >/dev/null 2>&1; then
  COMPOSE_CMD=(podman-compose)
elif [[ -x "$VENV_DIR/bin/podman-compose" ]]; then
  COMPOSE_CMD=("$VENV_DIR/bin/podman-compose")
elif podman compose version >/dev/null 2>&1; then
  COMPOSE_CMD=(podman compose)
else
  echo "ERROR: neither podman-compose nor podman compose is available"
  exit 1
fi

echo "Stopping ljlptx stack..."
"${COMPOSE_CMD[@]}" -f "./$COMPOSE_FILE" down || true

echo "Removing old containers and pods..."
podman rm -f \
  ljlptx \
  ljlserver \
  ljldataserver \
  ljlsplice_acceptor \
  ljlsplice_donor \
  ljlev \
  ljldb \
  ljconf_ljlptx_1 \
  ljconf_ljlserver_1 \
  ljconf_ljldataserver_1 \
  ljconf_ljlsplice_acceptor_1 \
  ljconf_ljlsplice_donor_1 \
  ljconf_ljlev_1 \
  ljconf_ljldb_1 \
  ljconfig_ljlptx_1 \
  ljconfig_ljlserver_1 \
  ljconfig_ljldataserver_1 \
  ljconfig_ljlsplice_acceptor_1 \
  ljconfig_ljlsplice_donor_1 \
  ljconfig_ljlev_1 \
  ljconfig_ljldb_1 \
  2>/dev/null || true

podman pod rm -f ljconf 2>/dev/null || true
podman pod rm -f ljconfig 2>/dev/null || true
podman pod rm -f ljconfig_default 2>/dev/null || true
podman pod rm -f pod_ljconfig_default 2>/dev/null || true

rm -f "$HOME/.config/cni/net.d/ljconfig_default.conflist" 2>/dev/null || true

echo "Final container state:"
podman ps -a

echo
echo "User files are preserved under:"
echo "  $(pwd)/ljlusers"
EOF

chmod 644 "$ENV_CONFIG_JS" "$PODMAN_YML" "$NGINX_CONFIG"
chmod 755 "$LJLPTX_SH" "$LJLPTX_SHUTDOWN_SH"

echo
echo "Installed:"
echo "  $PODMAN_YML"
echo "  $ENV_CONFIG_JS"
echo "  $NGINX_CONFIG"
echo "  $LJLPTX_SH"
echo "  $LJLPTX_SHUTDOWN_SH"
echo "  $LJLUSERS_DIR"

echo
echo "Run with:"
echo "  ./ljlptx.start.sh"

echo
echo "Shutdown with:"
echo "  ./ljlptx.shutdown.sh"
