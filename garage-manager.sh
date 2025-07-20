#!/bin/bash
# Garage Manager with Docker Compose - Full Features, Cleaned

CONFIG_FILE="garage.toml"
DATA_DIR="garage"
COMPOSE_FILE="docker-compose.yml"
CONTAINER_NAME="garage"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
pause() { echo -e "${YELLOW}Press any key to continue...${NC}"; read -n 1 -s; }

check_requirements() {
  command -v docker-compose &>/dev/null || { error "docker-compose not installed"; exit 1; }
}

generate_compose_file() {
  mkdir -p ${DATA_DIR}/meta ${DATA_DIR}/data

  cat > ${COMPOSE_FILE} <<EOF
version: "3"
services:
  garage:
    container_name: ${CONTAINER_NAME}
    image: dxflrs/garage:latest
    ports:
      - 39300:3900
      - 39301:3901
      - 39302:3902
      - 39303:3903
      - 39304:3904
    volumes:
      - ./garage.toml:/etc/garage.toml
      - ./garage/meta:/var/lib/garage/meta:rw
      - ./garage/data:/var/lib/garage/data:rw
    environment:
      RUST_LOG: garage=debug
EOF

  log "docker-compose.yml generated."
}

generate_config() {
  cat > ${CONFIG_FILE} <<EOF
metadata_dir = "/var/lib/garage/meta"
data_dir = "/var/lib/garage/data"
db_engine = "sqlite"
replication_factor = 1

rpc_bind_addr = "[::]:3901"
rpc_public_addr = "127.0.0.1:3901"
rpc_secret = "$(openssl rand -hex 32)"

[s3_api]
s3_region = "garage"
api_bind_addr = "[::]:3900"
root_domain = ".s3.garage.localhost"

[s3_web]
bind_addr = "[::]:3902"
root_domain = ".web.garage.localhost"
index = "index.html"

[k2v_api]
api_bind_addr = "[::]:3904"

[admin]
api_bind_addr = "[::]:3903"
admin_token = "$(openssl rand -base64 32)"
metrics_token = "$(openssl rand -base64 32)"
EOF

  log "garage.toml created."
}

compose_up() {
  sudo docker compose up -d --build && log "Services started." || error "Startup failed."
}

compose_down() {
  sudo docker compose down && log "Services stopped." || error "Stop failed."
}

garage_exec() {
  docker exec ${CONTAINER_NAME} /usr/local/bin/garage "$@"
}

configure_cluster() {
  NODE_ID=$(garage_exec node id | head -n1 | tr -d '\r\n')
  [[ -z "$NODE_ID" ]] && { error "Failed to get Node ID"; return 1; }
  garage_exec layout assign "$NODE_ID" -z dc1 -c 1000
  sleep 1
  garage_exec layout apply --version 1
  log "Cluster configured (Node ID: $NODE_ID)"
}

show_access_info() {
  echo -e "${BLUE}Access Points:${NC}"
  echo "S3 API:     http://localhost:39300"
  echo "Admin API:  http://localhost:39303"
  echo "Web API:    http://localhost:39302"
  echo "K2V API:    http://localhost:39304"
}

main_setup() {
  [[ ! -f ${COMPOSE_FILE} ]] && generate_compose_file
  [[ ! -f ${CONFIG_FILE} ]] && generate_config
  compose_up
  sleep 5
  configure_cluster
  show_access_info
  pause
}

show_status() {
  docker-compose ps
  echo -e "${CYAN}Cluster Status:${NC}"
  garage_exec status
  pause
}

show_logs() {
  docker-compose logs --tail=50 ${CONTAINER_NAME}
  pause
}

create_bucket() {
  echo -ne "Enter bucket name: "; read name
  garage_exec bucket create "$name"
  pause
}

create_key() {
  echo -ne "Enter key name: "; read name
  garage_exec key new --name "$name"
  pause
}

allow_bucket_access() {
  echo -ne "Bucket name: "; read bucket
  echo -ne "Key name: "; read key
  garage_exec bucket allow "$bucket" --read --write --key "$key"
  pause
}

list_buckets() {
  garage_exec bucket list
  pause
}

list_keys() {
  garage_exec key list
  pause
}

key_info() {
  echo -ne "Enter key name: "; read name
  garage_exec key info "$name"
  pause
}

cleanup_all() {
  compose_down
  rm -rf ${CONFIG_FILE} ${COMPOSE_FILE} ${DATA_DIR}
  log "Cleanup complete."
  pause
}

menu() {
  while true; do
    clear
    echo -e "${CYAN}Garage Manager (Compose-based)${NC}"
    echo "1) Setup Garage"
    echo "2) Start Services"
    echo "3) Stop Services"
    echo "4) Restart Services"
    echo "5) Show Status"
    echo "6) View Logs"
    echo "7) Create Bucket"
    echo "8) Create Access Key"
    echo "9) Allow Key Access to Bucket"
    echo "10) List Buckets"
    echo "11) List Keys"
    echo "12) Show Key Info"
    echo "13) Cleanup Everything"
    echo "0) Exit"
    echo -ne "${YELLOW}Choose option: ${NC}"
    read opt
    case $opt in
      1) main_setup ;;
      2) compose_up; pause ;;
      3) compose_down; pause ;;
      4) compose_down && compose_up; pause ;;
      5) show_status ;;
      6) show_logs ;;
      7) create_bucket ;;
      8) create_key ;;
      9) allow_bucket_access ;;
      10) list_buckets ;;
      11) list_keys ;;
      12) key_info ;;
      13) cleanup_all ;;
      0) exit 0 ;;
      *) warn "Invalid option"; pause ;;
    esac
  done
}

check_requirements
menu
