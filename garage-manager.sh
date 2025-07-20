#!/bin/bash
# Garage S3 Server Management Script - Interactive Menu
# Usage: ./garage-manager.sh

CONTAINER_NAME="garaged"
CONFIG_FILE="garage.toml"
DATA_DIR="garage"
DEFAULT_PORTS="3900:3900 3901:3901 3902:3902 3903:3903 3904:3904"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_banner() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           ${CYAN}GARAGE S3 SERVER MANAGER${BLUE}           ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"
    echo ""
}

show_menu() {
    echo -e "${PURPLE}┌─────────────────────────────────────────────┐${NC}"
    echo -e "${PURPLE}│                MAIN MENU                    │${NC}"
    echo -e "${PURPLE}├─────────────────────────────────────────────┤${NC}"
    echo -e "${PURPLE}│${NC} ${CYAN}1.${NC} Setup Garage Server                    ${PURPLE}│${NC}"
    echo -e "${PURPLE}│${NC} ${CYAN}2.${NC} Start Container                        ${PURPLE}│${NC}"
    echo -e "${PURPLE}│${NC} ${CYAN}3.${NC} Stop Container                         ${PURPLE}│${NC}"
    echo -e "${PURPLE}│${NC} ${CYAN}4.${NC} Restart Container                      ${PURPLE}│${NC}"
    echo -e "${PURPLE}│${NC} ${CYAN}5.${NC} Show Status                            ${PURPLE}│${NC}"
    echo -e "${PURPLE}│${NC} ${CYAN}6.${NC} View Logs                              ${PURPLE}│${NC}"
    echo -e "${PURPLE}├─────────────────────────────────────────────┤${NC}"
    echo -e "${PURPLE}│${NC} ${CYAN}7.${NC} Create Bucket                          ${PURPLE}│${NC}"
    echo -e "${PURPLE}│${NC} ${CYAN}8.${NC} Create Access Key                      ${PURPLE}│${NC}"
    echo -e "${PURPLE}│${NC} ${CYAN}9.${NC} Allow Key to Access Bucket             ${PURPLE}│${NC}"
    echo -e "${PURPLE}│${NC} ${CYAN}10.${NC} List Buckets                          ${PURPLE}│${NC}"
    echo -e "${PURPLE}│${NC} ${CYAN}11.${NC} List Keys                             ${PURPLE}│${NC}"
    echo -e "${PURPLE}│${NC} ${CYAN}12.${NC} Show Key Information                  ${PURPLE}│${NC}"
    echo -e "${PURPLE}├─────────────────────────────────────────────┤${NC}"
    echo -e "${PURPLE}│${NC} ${CYAN}13.${NC} Change Port Mappings                  ${PURPLE}│${NC}"
    echo -e "${PURPLE}│${NC} ${CYAN}14.${NC} Open Container Shell                  ${PURPLE}│${NC}"
    echo -e "${PURPLE}│${NC} ${CYAN}15.${NC} Remove Container Only                 ${PURPLE}│${NC}"
    echo -e "${PURPLE}│${NC} ${CYAN}16.${NC} Complete Cleanup (Remove All)        ${PURPLE}│${NC}"
    echo -e "${PURPLE}│${NC} ${CYAN}17.${NC} Troubleshoot Container                ${PURPLE}│${NC}"
    echo -e "${PURPLE}├─────────────────────────────────────────────┤${NC}"
    echo -e "${PURPLE}│${NC} ${CYAN}0.${NC} Exit                                   ${PURPLE}│${NC}"
    echo -e "${PURPLE}└─────────────────────────────────────────────┘${NC}"
    echo ""
}

pause() {
    echo ""
    echo -e "${YELLOW}Press any key to continue...${NC}"
    read -n 1 -s
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed or not in PATH"
        pause
        return 1
    fi
    return 0
}

container_exists() {
    sudo docker ps -a --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"
}

container_running() {
    sudo docker ps --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"
}

# Execute garage commands with proper shell and error handling
garage_exec() {
    local cmd="$1"
    
    log "Executing: garage $cmd"
    
    # Try different shell options and garage paths
    local shells=("/bin/sh" "/bin/bash" "/bin/ash" "sh" "bash")
    local garage_paths=("/usr/local/bin/garage" "/garage" "/usr/bin/garage" "/opt/garage/garage" "garage")
    
    # First, let's check what shell is available
    local available_shell=""
    for shell in "${shells[@]}"; do
        if sudo docker exec ${CONTAINER_NAME} test -x "$shell" 2>/dev/null; then
            available_shell="$shell"
            break
        fi
    done
    
    if [[ -z "$available_shell" ]]; then
        # Try direct execution without shell
        warn "No shell found, trying direct execution..."
        for garage_path in "${garage_paths[@]}"; do
            if sudo docker exec ${CONTAINER_NAME} "$garage_path" $cmd 2>/dev/null; then
                return 0
            fi
        done
    else
        # Use available shell
        for garage_path in "${garage_paths[@]}"; do
            if sudo docker exec ${CONTAINER_NAME} $available_shell -c "$garage_path $cmd" 2>/dev/null; then
                return 0
            fi
        done
    fi
    
    error "Failed to execute garage command. This might be due to:"
    echo "  - Wrong Docker image (try dxflrs/garage:latest instead)"
    echo "  - Container not properly initialized"
    echo "  - Garage binary not found or not executable"
    echo "  - Missing shell in container"
    return 1
}

create_config() {
    log "Creating garage.toml configuration file..."
    
    # Create data directories
    mkdir -p ${DATA_DIR}/{meta,data}
    
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

    log "Configuration file created: ${CONFIG_FILE}"
}

setup_garage() {
    if ! check_docker; then return; fi
    
    echo -e "${CYAN}Setting up Garage S3 Server...${NC}"
    echo ""
    
    # Check if container already exists
    if container_exists; then
        warn "Container ${CONTAINER_NAME} already exists."
        echo -e "${YELLOW}Do you want to remove it and create a new one? (y/N): ${NC}"
        read -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo docker rm -f ${CONTAINER_NAME}
        else
            error "Setup cancelled"
            pause
            return
        fi
    fi
    
    # Ask about Docker image
    echo -e "${CYAN}Choose Docker image:${NC}"
    echo "1. dxflrs/garage:latest (recommended - has shell)"
    echo "2. dxflrs/garage:v2.0.0"
    echo "3. Custom image"
    echo ""
    echo -e "${YELLOW}Enter choice (1-3): ${NC}"
    read image_choice
    
    case $image_choice in
        1)
            docker_image="dxflrs/garage:latest"
            ;;
        2)
            docker_image="dxflrs/garage:v2.0.0"
            warn "This image may have shell issues. Consider using 'latest' if problems occur."
            ;;
        3)
            echo -e "${YELLOW}Enter custom image name: ${NC}"
            read docker_image
            ;;
        *)
            docker_image="dxflrs/garage:latest"
            ;;
    esac
    
    # Ask about ports
    echo -e "${CYAN}Choose port configuration:${NC}"
    echo "1. Default ports (3900-3904)"
    echo "2. Alternative ports (3910-3914)"
    echo "3. Custom ports"
    echo ""
    echo -e "${YELLOW}Enter choice (1-3): ${NC}"
    read port_choice
    
    case $port_choice in
        1)
            ports="3900:3900 3901:3901 3902:3902 3903:3903 3904:3904"
            ;;
        2)
            ports="3910:3900 3911:3901 3912:3902 3913:3903 3914:3904"
            ;;
        3)
            echo -e "${YELLOW}Enter port mappings (e.g., 3910:3900 3911:3901 3912:3902 3913:3903 3914:3904): ${NC}"
            read ports
            ;;
        *)
            ports="3900:3900 3901:3901 3902:3902 3903:3903 3904:3904"
            ;;
    esac
    
    # Create config if it doesn't exist
    if [[ ! -f ${CONFIG_FILE} ]]; then
        create_config
    fi
    
    log "Starting Garage container with image: ${docker_image}"
    log "Port mappings: ${ports}"
    
    # Convert ports string to -p arguments
    port_args=""
    for port in ${ports}; do
        port_args="${port_args} -p ${port}"
    done
    
    # Start container with server command explicitly
    if sudo docker run \
        -d \
        --name ${CONTAINER_NAME} \
        --restart unless-stopped \
        ${port_args} \
        -v $(pwd)/${CONFIG_FILE}:/etc/garage.toml \
        -v $(pwd)/${DATA_DIR}/meta:/var/lib/garage/meta \
        -v $(pwd)/${DATA_DIR}/data:/var/lib/garage/data \
        ${docker_image} \
        /usr/local/bin/garage server; then
        
        log "Container started successfully!"
        
        # Wait for container to be ready
        log "Waiting for container to be ready..."
        sleep 15
        
        # Configure cluster
        configure_cluster
        
        # Show access information
        show_access_info
    else
        error "Failed to start container. Check if ports are already in use or try a different image."
    fi
    pause
}

configure_cluster() {
    log "Configuring Garage cluster..."
    
    # Get node ID with error handling
    NODE_ID=$(garage_exec "node id" | head -n1 | tr -d '\r\n')
    
    if [[ -z "${NODE_ID}" ]] || [[ "${NODE_ID}" == *"Failed"* ]]; then
        error "Failed to get node ID - retrying in 10 seconds..."
        sleep 10
        NODE_ID=$(garage_exec "node id" | head -n1 | tr -d '\r\n')
    fi
    
    if [[ -z "${NODE_ID}" ]] || [[ "${NODE_ID}" == *"Failed"* ]]; then
        error "Still unable to get node ID. The container may need more time to start."
        error "Try running 'Show Status' (option 5) in a few minutes to check if it's ready."
        return 1
    fi
    
    log "Node ID: ${NODE_ID}"
    
    # Configure node with proper syntax
    if garage_exec "layout assign ${NODE_ID} -z dc1 -c 1000" && \
       sleep 2 && \
       garage_exec "layout apply --version 1"; then
        log "Cluster configured successfully!"
        return 0
    else
        error "Failed to configure cluster"
        return 1
    fi
}

show_access_info() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║        GARAGE S3 SERVER IS READY!           ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Access Information:${NC}"
    local port_mappings=$(sudo docker port ${CONTAINER_NAME} 2>/dev/null)
    if [[ -n "$port_mappings" ]]; then
        echo "$port_mappings" | while read line; do
            if [[ $line == *":3900 "* ]]; then
                local host_port=$(echo "$line" | cut -d':' -f2 | cut -d' ' -f1)
                echo "S3 API:     http://localhost:${host_port}"
            elif [[ $line == *":3903 "* ]]; then
                local host_port=$(echo "$line" | cut -d':' -f2 | cut -d' ' -f1)
                echo "Admin API:  http://localhost:${host_port}"
            elif [[ $line == *":3902 "* ]]; then
                local host_port=$(echo "$line" | cut -d':' -f2 | cut -d' ' -f1)
                echo "Web API:    http://localhost:${host_port}"
            elif [[ $line == *":3904 "* ]]; then
                local host_port=$(echo "$line" | cut -d':' -f2 | cut -d' ' -f1)
                echo "K2V API:    http://localhost:${host_port}"
            fi
        done
    fi
}

start_container() {
    if ! check_docker; then return; fi
    
    if container_running; then
        warn "Container is already running"
    else
        log "Starting container..."
        sudo docker start ${CONTAINER_NAME}
        if [[ $? -eq 0 ]]; then
            log "Container started successfully!"
            sleep 5
            show_access_info
        else
            error "Failed to start container"
        fi
    fi
    pause
}

stop_container() {
    if ! check_docker; then return; fi
    
    if ! container_running; then
        warn "Container is not running"
    else
        log "Stopping container..."
        sudo docker stop ${CONTAINER_NAME}
        if [[ $? -eq 0 ]]; then
            log "Container stopped successfully!"
        else
            error "Failed to stop container"
        fi
    fi
    pause
}

restart_container() {
    if ! check_docker; then return; fi
    
    log "Restarting container..."
    sudo docker restart ${CONTAINER_NAME}
    if [[ $? -eq 0 ]]; then
        log "Container restarted successfully!"
        sleep 5
        show_access_info
    else
        error "Failed to restart container"
    fi
    pause
}

show_status() {
    if ! check_docker; then return; fi
    
    echo -e "${BLUE}Container Status:${NC}"
    if container_running; then
        echo -e "${GREEN}✓ Container is running${NC}"
        echo ""
        echo -e "${BLUE}Cluster Status:${NC}"
        garage_exec "status"
        echo ""
        echo -e "${BLUE}Port Mappings:${NC}"
        sudo docker port ${CONTAINER_NAME}
    else
        echo -e "${RED}✗ Container is not running${NC}"
    fi
    pause
}

show_logs() {
    if ! check_docker; then return; fi
    
    echo -e "${BLUE}Container Logs (last 50 lines):${NC}"
    sudo docker logs --tail 50 ${CONTAINER_NAME}
    echo ""
    echo -e "${YELLOW}Show all logs? (y/N): ${NC}"
    read -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo docker logs ${CONTAINER_NAME}
    fi
    pause
}

create_bucket() {
    if ! container_running; then
        error "Container is not running"
        pause
        return
    fi
    
    echo -e "${YELLOW}Enter bucket name: ${NC}"
    read bucket_name
    
    if [[ -z "${bucket_name}" ]]; then
        error "Bucket name cannot be empty"
        pause
        return
    fi
    
    log "Creating bucket: ${bucket_name}"
    garage_exec "bucket create ${bucket_name}"
    pause
}

create_key() {
    if ! container_running; then
        error "Container is not running"
        pause
        return
    fi
    
    echo -e "${YELLOW}Enter key name: ${NC}"
    read key_name
    
    if [[ -z "${key_name}" ]]; then
        error "Key name cannot be empty"
        pause
        return
    fi
    
    log "Creating key: ${key_name}"
    garage_exec "key new --name ${key_name}"
    pause
}

allow_bucket() {
    if ! container_running; then
        error "Container is not running"
        pause
        return
    fi
    
    echo -e "${YELLOW}Enter bucket name: ${NC}"
    read bucket_name
    echo -e "${YELLOW}Enter key name: ${NC}"
    read key_name
    
    if [[ -z "${bucket_name}" ]] || [[ -z "${key_name}" ]]; then
        error "Both bucket name and key name are required"
        pause
        return
    fi
    
    log "Allowing key '${key_name}' to access bucket '${bucket_name}'"
    garage_exec "bucket allow ${bucket_name} --read --write --key ${key_name}"
    pause
}

list_buckets() {
    if ! container_running; then
        error "Container is not running"
        pause
        return
    fi
    
    echo -e "${BLUE}All Buckets:${NC}"
    garage_exec "bucket list"
    pause
}

list_keys() {
    if ! container_running; then
        error "Container is not running"
        pause
        return
    fi
    
    echo -e "${BLUE}All Keys:${NC}"
    garage_exec "key list"
    pause
}

key_info() {
    if ! container_running; then
        error "Container is not running"
        pause
        return
    fi
    
    echo -e "${YELLOW}Enter key name: ${NC}"
    read key_name
    
    if [[ -z "${key_name}" ]]; then
        error "Key name cannot be empty"
        pause
        return
    fi
    
    echo -e "${BLUE}Key Information for: ${key_name}${NC}"
    garage_exec "key info ${key_name}"
    pause
}

change_ports() {
    if ! check_docker; then return; fi
    
    echo -e "${YELLOW}Current port mappings:${NC}"
    if container_exists; then
        sudo docker port ${CONTAINER_NAME} 2>/dev/null || echo "No port mappings found"
    else
        echo "No container exists"
    fi
    
    echo ""
    echo -e "${YELLOW}Enter new port mappings (e.g., 3910:3900 3911:3901 3912:3902 3913:3903 3914:3904): ${NC}"
    read new_ports
    
    if [[ -z "${new_ports}" ]]; then
        error "Port mappings cannot be empty"
        pause
        return
    fi
    
    log "Changing port mappings to: ${new_ports}"
    
    # Get current image
    local current_image=$(sudo docker inspect ${CONTAINER_NAME} --format='{{.Config.Image}}' 2>/dev/null || echo "dxflrs/garage:latest")
    
    # Stop and remove current container
    if container_exists; then
        sudo docker rm -f ${CONTAINER_NAME}
    fi
    
    # Convert ports string to -p arguments
    port_args=""
    for port in ${new_ports}; do
        port_args="${port_args} -p ${port}"
    done
    
    # Start with new ports
    if sudo docker run \
        -d \
        --name ${CONTAINER_NAME} \
        --restart unless-stopped \
        ${port_args} \
        -v $(pwd)/${CONFIG_FILE}:/etc/garage.toml \
        -v $(pwd)/${DATA_DIR}/meta:/var/lib/garage/meta \
        -v $(pwd)/${DATA_DIR}/data:/var/lib/garage/data \
        ${current_image} \
        /usr/local/bin/garage server; then
        
        log "Container restarted with new ports!"
        sleep 5
        show_access_info
    else
        error "Failed to restart container with new ports"
    fi
    pause
}

open_shell() {
    if ! container_running; then
        error "Container is not running"
        pause
        return
    fi
    
    log "Opening shell in container... Type 'exit' to return to menu"
    
    # Try different shells
    local shells=("/bin/sh" "/bin/bash" "/bin/ash")
    local shell_found=false
    
    for shell in "${shells[@]}"; do
        if sudo docker exec ${CONTAINER_NAME} test -x "$shell" 2>/dev/null; then
            sudo docker exec -it ${CONTAINER_NAME} "$shell"
            shell_found=true
            break
        fi
    done
    
    if [[ "$shell_found" == false ]]; then
        error "No interactive shell found in container"
        log "Available files in container:"
        sudo docker exec ${CONTAINER_NAME} ls -la / 2>/dev/null || echo "Cannot list files"
    fi
}

remove_container() {
    if ! check_docker; then return; fi
    
    echo -e "${YELLOW}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║                 WARNING!                     ║${NC}"
    echo -e "${YELLOW}║  This will remove the container but keep    ║${NC}"
    echo -e "${YELLOW}║  configuration and data files.              ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Remove container '${CONTAINER_NAME}'? (y/N): ${NC}"
    read -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if container_exists; then
            log "Stopping and removing container..."
            sudo docker rm -f ${CONTAINER_NAME} 2>/dev/null
            log "Container removed successfully!"
            log "Data and configuration files are preserved."
        else
            warn "Container does not exist"
        fi
    else
        log "Operation cancelled"
    fi
    pause
}

cleanup() {
    echo -e "${RED}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                 WARNING!                     ║${NC}"
    echo -e "${RED}║  This will remove the container and ALL     ║${NC}"
    echo -e "${RED}║  data permanently! This cannot be undone!   ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Are you absolutely sure? Type 'YES' to confirm: ${NC}"
    read confirmation
    
    if [[ "$confirmation" == "YES" ]]; then
        log "Stopping and removing container..."
        sudo docker rm -f ${CONTAINER_NAME} 2>/dev/null
        
        log "Removing data directories..."
        rm -rf ${DATA_DIR}
        
        log "Removing configuration file..."
        rm -f ${CONFIG_FILE}
        
        log "Complete cleanup finished!"
    else
        log "Cleanup cancelled"
    fi
    pause
}

troubleshoot() {
    echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║              TROUBLESHOOTING                 ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${CYAN}1. Container Information:${NC}"
    if container_exists; then
        echo "Container exists: ✓"
        if container_running; then
            echo "Container running: ✓"
        else
            echo "Container running: ✗"
        fi
        echo ""
        echo -e "${CYAN}Container Image:${NC}"
        sudo docker inspect ${CONTAINER_NAME} --format='{{.Config.Image}}' 2>/dev/null || echo "Unable to get image info"
        echo ""
        echo -e "${CYAN}Container Command:${NC}"
        sudo docker inspect ${CONTAINER_NAME} --format='{{.Config.Cmd}}' 2>/dev/null || echo "Unable to get command info"
        echo ""
        echo -e "${CYAN}Container Mounts:${NC}"
        sudo docker inspect ${CONTAINER_NAME} --format='{{range .Mounts}}{{.Source}}:{{.Destination}} {{end}}' 2>/dev/null || echo "Unable to get mount info"
    else
        echo "Container exists: ✗"
    fi
    
    echo ""
    echo -e "${CYAN}2. File System Check:${NC}"
    echo "Config file (${CONFIG_FILE}): $([[ -f ${CONFIG_FILE} ]] && echo "✓" || echo "✗")"
    echo "Data directory (${DATA_DIR}): $([[ -d ${DATA_DIR} ]] && echo "✓" || echo "✗")"
    
    if container_running; then
        echo ""
        echo -e "${CYAN}3. Available Shells in Container:${NC}"
        local shells=("/bin/sh" "/bin/bash" "/bin/ash" "/usr/bin/sh")
        for shell in "${shells[@]}"; do
            if sudo docker exec ${CONTAINER_NAME} test -x "$shell" 2>/dev/null; then
                echo "$shell: ✓"
            else
                echo "$shell: ✗"
            fi
        done
        
        echo ""
        echo -e "${CYAN}4. Garage Binary Locations in Container:${NC}"
        local binary_paths=(
            "/usr/local/bin/garage"
            "/usr/bin/garage"
            "/garage"
            "/opt/garage/garage"
        )
        
        for path in "${binary_paths[@]}"; do
            if sudo docker exec ${CONTAINER_NAME} test -f "$path" 2>/dev/null; then
                echo "$path: ✓"
                sudo docker exec ${CONTAINER_NAME} ls -la "$path" 2>/dev/null
            else
                echo "$path: ✗"
            fi
        done
        
        echo ""
        echo -e "${CYAN}5. Container Process List:${NC}"
        # Try multiple methods to get process list
        if ! sudo docker exec ${CONTAINER_NAME} ps aux 2>/dev/null; then
            if ! sudo docker exec ${CONTAINER_NAME} ps -ef 2>/dev/null; then
                echo "Unable to get process list (ps command not available)"
            fi
        fi
        
        echo ""
        echo -e "${CYAN}6. Container Root Directory:${NC}"
        sudo docker exec ${CONTAINER_NAME} ls -la / 2>/dev/null || echo "Unable to list root directory"
    fi
    
    pause
}

# Main menu loop
while true; do
    show_banner
    show_menu
    echo -e "${YELLOW}Enter your choice (0-17): ${NC}"
    read choice
    
    case $choice in
        1) setup_garage ;;
        2) start_container ;;
        3) stop_container ;;
        4) restart_container ;;
        5) show_status ;;
        6) show_logs ;;
        7) create_bucket ;;
        8) create_key ;;
        9) allow_bucket ;;
        10) list_buckets ;;
        11) list_keys ;;
        12) key_info ;;
        13) change_ports ;;
        14) open_shell ;;
        15) remove_container ;;
        16) cleanup ;;
        17) troubleshoot ;;
        0)
            echo -e "${GREEN}Thank you for using Garage S3 Server Manager!${NC}"
            exit 0
            ;;
        *)
            error "Invalid choice. Please enter a number between 0-17."
            pause
            ;;
    esac
done
