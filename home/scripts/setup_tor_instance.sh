#!/bin/sh

# Single Tor Instance Setup Script for FreeBSD
# Configure the variables below to create any Tor instance

#==============================================
# CONFIGURATION VARIABLES - EDIT THESE
#==============================================
INSTANCE_NAME="tor4"                                    # Name of the instance (e.g., tor1, tor4, relay1)
SOCKS_PORT="9054"                                       # SOCKS5 proxy port
CONTROL_PORT="9084"                                     # Control port
CONFIG_DIR="/usr/local/etc/tor/${INSTANCE_NAME}"       # Configuration directory
DATA_DIR="/var/db/tor/${INSTANCE_NAME}"                # Data directory
LOG_FILE="/var/log/tor/${INSTANCE_NAME}.log"           # Log file location
PID_FILE="/var/run/tor/${INSTANCE_NAME}.pid"           # PID file location
SERVICE_NAME="${INSTANCE_NAME}"                         # Service name for rc.d
#==============================================

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    printf "${GREEN}[INFO]${NC} %s\n" "$1"
}

print_warning() {
    printf "${YELLOW}[WARNING]${NC} %s\n" "$1"
}

print_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1"
}

print_step() {
    printf "${BLUE}[STEP]${NC} %s\n" "$1"
}

# Display configuration
show_configuration() {
    echo "Tor Instance Configuration"
    echo "=========================="
    echo "Instance Name:    ${INSTANCE_NAME}"
    echo "SOCKS5 Port:      ${SOCKS_PORT}"
    echo "Control Port:     ${CONTROL_PORT}"
    echo "Config Dir:       ${CONFIG_DIR}"
    echo "Data Dir:         ${DATA_DIR}"
    echo "Log File:         ${LOG_FILE}"
    echo "PID File:         ${PID_FILE}"
    echo "Service Name:     ${SERVICE_NAME}"
    echo "=========================="
    echo
}

# Check if running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_error "This script must be run as root. Use: sudo $0"
        exit 1
    fi
}

# Check if Tor is installed
check_tor_installed() {
    if ! command -v tor >/dev/null 2>&1; then
        print_error "Tor is not installed. Please install it first:"
        echo "  pkg install tor"
        exit 1
    fi
    print_status "Tor is installed: $(which tor)"
}

# Check if instance already exists
check_existing_instance() {
    if [ -f "/usr/local/etc/rc.d/${SERVICE_NAME}" ]; then
        print_warning "Service ${SERVICE_NAME} already exists!"
        printf "Do you want to overwrite it? (y/N): "
        read -r response
        case "$response" in
            [yY][eE][sS]|[yY])
                print_status "Proceeding with overwrite..."
                # Stop existing service if running
                if service "${SERVICE_NAME}" status >/dev/null 2>&1; then
                    print_status "Stopping existing ${SERVICE_NAME} service..."
                    service "${SERVICE_NAME}" stop || true
                fi
                ;;
            *)
                print_status "Exiting without changes."
                exit 0
                ;;
        esac
    fi
}

# Check for port conflicts
check_port_conflicts() {
    print_step "Checking for port conflicts..."
    
    # Check SOCKS port
    if sockstat -l | grep -q ":${SOCKS_PORT} "; then
        print_error "Port ${SOCKS_PORT} is already in use!"
        sockstat -l | grep ":${SOCKS_PORT} "
        exit 1
    fi
    
    # Check Control port
    if sockstat -l | grep -q ":${CONTROL_PORT} "; then
        print_error "Port ${CONTROL_PORT} is already in use!"
        sockstat -l | grep ":${CONTROL_PORT} "
        exit 1
    fi
    
    print_status "Ports ${SOCKS_PORT} and ${CONTROL_PORT} are available"
}

# Create directories
create_directories() {
    print_step "Creating directories..."
    
    # Create config directory
    mkdir -p "${CONFIG_DIR}"
    print_status "Created config directory: ${CONFIG_DIR}"
    
    # Create data directory
    mkdir -p "${DATA_DIR}"
    print_status "Created data directory: ${DATA_DIR}"
    
    # Create log directory (parent of log file)
    LOG_DIR=$(dirname "${LOG_FILE}")
    mkdir -p "${LOG_DIR}"
    print_status "Created log directory: ${LOG_DIR}"
    
    # Create PID directory (parent of pid file)
    PID_DIR=$(dirname "${PID_FILE}")
    mkdir -p "${PID_DIR}"
    print_status "Created PID directory: ${PID_DIR}"
}

# Set proper permissions
set_permissions() {
    print_step "Setting proper permissions..."
    
    # Check if _tor user exists
    if ! id -u _tor >/dev/null 2>&1; then
        print_error "_tor user does not exist. Please ensure Tor is properly installed."
        exit 1
    fi
    
    # Set ownership
    chown -R _tor:_tor "${CONFIG_DIR}"
    chown -R _tor:_tor "${DATA_DIR}"
    chown -R _tor:_tor "$(dirname "${LOG_FILE}")"
    chown -R _tor:_tor "$(dirname "${PID_FILE}")"
    
    # Set directory permissions
    chmod 700 "${DATA_DIR}"
    chmod 755 "$(dirname "${LOG_FILE}")"
    chmod 755 "$(dirname "${PID_FILE}")"
    chmod 755 "${CONFIG_DIR}"
    
    print_status "Permissions set successfully"
}

# Create torrc configuration file
create_torrc_file() {
    print_step "Creating torrc configuration file..."
    
    cat > "${CONFIG_DIR}/torrc" << EOF
# Tor configuration for ${INSTANCE_NAME}
SocksPort ${SOCKS_PORT}
ControlPort ${CONTROL_PORT}
DataDirectory ${DATA_DIR}
PidFile ${PID_FILE}
Log notice file ${LOG_FILE}
RunAsDaemon 1

# Additional configurations can be added below
# Uncomment and modify as needed:
# Log debug file ${LOG_FILE}
# ExitPolicy reject *:*
# RelayBandwidthRate 100 KBytes
# RelayBandwidthBurst 200 KBytes
# ContactInfo your-email@example.com
EOF

    # Set proper ownership and permissions for config file
    chown _tor:_tor "${CONFIG_DIR}/torrc"
    chmod 644 "${CONFIG_DIR}/torrc"
    
    print_status "Created torrc file: ${CONFIG_DIR}/torrc"
}

# Create rc.d script
create_rcd_script() {
    print_step "Creating rc.d service script..."
    
    cat > "/usr/local/etc/rc.d/${SERVICE_NAME}" << EOF
#!/bin/sh

# PROVIDE: ${SERVICE_NAME}
# REQUIRE: NETWORKING SERVERS
# BEFORE: DAEMON
# KEYWORD: shutdown

. /etc/rc.subr

name="${SERVICE_NAME}"
rcvar="${SERVICE_NAME}_enable"
command="/usr/local/bin/tor"
command_args="-f ${CONFIG_DIR}/torrc"
pidfile="${PID_FILE}"
required_files="${CONFIG_DIR}/torrc"

${SERVICE_NAME}_user="_tor"
${SERVICE_NAME}_group="_tor"

load_rc_config \$name
run_rc_command "\$1"
EOF

    # Make script executable
    chmod +x "/usr/local/etc/rc.d/${SERVICE_NAME}"
    
    print_status "Created rc.d script: /usr/local/etc/rc.d/${SERVICE_NAME}"
}

# Configure rc.conf
configure_rc_conf() {
    print_step "Configuring /etc/rc.conf..."
    
    RC_VAR="${SERVICE_NAME}_enable"
    
    # Check if entry already exists
    if grep -q "^${RC_VAR}=" /etc/rc.conf; then
        print_warning "${RC_VAR} already exists in rc.conf"
        # Update existing entry
        sed -i '' "s/^${RC_VAR}=.*/${RC_VAR}=\"YES\"/" /etc/rc.conf
        print_status "Updated ${RC_VAR} in rc.conf"
    else
        echo "${RC_VAR}=\"YES\"" >> /etc/rc.conf
        print_status "Added ${RC_VAR} to rc.conf"
    fi
}

# Start service
start_service() {
    print_step "Starting ${SERVICE_NAME} service..."
    
    if service "${SERVICE_NAME}" start; then
        print_status "${SERVICE_NAME} started successfully"
        sleep 3  # Wait for service to fully start
    else
        print_error "Failed to start ${SERVICE_NAME}"
        exit 1
    fi
}

# Check service status
check_service() {
    print_step "Checking service status..."
    
    echo "\nService Status:"
    echo "==============="
    service "${SERVICE_NAME}" status
    
    echo "\nProcess Status:"
    echo "==============="
    ps aux | grep "${INSTANCE_NAME}" | grep -v grep || echo "No ${INSTANCE_NAME} processes found"
    
    echo "\nPort Status:"
    echo "============"
    sockstat -l | grep -E "(${SOCKS_PORT}|${CONTROL_PORT})" || echo "No listening sockets found for configured ports"
    
    echo "\nLog File Check:"
    echo "==============="
    if [ -f "${LOG_FILE}" ]; then
        echo "Log file exists: ${LOG_FILE}"
        echo "Last 5 lines:"
        tail -5 "${LOG_FILE}"
    else
        echo "Log file not found: ${LOG_FILE}"
    fi
}

# Test connection
test_connection() {
    print_step "Testing SOCKS5 connection..."
    
    if command -v curl >/dev/null 2>&1; then
        echo "\nTesting Tor connection:"
        echo "======================="
        
        echo "Testing SOCKS5 port ${SOCKS_PORT}..."
        if timeout 30 curl --socks5 "127.0.0.1:${SOCKS_PORT}" -s https://check.torproject.org/api/ip 2>/dev/null; then
            echo " - SOCKS5 port ${SOCKS_PORT}: OK"
        else
            echo " - SOCKS5 port ${SOCKS_PORT}: FAILED (this may be normal if Tor is still bootstrapping)"
        fi
    else
        print_warning "curl not found, skipping connection test"
        echo "To test connection manually, use:"
        echo "  curl --socks5 127.0.0.1:${SOCKS_PORT} https://check.torproject.org/api/ip"
    fi
}

# Print management commands
print_management_info() {
    print_step "Setup complete! Management commands for ${INSTANCE_NAME}:"
    
    cat << EOF

Management Commands for ${INSTANCE_NAME}:
========================================
Start service:
  service ${SERVICE_NAME} start

Stop service:
  service ${SERVICE_NAME} stop

Restart service:
  service ${SERVICE_NAME} restart

Check status:
  service ${SERVICE_NAME} status

View logs:
  tail -f ${LOG_FILE}

Test connection:
  curl --socks5 127.0.0.1:${SOCKS_PORT} https://check.torproject.org/api/ip

Configuration file:
  ${CONFIG_DIR}/torrc

SOCKS5 Proxy: 127.0.0.1:${SOCKS_PORT}
Control Port: 127.0.0.1:${CONTROL_PORT}

To create another instance, edit the variables at the top of this script and run again.

EOF
}

# Main execution
main() {
    echo "Single Tor Instance Setup Script for FreeBSD"
    echo "============================================"
    echo
    
    show_configuration
    
    # Ask for confirmation
    printf "Proceed with this configuration? (Y/n): "
    read -r response
    case "$response" in
        [nN][oO]|[nN])
            print_status "Exiting without changes."
            exit 0
            ;;
        *)
            print_status "Proceeding with setup..."
            ;;
    esac
    
    check_root
    check_tor_installed
    check_existing_instance
    check_port_conflicts
    create_directories
    set_permissions
    create_torrc_file
    create_rcd_script
    configure_rc_conf
    start_service
    check_service
    test_connection
    print_management_info
    
    print_status "${INSTANCE_NAME} setup completed successfully!"
}

# Run the main function
main "$@"
