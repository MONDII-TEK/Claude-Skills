#!/bin/bash

# ===========================================
# Iron & Volt - Docker Management Script
# ===========================================
# Comprehensive CLI for managing Docker deployment
# Usage: ./scripts/manage.sh [command] [options]

set -e

# ===========================================
# Color Definitions
# ===========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ===========================================
# Configuration
# ===========================================
COMPOSE_FILE="docker-compose.yml"
COMPOSE_DEV_FILE="docker-compose.dev.yml"
COMPOSE_PROD_FILE="docker-compose.prod.yml"
COMPOSE_TEST_FILE="docker-compose.test.yml"
BACKUP_DIR="./backups"

# ===========================================
# Load .env file if it exists (before setting PROJECT_NAME)
# This ensures COMPOSE_PROJECT_NAME from .env is available
# ===========================================
ENV_LOADED="false"
ENV_PROJECT_NAME=""
if [ -f ".env" ]; then
    # Export variables from .env file (ignoring comments and empty lines)
    set -a  # automatically export all variables
    source .env 2>/dev/null || true
    set +a
    ENV_LOADED="true"
    # Capture if project name came from .env
    if [ -n "$COMPOSE_PROJECT_NAME" ]; then
        ENV_PROJECT_NAME="$COMPOSE_PROJECT_NAME"
    fi
fi

# Project name (can be overridden with -p/--project flag or COMPOSE_PROJECT_NAME env var)
PROJECT_NAME="${COMPOSE_PROJECT_NAME:-ironvolt}"

# Export COMPOSE_PROJECT_NAME for container naming in docker-compose files
# This ensures container_name: ${COMPOSE_PROJECT_NAME:-ironvolt}-service works correctly
export COMPOSE_PROJECT_NAME="$PROJECT_NAME"

# Show project configuration info
show_project_info() {
    echo -e "${CYAN}[CONFIG]${NC} Project: ${BOLD}$PROJECT_NAME${NC}"
    if [ "$ENV_LOADED" = "true" ]; then
        if [ -n "$ENV_PROJECT_NAME" ]; then
            echo -e "${CYAN}[CONFIG]${NC} Loaded from .env: COMPOSE_PROJECT_NAME=$ENV_PROJECT_NAME"
        else
            echo -e "${YELLOW}[WARNING]${NC} .env loaded but COMPOSE_PROJECT_NAME not set (using default: ironvolt)"
        fi
    else
        echo -e "${YELLOW}[WARNING]${NC} No .env file found (using default project: ironvolt)"
    fi
}

# Env file (can be overridden with --env-file flag)
ENV_FILE=""

# Default container names (will be set based on project name)
DB_CONTAINER=""
BACKEND_CONTAINER=""

# ===========================================
# Mode Tracking Functions
# ===========================================

# Get mode file path for current project
get_mode_file() {
    echo ".compose_mode_${PROJECT_NAME}"
}

# Save the compose mode (dev or prod) for the current project
save_compose_mode() {
    local mode="$1"  # "dev" or "prod"
    local mode_file=$(get_mode_file)
    echo "$mode" > "$mode_file"
}

# Read the saved compose mode for the current project
read_compose_mode() {
    local mode_file=$(get_mode_file)
    if [ -f "$mode_file" ]; then
        cat "$mode_file"
    else
        echo ""
    fi
}

# Clear the compose mode file
clear_compose_mode() {
    local mode_file=$(get_mode_file)
    rm -f "$mode_file" 2>/dev/null || true
}

# Get compose files based on mode
get_compose_files_for_mode() {
    local mode="$1"
    case "$mode" in
        dev)
            echo "$COMPOSE_FILE $COMPOSE_DEV_FILE"
            ;;
        prod)
            echo "$COMPOSE_FILE $COMPOSE_PROD_FILE"
            ;;
        *)
            echo "$COMPOSE_FILE"
            ;;
    esac
}

# Build compose project flags
get_project_flags() {
    local flags=""
    if [ -n "$PROJECT_NAME" ]; then
        flags="-p $PROJECT_NAME"
    fi
    # Always include .env file if it exists (primary source)
    if [ -f ".env" ]; then
        flags="$flags --env-file .env"
    fi
    # Also include custom ENV_FILE if specified via --env-file flag
    if [ -n "$ENV_FILE" ] && [ -f "$ENV_FILE" ] && [ "$ENV_FILE" != ".env" ]; then
        flags="$flags --env-file $ENV_FILE"
    fi
    # Enable MinIO profile only when STORAGE_PROVIDER=minio (default)
    local storage_provider="${STORAGE_PROVIDER:-}"
    if [ -z "$storage_provider" ] && [ -f ".env" ]; then
        storage_provider=$(grep -E "^STORAGE_PROVIDER=" .env 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'" || true)
    fi
    if [ "${storage_provider:-minio}" = "minio" ]; then
        flags="$flags --profile minio"
    fi
    echo "$flags"
}

TEST_PROJECT_NAME="${PROJECT_NAME}_test"

get_test_project_flags() {
    local flags="-p ${TEST_PROJECT_NAME}"
    if [ -f ".env" ]; then
        flags="$flags --env-file .env"
    fi
    if [ -n "$ENV_FILE" ] && [ -f "$ENV_FILE" ] && [ "$ENV_FILE" != ".env" ]; then
        flags="$flags --env-file $ENV_FILE"
    fi
    # Enable MinIO profile only when STORAGE_PROVIDER=minio (default)
    local storage_provider="${STORAGE_PROVIDER:-}"
    if [ -z "$storage_provider" ] && [ -f ".env" ]; then
        storage_provider=$(grep -E "^STORAGE_PROVIDER=" .env 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'" || true)
    fi
    if [ "${storage_provider:-minio}" = "minio" ]; then
        flags="$flags --profile minio"
    fi
    echo "$flags"
}

_test_compose() {
    local project_flags=$(get_test_project_flags)
    COMPOSE_PROJECT_NAME="$TEST_PROJECT_NAME" $COMPOSE_CMD $project_flags -f "$COMPOSE_FILE" -f "$COMPOSE_TEST_FILE" "$@"
}

# Get container name for a service based on project name using docker compose
get_container_name() {
    local service="$1"
    local project_flags=$(get_project_flags)
    
    # Use docker compose ps to get the exact container name for this project/service
    local container=$($COMPOSE_CMD $project_flags -f "$COMPOSE_FILE" ps -q "$service" 2>/dev/null | head -n1)
    
    if [ -n "$container" ]; then
        # Get the actual container name from the ID
        local name=$(docker inspect --format '{{.Name}}' "$container" 2>/dev/null | sed 's/^\///')
        if [ -n "$name" ]; then
            echo "$name"
            return
        fi
    fi
    
    # Fallback: search running containers by pattern matching project-service
    # Docker filter doesn't support regex, so we use grep for pattern matching
    container=$(docker ps --format "{{.Names}}" 2>/dev/null | grep -E "^${PROJECT_NAME}[-_]${service}$" | head -n1)
    
    if [ -n "$container" ]; then
        echo "$container"
        return
    fi
    
    # Try with just the service name suffix (handles various naming patterns)
    container=$(docker ps --format "{{.Names}}" 2>/dev/null | grep -E "${PROJECT_NAME}.*${service}" | head -n1)
    
    if [ -n "$container" ]; then
        echo "$container"
    else
        # Last resort: default naming convention (matches container_name in docker-compose.yml)
        # Note: We use ${PROJECT_NAME}-${service} without -1 suffix because
        # docker-compose.yml defines explicit container_name: ${COMPOSE_PROJECT_NAME}-service
        echo "${PROJECT_NAME}-${service}"
    fi
}

# Ensure we have the correct container names based on project
detect_containers() {
    DB_CONTAINER=$(get_container_name "database")
    BACKEND_CONTAINER=$(get_container_name "backend")
}

# Database credentials - dynamically detected from running container
get_db_credentials() {
    detect_containers
    if docker inspect "$DB_CONTAINER" &>/dev/null; then
        DB_USER=$(docker exec "$DB_CONTAINER" sh -c 'echo $POSTGRES_USER' 2>/dev/null || echo "ironvolt")
        DB_NAME=$(docker exec "$DB_CONTAINER" sh -c 'echo $POSTGRES_DB' 2>/dev/null || echo "ironvolt")
    else
        DB_USER="${POSTGRES_USER:-ironvolt}"
        DB_NAME="${POSTGRES_DB:-ironvolt}"
    fi
}

# ===========================================
# Helper Functions
# ===========================================
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

header() {
    echo -e "\n${BOLD}${CYAN}=== $1 ===${NC}\n"
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install Docker first."
    fi
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        error "Docker Compose is not installed. Please install Docker Compose first."
    fi
}

get_compose_cmd() {
    if docker compose version &> /dev/null 2>&1; then
        echo "docker compose"
    else
        echo "docker-compose"
    fi
}

COMPOSE_CMD=$(get_compose_cmd)

# ===========================================
# Port Checking Functions
# ===========================================

# Get required ports from docker-compose files (using merged config)
get_required_ports() {
    local compose_files="$1"
    local ports=""
    
    # Build the -f flags for docker compose
    local compose_flags=""
    for file in $compose_files; do
        if [ -f "$file" ]; then
            compose_flags="$compose_flags -f $file"
        fi
    done
    
    # Use docker compose config to get the MERGED configuration
    # This respects overrides properly (dev overrides base, etc.)
    # docker compose config outputs long-form YAML like:
    #   ports:
    #     - published: 5008        (unquoted)
    #       target: 5001
    # OR:
    #     - published: "5008"      (quoted)
    #       target: "5001"
    # We need to extract the "published" values (host ports), handling both formats
    if [ -n "$compose_flags" ]; then
        ports=$($COMPOSE_CMD $compose_flags config 2>/dev/null | \
            grep -E '^\s*published:\s*"?[0-9]+"?' | \
            sed 's/.*published:\s*"\?\([0-9]*\)"\?.*/\1/' | \
            sort -u | tr '\n' ' ')
    fi
    
    echo "$ports"
}

# Check if a port is in use by a container from this project
is_ironvolt_container_port() {
    local port="$1"
    
    # Get containers from this EXACT project using Docker Compose label
    local ironvolt_containers=$(docker ps --filter "label=com.docker.compose.project=${PROJECT_NAME}" --format "{{.Names}}" 2>/dev/null || true)
    
    if [ -z "$ironvolt_containers" ]; then
        return 1  # No Iron & Volt containers running
    fi
    
    # Check if any project container is using this port
    for container in $ironvolt_containers; do
        local container_ports=$(docker port "$container" 2>/dev/null | grep -oE "^[0-9]+" || true)
        for cport in $container_ports; do
            if [ "$cport" = "$port" ]; then
                return 0  # This port belongs to Iron & Volt
            fi
        done
        
        # Also check via inspect for host port bindings
        local host_ports=$(docker inspect "$container" --format '{{range $p, $conf := .NetworkSettings.Ports}}{{range $conf}}{{.HostPort}} {{end}}{{end}}' 2>/dev/null || true)
        for hport in $host_ports; do
            if [ "$hport" = "$port" ]; then
                return 0  # This port belongs to Iron & Volt
            fi
        done
    done
    
    return 1  # Port not used by Iron & Volt
}

# Check if a port is in use
check_port_available() {
    local port="$1"
    local process_info=""
    
    # Check with ss (preferred) or netstat
    if command -v ss &>/dev/null; then
        process_info=$(ss -tlnp 2>/dev/null | grep ":$port " | head -1)
    elif command -v netstat &>/dev/null; then
        process_info=$(netstat -tlnp 2>/dev/null | grep ":$port " | head -1)
    fi
    
    if [ -n "$process_info" ]; then
        # Check if the port is used by docker-proxy
        if echo "$process_info" | grep -qE "docker-proxy|containerd"; then
            # Port is used by Docker - check if it's OUR project
            if is_ironvolt_container_port "$port"; then
                # Port is used by Iron & Volt container - will be replaced
                echo "ironvolt"
                return 0
            else
                # Port is used by ANOTHER Docker project
                local other_container=$(docker ps --format "{{.Names}}" --filter "publish=$port" 2>/dev/null | head -1)
                if [ -n "$other_container" ]; then
                    echo "In use by Docker container: $other_container"
                else
                    echo "In use by another Docker container"
                fi
                return 1
            fi
        else
            # Port is used by a non-Docker process
            echo "$process_info"
            return 1
        fi
    fi
    
    echo "free"
    return 0
}

# Check all required ports before starting services
check_ports() {
    local compose_files="$1"
    local ports=$(get_required_ports "$compose_files")
    local has_conflict=0
    local conflicts=""
    
    if [ -z "$ports" ]; then
        return 0
    fi
    
    info "Checking port availability..."
    
    for port in $ports; do
        local result=$(check_port_available "$port")
        local status=$?
        
        if [ $status -ne 0 ]; then
            has_conflict=1
            conflicts="$conflicts\n  Port $port: $result"
        fi
    done
    
    if [ $has_conflict -eq 1 ]; then
        echo ""
        error_no_exit "Port conflict detected! The following ports are already in use:"
        echo -e "$conflicts"
        echo ""
        info "Solutions:"
        echo "  1. Stop the process using the port"
        echo "  2. Stop existing Docker containers: docker stop \$(docker ps -aq)"
        echo "  3. Change the port mapping in docker-compose.yml"
        echo ""
        return 1
    fi
    
    success "All required ports are available"
    return 0
}

# Error without exit (for port check feedback)
error_no_exit() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ===========================================
# Build Commands
# ===========================================

# Parse build options (--no-cache, --pull, etc.)
parse_build_options() {
    local build_opts=""
    for arg in "$@"; do
        case "$arg" in
            --no-cache)
                build_opts="$build_opts --no-cache"
                ;;
            --pull)
                build_opts="$build_opts --pull"
                ;;
            --parallel)
                build_opts="$build_opts --parallel"
                ;;
        esac
    done
    echo "$build_opts"
}

cmd_build() {
    local build_opts=$(parse_build_options "$@")
    header "Building All Docker Images - Project: $PROJECT_NAME"
    local project_flags=$(get_project_flags)
    if [ -n "$build_opts" ]; then
        info "Building production images with options:$build_opts"
    else
        info "Building production images..."
    fi
    $COMPOSE_CMD $project_flags -f "$COMPOSE_FILE" -f "$COMPOSE_PROD_FILE" build $build_opts
    success "All images built successfully!"
}

cmd_build_dev() {
    local build_opts=$(parse_build_options "$@")
    header "Building Development Docker Images - Project: $PROJECT_NAME"
    local project_flags=$(get_project_flags)
    if [ -n "$build_opts" ]; then
        info "Building development images with options:$build_opts"
    else
        info "Building development images..."
    fi
    $COMPOSE_CMD $project_flags -f "$COMPOSE_FILE" -f "$COMPOSE_DEV_FILE" build $build_opts
    success "Development images built successfully!"
}

cmd_build_prod() {
    local build_opts=$(parse_build_options "$@")
    header "Building Production Docker Images - Project: $PROJECT_NAME"
    local project_flags=$(get_project_flags)
    if [ -n "$build_opts" ]; then
        info "Building production images with options:$build_opts"
    else
        info "Building production images..."
    fi
    $COMPOSE_CMD $project_flags -f "$COMPOSE_FILE" -f "$COMPOSE_PROD_FILE" build $build_opts
    success "Production images built successfully!"
}

cmd_build_test() {
    local build_opts=$(parse_build_options "$@")
    header "Building Test Docker Images - Project: $TEST_PROJECT_NAME"
    local project_flags=$(get_test_project_flags)

    # Compute SRC_HASH from backend/ source (excludes tests, __pycache__, *.pyc, *.egg-info).
    # Mirrors the testing-orchestration skill freshness algorithm so the resulting
    # image carries label src_hash=<16-char prefix>, enabling robust stale detection.
    local src_hash=""
    if [ -d "backend" ]; then
        src_hash=$(find backend -type f -name '*.py' \
            -not -path 'backend/tests/*' \
            -not -path '*/__pycache__/*' \
            -not -name '*.pyc' \
            -not -name '*.egg-info*' \
            2>/dev/null | sort | xargs sha256sum 2>/dev/null | sha256sum | cut -d' ' -f1 | head -c 16)
        if [ -n "$src_hash" ]; then
            info "Source hash: $src_hash"
        fi
    fi

    if [ -n "$build_opts" ]; then
        info "Building test images with options:$build_opts"
    else
        info "Building test images..."
    fi
    SRC_HASH="$src_hash" COMPOSE_PROJECT_NAME="$TEST_PROJECT_NAME" $COMPOSE_CMD $project_flags -f "$COMPOSE_FILE" -f "$COMPOSE_TEST_FILE" build $build_opts
    success "Test images built successfully!"
}

# ===========================================
# Lifecycle Commands
# ===========================================

# Clean up existing project containers before starting
# This prevents port conflicts from zombie containers
cleanup_existing_containers() {
    local compose_files="$1"
    local project_flags=$(get_project_flags)
    
    # Check if any containers from this EXACT project are running
    # Uses Docker Compose label for precise project matching (most reliable method)
    # Docker Compose automatically adds com.docker.compose.project label to all containers
    local running_containers=$(docker ps --filter "label=com.docker.compose.project=${PROJECT_NAME}" --format "{{.Names}}" 2>/dev/null | tr '\n' ' ' || true)
    
    if [ -n "$running_containers" ]; then
        info "Stopping existing $PROJECT_NAME containers: $running_containers"
        
        # Use project flag to ensure only this project's containers are affected
        $COMPOSE_CMD $project_flags -f "$COMPOSE_FILE" down 2>/dev/null || true
        
        # Remove any remaining project containers using Docker Compose label
        local remaining=$(docker ps -a --filter "label=com.docker.compose.project=${PROJECT_NAME}" --format "{{.Names}}" 2>/dev/null || true)
        if [ -n "$remaining" ]; then
            info "Removing remaining containers: $remaining"
            for container in $remaining; do
                docker rm -f "$container" 2>/dev/null || true
            done
        fi
        
        # Clear the mode file since containers are now stopped
        clear_compose_mode
        
        success "Previous containers cleaned up"
        
        # Wait for ports to be actually released by the OS
        info "Waiting for ports to be released..."
        wait_for_ports_release "$compose_files"
    fi
}

# Wait until all ports from compose files are actually free
wait_for_ports_release() {
    local compose_files="$1"
    local ports=$(get_required_ports "$compose_files")
    local max_wait=30
    local waited=0
    
    if [ -z "$ports" ]; then
        return 0
    fi
    
    while [ $waited -lt $max_wait ]; do
        local all_free=true
        
        for port in $ports; do
            # Check if port is still bound by docker-proxy or any process
            if ss -tlnp 2>/dev/null | grep -q ":$port "; then
                all_free=false
                break
            fi
        done
        
        if [ "$all_free" = "true" ]; then
            success "All ports released"
            return 0
        fi
        
        sleep 1
        waited=$((waited + 1))
        echo -n "."
    done
    
    echo ""
    warning "Some ports may still be releasing (waited ${max_wait}s)"
}

cmd_up() {
    header "Starting Services (Production) - Project: $PROJECT_NAME"
    show_project_info
    local project_flags=$(get_project_flags)
    
    # Clean up existing containers first to free ports
    cleanup_existing_containers "$COMPOSE_FILE $COMPOSE_PROD_FILE"
    
    # Check ports before starting (merged base + prod config)
    if ! check_ports "$COMPOSE_FILE $COMPOSE_PROD_FILE"; then
        exit 1
    fi
    
    info "Starting all services in production mode..."
    $COMPOSE_CMD $project_flags -f "$COMPOSE_FILE" -f "$COMPOSE_PROD_FILE" up -d
    
    # Save the mode for proper cleanup later
    save_compose_mode "prod"
    
    success "All services started in production mode!"
    echo ""
    cmd_status
}

cmd_up_dev() {
    header "Starting Services (Development) - Project: $PROJECT_NAME"
    show_project_info
    local project_flags=$(get_project_flags)
    
    # Clean up existing containers and wait for ports to be released
    cleanup_existing_containers "$COMPOSE_FILE $COMPOSE_DEV_FILE"
    
    # Check all ports before starting (merged base + dev config)
    if ! check_ports "$COMPOSE_FILE $COMPOSE_DEV_FILE"; then
        exit 1
    fi
    
    info "Starting all services in development mode with hot reload..."
    $COMPOSE_CMD $project_flags -f "$COMPOSE_FILE" -f "$COMPOSE_DEV_FILE" up -d
    
    # Save the mode for proper cleanup later
    save_compose_mode "dev"
    
    success "All services started in development mode!"
    echo ""
    cmd_status
}

cmd_up_prod() {
    cmd_up
}

cmd_down() {
    header "Stopping Services - Project: $PROJECT_NAME"
    show_project_info
    local project_flags=$(get_project_flags)
    info "Stopping and removing all containers..."
    
    # Use project flag to ensure only this project's containers are affected
    # Docker Compose uses COMPOSE_PROJECT_NAME to identify containers
    $COMPOSE_CMD $project_flags -f "$COMPOSE_FILE" down 2>/dev/null || true
    
    # Remove any remaining project containers using Docker Compose label
    local remaining=$(docker ps -a --filter "label=com.docker.compose.project=${PROJECT_NAME}" --format "{{.Names}}" 2>/dev/null || true)
    if [ -n "$remaining" ]; then
        info "Removing remaining containers: $remaining"
        for container in $remaining; do
            docker rm -f "$container" 2>/dev/null || true
        done
    fi
    
    # Clear the mode file
    clear_compose_mode
    
    success "All services stopped and removed!"
}

cmd_restart() {
    local service="$1"
    local project_flags=$(get_project_flags)
    if [ -n "$service" ]; then
        header "Restarting Service: $service - Project: $PROJECT_NAME"
        info "Restarting $service..."
        $COMPOSE_CMD $project_flags -f "$COMPOSE_FILE" restart "$service"
        success "$service restarted successfully!"
    else
        header "Restarting All Services - Project: $PROJECT_NAME"
        info "Restarting all services..."
        $COMPOSE_CMD $project_flags -f "$COMPOSE_FILE" restart
        success "All services restarted successfully!"
    fi
}

# ===========================================
# Utility Commands
# ===========================================
cmd_logs() {
    # Usage:
    #   manage.sh logs [service] [extra docker-compose logs flags]
    #
    # Service is optional (default: all services). Extra flags are passed
    # through to `docker compose logs`. Special flag `--no-follow` strips
    # the default `-f` so the command returns after dumping current output —
    # required for one-shot audits (see doc 053).
    #
    # Examples:
    #   manage.sh logs                              # all services, stream
    #   manage.sh logs backend                      # backend only, stream
    #   manage.sh logs backend --no-follow --tail 200
    #   manage.sh logs backend --no-follow --since 15m

    local service=""
    local follow_flag="-f"
    local -a filtered=()

    for arg in "$@"; do
        case "$arg" in
            --no-follow)
                follow_flag=""
                ;;
            -*)
                filtered+=("$arg")
                ;;
            *)
                # First non-flag positional is the service name
                if [ -z "$service" ]; then
                    service="$arg"
                else
                    filtered+=("$arg")
                fi
                ;;
        esac
    done

    local project_flags=$(get_project_flags)
    if [ -n "$service" ]; then
        header "Logs for: $service - Project: $PROJECT_NAME"
        $COMPOSE_CMD $project_flags -f "$COMPOSE_FILE" logs $follow_flag "${filtered[@]}" "$service"
    else
        header "Logs for All Services - Project: $PROJECT_NAME"
        $COMPOSE_CMD $project_flags -f "$COMPOSE_FILE" logs $follow_flag "${filtered[@]}"
    fi
}

cmd_shell() {
    local service="${1:-backend}"
    detect_containers
    local container=""
    
    case "$service" in
        backend)
            container="$BACKEND_CONTAINER"
            ;;
        database|db)
            container="$DB_CONTAINER"
            ;;
        *)
            container=$(get_container_name "$service" "ironvolt-$service")
            ;;
    esac
    
    header "Opening Shell in: $container"
    info "Connecting to $container..."
    docker exec -it "$container" /bin/sh || docker exec -it "$container" /bin/bash
}

cmd_status() {
    header "Container Status - Project: $PROJECT_NAME"
    local project_flags=$(get_project_flags)
    $COMPOSE_CMD $project_flags -f "$COMPOSE_FILE" ps
}

# ===========================================
# Database Commands
# ===========================================
cmd_db_migrate() {
    header "Running Database Migrations"
    info "Executing Flask database migrations..."
    local project_flags=$(get_project_flags)
    # Use 'heads' to handle multiple migration branches
    $COMPOSE_CMD $project_flags -f "$COMPOSE_FILE" run --rm --entrypoint "" backend flask db upgrade heads
    success "Database migrations completed!"
}

cmd_db_heads() {
    header "Checking Migration Heads"
    info "Checking for divergent migration heads..."
    local project_flags=$(get_project_flags)
    $COMPOSE_CMD $project_flags -f "$COMPOSE_FILE" run --rm --entrypoint "" backend flask db heads
}

cmd_db_merge() {
    header "Merging Migration Heads"
    info "Merging divergent migration heads..."
    local project_flags=$(get_project_flags)
    $COMPOSE_CMD $project_flags -f "$COMPOSE_FILE" run --rm --entrypoint "" backend flask db merge heads -m "merge_migration_heads"
    success "Migration heads merged! Run 'db:migrate' to apply."
}

cmd_db_current() {
    header "Current Migration State"
    info "Checking current migration state in database..."
    local project_flags=$(get_project_flags)
    $COMPOSE_CMD $project_flags -f "$COMPOSE_FILE" run --rm --entrypoint "" backend flask db current
}

cmd_db_stamp() {
    header "Stamp Migration Head"
    if [ -z "$1" ]; then
        error "Usage: db:stamp <revision>"
        error "Example: ./scripts/manage.sh db:stamp head"
        error "Example: ./scripts/manage.sh db:stamp 223d61f3e020"
        exit 1
    fi
    info "Stamping database with revision: $1"
    local project_flags=$(get_project_flags)
    $COMPOSE_CMD $project_flags -f "$COMPOSE_FILE" run --rm --entrypoint "" backend flask db stamp "$1"
    success "Database stamped with revision: $1"
}

# Helper to ensure DB credentials are loaded for DB operations
ensure_db_credentials() {
    get_db_credentials
    info "Using database: $DB_NAME as user: $DB_USER"
}

cmd_db_clean() {
    header "Cleaning Transactional Data"
    detect_containers
    info "Running transactional data cleanup script..."
    docker exec -it "$BACKEND_CONTAINER" python -m seed.seed_clean
    success "Transactional data cleaned successfully!"
}

cmd_db_init() {
    header "Initializing Database from Models"
    detect_containers
    warning "This will DROP ALL TABLES and recreate them from SQLAlchemy models!"
    warning "All data will be lost. Make sure you have a backup if needed."
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        info "Operation cancelled."
        exit 0
    fi
    info "Initializing database from models..."
    docker exec -it "$BACKEND_CONTAINER" python -m seed.seed_init
    success "Database initialized from models!"
}

cmd_db_seed_users() {
    header "Seeding Quick Access Users (all 4 fixtures)"
    detect_containers
    info "Creating quick access users (superadmin, manager, instructor, client)..."
    docker exec -it "$BACKEND_CONTAINER" python -m seed.seed_users
    success "Quick access users created!"
}

cmd_db_seed_owner() {
    header "Seeding Owner Superadmin"
    detect_containers
    info "Creating/updating owner superadmin (eacaja+admin@gmail.com)..."
    docker exec -it "$BACKEND_CONTAINER" python -m seed.seed_users owner
    success "Owner superadmin ready!"
}

cmd_db_seed_quick_defaults() {
    header "Seeding Default Quick Users (manager, instructor, client)"
    detect_containers
    info "Creating/updating 3 default quick users (excluding superadmin@example.com)..."
    docker exec -it "$BACKEND_CONTAINER" python -m seed.seed_users quick-defaults
    success "Default quick users ready!"
}

cmd_db_seed_config() {
    header "Seeding Database (Config Only)"
    detect_containers
    info "Running config seed script..."
    docker exec -it "$BACKEND_CONTAINER" python -m seed.seed_config
    success "Database seeded with config data!"
}

cmd_db_seed_minimal() {
    header "Seeding Database (Minimal Data)"
    detect_containers
    info "Running minimal seed script..."
    docker exec -it "$BACKEND_CONTAINER" python -m seed.seed_minimal
    success "Database seeded with minimal demo data!"
}

cmd_db_seed_max() {
    header "Seeding Database (Maximum Data)"
    detect_containers
    info "Running maximum seed script..."
    docker exec -it "$BACKEND_CONTAINER" python -m seed.seed_max
    success "Database seeded with complete demo data!"
}

cmd_db_seed_geo() {
    header "Seeding GEO Data"
    detect_containers
    info "Running GEO seed script (stats, quotes, FAQ)..."
    docker exec -it "$BACKEND_CONTAINER" python -m seed.seed_geo
    success "GEO data seeded successfully!"
}

cmd_db_seed_posts() {
    header "Seeding Blog Posts"
    detect_containers
    info "Running blog posts seed script..."
    docker exec -it "$BACKEND_CONTAINER" python -m seed.seed_posts
    success "Blog posts seeded successfully!"
}

cmd_db_seed_legal() {
    local lang="${1:-es}"
    header "Seeding Legal Documents (lang: $lang)"
    detect_containers
    info "Running legal documents seed script (language: $lang)..."
    docker exec -it "$BACKEND_CONTAINER" python -m seed.seed_legal_documents --lang "$lang"
    success "Legal documents seeded successfully! (language: $lang)"
}

cmd_db_seed_theme_ironvolt() {
    header "Seeding Iron-Volt Theme Templates"
    detect_containers
    info "Running Iron-Volt theme templates seed script..."
    docker exec -it "$BACKEND_CONTAINER" python -c "from app import create_app; from seed.seed_theme_templates import seed_ironvolt_templates; app = create_app(); app.app_context().push(); seed_ironvolt_templates()"
    success "Iron-Volt theme templates seeded successfully!"
}

cmd_db_seed_theme_luttebien() {
    header "Seeding Luttebien Theme Templates"
    detect_containers
    info "Running Luttebien theme templates seed script..."
    docker exec -it "$BACKEND_CONTAINER" python -c "from app import create_app; from seed.seed_theme_templates import seed_luttebien_templates; app = create_app(); app.app_context().push(); seed_luttebien_templates()"
    success "Luttebien theme templates seeded successfully!"
}

cmd_db_seed_theme_all() {
    header "Seeding All Theme Templates"
    detect_containers
    info "Running all theme templates seed script..."
    docker exec -it "$BACKEND_CONTAINER" python -m seed.seed_theme_templates
    success "All theme templates seeded successfully!"
}

cmd_db_seed_document_templates() {
    local lang="${1:-es}"
    header "Seeding Document Templates (lang: $lang)"
    detect_containers
    info "Running document templates seed script (lang: $lang)..."
    docker exec -it "$BACKEND_CONTAINER" python -m seed.seed_document_templates --lang "$lang"
    success "Document templates seeded successfully! (language: $lang)"
}

cmd_db_seed_emails() {
    local lang="${1:-es}"
    header "Seeding Email Templates (lang: $lang)"
    detect_containers
    info "Running email templates seed script (lang: $lang)..."
    docker exec -it "$BACKEND_CONTAINER" python -m scripts.seed_classic_email_templates --lang "$lang"
    success "Email templates seeded successfully! (language: $lang)"
}

cmd_db_seed_all_templates() {
    local lang="${1:-es}"
    header "Seeding All Templates (lang: $lang)"
    detect_containers
    info "1/2 — Email templates (lang: $lang)..."
    docker exec -it "$BACKEND_CONTAINER" python -m scripts.seed_classic_email_templates --lang "$lang"
    echo ""
    info "2/2 — Document templates (lang: $lang)..."
    docker exec -it "$BACKEND_CONTAINER" python -m seed.seed_document_templates --lang "$lang"
    echo ""
    success "All templates seeded successfully! (language: $lang)"
}

cmd_sync_manual() {
    header "Syncing User Manual to Storage"
    detect_containers
    info "Uploading MANUAL_USUARIO.md to storage (overwrites existing)..."
    docker exec -it "$BACKEND_CONTAINER" python /app/scripts/seed_assets.py --manual-only
    success "User manual synced to storage!"
}

cmd_theme_import() {
    local zip_file="$1"
    
    if [ -z "$zip_file" ]; then
        error "Usage: $0 theme:import <path-to-zip>\n\nImport a theme ZIP file exported via single-template or full export."
    fi
    
    if [ ! -f "$zip_file" ]; then
        error "File not found: $zip_file"
    fi
    
    if ! command -v python3 &>/dev/null; then
        error "python3 is required on the host but not found."
    fi
    
    header "Importing Theme from ZIP"
    detect_containers
    ensure_db_credentials
    
    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap "rm -rf '$tmp_dir'" EXIT
    
    info "Parsing ZIP file on host..."
    
    python3 -c "
import sys, json, zipfile, os, mimetypes

zip_path = sys.argv[1]
tmp_dir = sys.argv[2]

try:
    zf = zipfile.ZipFile(zip_path, 'r')
except zipfile.BadZipFile:
    print('ERROR: Invalid or corrupt ZIP file', file=sys.stderr)
    sys.exit(1)

if 'theme_config.json' not in zf.namelist():
    print('ERROR: ZIP does not contain theme_config.json', file=sys.stderr)
    zf.close()
    sys.exit(1)

import_data = json.loads(zf.read('theme_config.json').decode('utf-8'))

is_single = 'template' in import_data and 'meta' in import_data
is_full = 'templates' in import_data

if not is_single and not is_full:
    print('ERROR: Unrecognized theme_config.json format', file=sys.stderr)
    zf.close()
    sys.exit(1)

import re
def sanitize_slug(s):
    s = str(s).strip().lower()
    s = re.sub(r'[^a-z0-9-]', '-', s)
    s = re.sub(r'-+', '-', s).strip('-')
    return s if s else None

def sanitize_filename(f):
    f = os.path.basename(str(f).strip())
    if not f or f.startswith('.') or '..' in f:
        return None
    return f

templates = []
if is_single:
    t = import_data['template']
    slug = sanitize_slug(t.get('slug', ''))
    if not slug:
        print('ERROR: Template has no valid slug', file=sys.stderr)
        sys.exit(1)
    templates.append({'name': t['name'], 'slug': slug, 'config': t['config']})
else:
    for t in import_data.get('templates', []):
        if isinstance(t, dict) and t.get('name', '').strip():
            slug = sanitize_slug(t.get('slug', ''))
            if not slug:
                continue
            templates.append({'name': t['name'].strip(), 'slug': slug, 'config': t.get('config', {})})

if not templates:
    print('ERROR: No valid templates found in ZIP', file=sys.stderr)
    sys.exit(1)

images = {}
for entry in zf.namelist():
    if not entry.startswith('images/') or entry.endswith('/'):
        continue
    parts = entry.split('/')
    filename = sanitize_filename(parts[-1])
    if not filename:
        continue
    if is_single and len(templates) == 1:
        slug = templates[0]['slug']
    elif len(parts) >= 3:
        slug = sanitize_slug(parts[1])
        if not slug:
            continue
    else:
        continue
    if slug not in images:
        images[slug] = []
    img_path = os.path.join(tmp_dir, 'images', slug, filename)
    os.makedirs(os.path.dirname(img_path), exist_ok=True)
    with open(img_path, 'wb') as f:
        f.write(zf.read(entry))
    file_size = os.path.getsize(img_path)
    ct = mimetypes.guess_type(filename)[0] or 'application/octet-stream'
    storage_key = f'system/templates/{slug}/{filename}'
    url = f'/api/files/download/{storage_key}'
    folder = f'system/templates/{slug}'
    images[slug].append({
        'storage_key': storage_key,
        'url': url,
        'filename': filename,
        'content_type': ct,
        'size': file_size,
        'folder': folder,
    })

zf.close()

def esc(s):
    if s is None:
        return 'NULL'
    return \"'\" + str(s).replace(\"'\", \"''\") + \"'\"

sql_lines = []
for t in templates:
    name = t['name']
    slug = t['slug']
    config_json = json.dumps(t['config'], ensure_ascii=False)
    sql_lines.append(
        f\"INSERT INTO theme_templates (name, slug, config, is_system, created_at, updated_at) \"
        f\"VALUES ({esc(name)}, {esc(slug)}, {esc(config_json)}::jsonb, false, NOW(), NOW()) \"
        f\"ON CONFLICT (slug) DO UPDATE SET config = EXCLUDED.config, name = EXCLUDED.name, updated_at = NOW();\"
    )

for slug, img_list in images.items():
    for img in img_list:
        sql_lines.append(
            f\"INSERT INTO file_assets (storage_key, url, filename, content_type, size, folder, created_at) \"
            f\"VALUES ({esc(img['storage_key'])}, {esc(img['url'])}, {esc(img['filename'])}, \"
            f\"{esc(img['content_type'])}, {img['size']}, {esc(img['folder'])}, NOW()) \"
            f\"ON CONFLICT (storage_key) DO UPDATE SET size = EXCLUDED.size, content_type = EXCLUDED.content_type, url = EXCLUDED.url;\"
        )

sql_path = os.path.join(tmp_dir, 'import.sql')
with open(sql_path, 'w') as f:
    f.write('\n'.join(sql_lines))

print(f'Templates: {len(templates)}')
total_images = sum(len(v) for v in images.values())
print(f'Images: {total_images}')
print(f'SQL file: {sql_path}')
" "$zip_file" "$tmp_dir"
    
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        error "Failed to parse ZIP file"
    fi
    
    local sql_file="$tmp_dir/import.sql"
    
    if [ ! -f "$sql_file" ]; then
        error "SQL file not generated"
    fi
    
    info "Inserting template data into database..."
    cat "$sql_file" | docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -q 2>&1
    local db_exit=$?
    if [ $db_exit -ne 0 ]; then
        error "Database insertion failed (exit code: $db_exit)"
    fi
    
    if [ -d "$tmp_dir/images" ] && [ "$(ls -A "$tmp_dir/images" 2>/dev/null)" ]; then
        info "Copying images to backend uploads volume..."
        local img_count=0
        local uploads_tmp="$tmp_dir/uploads_tree/system/templates"
        mkdir -p "$uploads_tmp"
        cp -r "$tmp_dir/images"/* "$uploads_tmp/"
        tar -C "$tmp_dir/uploads_tree" -cf - . | docker cp - "${BACKEND_CONTAINER}:/app/uploads/" 2>&1
        if [ $? -eq 0 ]; then
            img_count=$(find "$tmp_dir/images" -type f | wc -l)
            info "Images copied: $img_count"
        else
            error "Failed to copy images to backend container. DB records were inserted but files are missing."
        fi
    fi
    
    rm -rf "$tmp_dir"
    trap - EXIT
    
    success "Theme imported successfully!"
    echo ""
    warning "Please restart the backend container to apply changes:"
    echo -e "  ${CYAN}docker compose restart backend${NC}"
}

# Post-restore migration reconciliation.
# After restoring a backup, the schema may be behind the current codebase
# (e.g. a pre-RBAC backup lacks roles/role_permissions tables).
# This step re-applies any pending Alembic migrations so old backups
# are automatically forward-compatible with the running code.
_db_post_restore_migrate() {
    info "Checking for pending migrations after restore..."

    # Ensure backend container is running (needed for flask db upgrade)
    local was_stopped=false
    if ! docker inspect -f '{{.State.Running}}' "$BACKEND_CONTAINER" 2>/dev/null | grep -q true; then
        was_stopped=true
        docker start "$BACKEND_CONTAINER" 2>/dev/null || true
        # Wait for container to be ready
        local retries=0
        while [ $retries -lt 15 ]; do
            if docker exec "$BACKEND_CONTAINER" python -c "print('ready')" 2>/dev/null; then
                break
            fi
            retries=$((retries + 1))
            sleep 2
        done
    fi

    # Check if there are pending migrations
    local pending
    pending=$(docker exec "$BACKEND_CONTAINER" flask db heads 2>/dev/null || echo "error")
    local current
    current=$(docker exec "$BACKEND_CONTAINER" flask db current 2>/dev/null || echo "error")

    if [ "$pending" = "error" ] || [ "$current" = "error" ]; then
        warning "Could not check migration state. Run 'flask db upgrade' manually if needed."
        return
    fi

    # Apply any pending migrations
    info "Applying pending migrations (forward-compat)..."
    if docker exec "$BACKEND_CONTAINER" flask db upgrade 2>&1; then
        success "Migrations applied — backup is now compatible with current schema"
    else
        warning "Migration failed! The backup may be from an incompatible version."
        warning "Check 'flask db current' and 'flask db history' for details."
    fi

    # If we started the backend just for migrations, stop it again
    # (the caller may manage its own start/stop lifecycle)
    if [ "$was_stopped" = true ]; then
        docker stop "$BACKEND_CONTAINER" 2>/dev/null || true
    fi
}

cmd_backup_full() {
    header "Creating Full Backup (Database + Storage)"
    ensure_db_credentials
    
    mkdir -p "$BACKUP_DIR"
    
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    local tmp_dir="$BACKUP_DIR/.tmp_backup_${TIMESTAMP}"
    local archive_file="$BACKUP_DIR/full_backup_${TIMESTAMP}.tar.gz"
    
    mkdir -p "$tmp_dir/storage"
    
    info "[1/3] Backing up database..."
    local sql_file="$tmp_dir/database.sql"
    docker exec "$DB_CONTAINER" pg_dump -U "$DB_USER" -d "$DB_NAME" > "$sql_file"
    
    if [ ! -s "$sql_file" ]; then
        rm -rf "$tmp_dir"
        error "Database backup failed or is empty!"
    fi
    
    local db_size
    db_size=$(du -h "$sql_file" | cut -f1)
    success "Database backup: $db_size"
    
    info "[2/3] Exporting storage files..."
    local storage_tmp="$BACKUP_DIR/_tmp_storage"
    rm -rf "$storage_tmp"
    mkdir -p "$storage_tmp"
    
    docker exec "$BACKEND_CONTAINER" python /app/scripts/backup_storage.py export /app/backups/_tmp_storage 2>&1
    
    if [ -d "$storage_tmp" ] && [ "$(ls -A "$storage_tmp" 2>/dev/null)" ]; then
        cp -r "$storage_tmp/." "$tmp_dir/storage/"
    else
        warning "Storage export produced no files (storage may be empty)"
    fi
    
    rm -rf "$storage_tmp"
    
    local storage_count=0
    if [ -f "$tmp_dir/storage/manifest.json" ]; then
        storage_count=$(python3 -c "import json; print(json.load(open('$tmp_dir/storage/manifest.json'))['total_files'])" 2>/dev/null || echo "0")
    fi
    success "Storage export: $storage_count files"
    
    info "[3/3] Compressing backup..."
    
    local meta_file="$tmp_dir/backup_meta.json"
    local alembic_rev
    alembic_rev=$(docker exec "$BACKEND_CONTAINER" flask db current 2>/dev/null | grep -oE '[a-f0-9]+' | head -1 || echo "unknown")
    cat > "$meta_file" <<EOF
{
    "version": "1.1",
    "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "project": "$PROJECT_NAME",
    "database": "$DB_NAME",
    "db_user": "$DB_USER",
    "storage_files": $storage_count,
    "db_size": "$db_size",
    "alembic_revision": "$alembic_rev"
}
EOF
    
    tar -czf "$archive_file" -C "$tmp_dir" .
    
    rm -rf "$tmp_dir"
    
    local archive_size
    archive_size=$(du -h "$archive_file" | cut -f1)
    
    echo ""
    success "Full backup created: $archive_file"
    info "Archive size: $archive_size"
    info "Contents: database ($db_size) + $storage_count storage files"
}

cmd_restore_full() {
    local archive_file="$1"
    
    if [ -z "$archive_file" ]; then
        error "Please specify a backup archive to restore.\nUsage: $0 restore:full <archive.tar.gz>"
    fi
    
    if [ ! -f "$archive_file" ]; then
        error "Backup archive not found: $archive_file"
    fi
    
    header "Full Restore (Database + Storage)"
    ensure_db_credentials
    
    warning "This will REPLACE the database and overwrite storage files from backup!"
    warning "Existing storage files not in the backup will remain (merge behavior)."
    echo -n "Are you sure you want to continue? [y/N]: "
    read -r confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info "Restore cancelled."
        exit 0
    fi
    
    local tmp_dir="$BACKUP_DIR/.tmp_restore_$$"
    mkdir -p "$tmp_dir"
    
    _restore_cleanup() {
        info "Ensuring backend is running..."
        docker start "$BACKEND_CONTAINER" 2>/dev/null || true
        rm -rf "$tmp_dir" 2>/dev/null || true
    }
    trap _restore_cleanup EXIT
    
    info "[1/5] Extracting archive..."
    tar -xzf "$archive_file" -C "$tmp_dir"
    
    if [ -f "$tmp_dir/backup_meta.json" ]; then
        info "Backup metadata:"
        python3 -c "
import json
meta = json.load(open('$tmp_dir/backup_meta.json'))
print(f\"  Created: {meta.get('created_at', 'unknown')}\")
print(f\"  Project: {meta.get('project', 'unknown')}\")
print(f\"  Database: {meta.get('database', 'unknown')}\")
print(f\"  Storage files: {meta.get('storage_files', 'unknown')}\")
print(f\"  DB size: {meta.get('db_size', 'unknown')}\")
" 2>/dev/null || true
    fi
    
    if [ ! -f "$tmp_dir/database.sql" ]; then
        rm -rf "$tmp_dir"
        trap - EXIT
        error "Invalid backup: database.sql not found in archive"
    fi
    
    info "[2/6] Stopping backend..."
    docker stop "$BACKEND_CONTAINER" 2>/dev/null || true

    info "[3/6] Restoring database..."
    docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d postgres -c \
        "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$DB_NAME' AND pid <> pg_backend_pid();" \
        2>/dev/null || true
    docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d postgres -c "DROP DATABASE IF EXISTS \"$DB_NAME\";"
    docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d postgres -c "CREATE DATABASE \"$DB_NAME\";"
    cat "$tmp_dir/database.sql" | docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME"
    success "Database restored"

    info "[4/6] Applying pending migrations (forward-compat)..."
    _db_post_restore_migrate

    info "[5/6] Restoring storage files..."
    if [ -d "$tmp_dir/storage" ] && [ "$(ls -A "$tmp_dir/storage" 2>/dev/null)" ]; then
        docker start "$BACKEND_CONTAINER" 2>/dev/null || true

        local retries=0
        while [ $retries -lt 15 ]; do
            if docker exec "$BACKEND_CONTAINER" python -c "print('ready')" 2>/dev/null; then
                break
            fi
            retries=$((retries + 1))
            sleep 2
        done

        local storage_tmp="$BACKUP_DIR/_tmp_storage"
        rm -rf "$storage_tmp"
        cp -r "$tmp_dir/storage" "$storage_tmp"

        docker exec "$BACKEND_CONTAINER" python /app/scripts/backup_storage.py import /app/backups/_tmp_storage 2>&1

        rm -rf "$storage_tmp"

        success "Storage files restored"
    else
        info "No storage files in backup, skipping"
        docker start "$BACKEND_CONTAINER" 2>/dev/null || true
    fi

    info "[6/6] Cleanup..."
    rm -rf "$tmp_dir"
    
    trap - EXIT
    
    echo ""
    success "Full restore completed from: $archive_file"
}

cmd_backup_list() {
    header "Available Backups"
    
    if [ ! -d "$BACKUP_DIR" ]; then
        info "No backup directory found ($BACKUP_DIR)"
        return
    fi
    
    local found=0
    
    local full_backups
    full_backups=$(ls -1 "$BACKUP_DIR"/full_backup_*.tar.gz 2>/dev/null || true)
    
    if [ -n "$full_backups" ]; then
        echo -e "${BOLD}${BLUE}Full Backups (.tar.gz):${NC}"
        echo ""
        while IFS= read -r f; do
            local fname
            fname=$(basename "$f")
            local fsize
            fsize=$(du -h "$f" | cut -f1)
            local fdate
            fdate=$(echo "$fname" | sed -n 's/full_backup_\([0-9]\{8\}\)_\([0-9]\{6\}\)\.tar\.gz/\1 \2/p')
            if [ -n "$fdate" ]; then
                local formatted_date
                formatted_date=$(echo "$fdate" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\) \([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3 \4:\5:\6/')
                echo -e "  ${GREEN}●${NC} $fname  ${CYAN}$fsize${NC}  ${YELLOW}$formatted_date${NC}"
            else
                echo -e "  ${GREEN}●${NC} $fname  ${CYAN}$fsize${NC}"
            fi
            local meta_info
            meta_info=$(tar -xzf "$f" -O ./backup_meta.json 2>/dev/null | python3 -c "
import json, sys
try:
    meta = json.load(sys.stdin)
    db_size = meta.get('db_size', '?')
    storage = meta.get('storage_files', '?')
    project = meta.get('project', '?')
    rev = meta.get('alembic_revision', '')
    rev_str = f' | Schema: {rev}' if rev and rev != 'unknown' else ''
    print(f'    DB: {db_size} | Storage: {storage} files | Project: {project}{rev_str}')
except:
    pass
" 2>/dev/null)
            if [ -n "$meta_info" ]; then
                echo -e "  ${meta_info}"
            fi
            found=$((found + 1))
        done <<< "$full_backups"
        echo ""
    fi
    
    local sql_backups
    sql_backups=$(ls -1 "$BACKUP_DIR"/ironvolt_backup_*.sql 2>/dev/null || true)
    
    if [ -n "$sql_backups" ]; then
        echo -e "${BOLD}${BLUE}Legacy Database-Only Backups (.sql):${NC}"
        echo ""
        while IFS= read -r f; do
            local fname
            fname=$(basename "$f")
            local fsize
            fsize=$(du -h "$f" | cut -f1)
            local fdate
            fdate=$(echo "$fname" | sed -n 's/ironvolt_backup_\([0-9]\{8\}\)_\([0-9]\{6\}\)\.sql/\1 \2/p')
            if [ -n "$fdate" ]; then
                local formatted_date
                formatted_date=$(echo "$fdate" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\) \([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3 \4:\5:\6/')
                echo -e "  ${YELLOW}○${NC} $fname  ${CYAN}$fsize${NC}  ${YELLOW}$formatted_date${NC}  (DB only)"
            else
                echo -e "  ${YELLOW}○${NC} $fname  ${CYAN}$fsize${NC}  (DB only)"
            fi
            found=$((found + 1))
        done <<< "$sql_backups"
        echo ""
    fi
    
    if [ "$found" -eq 0 ]; then
        info "No backups found in $BACKUP_DIR"
    else
        info "Total: $found backup(s) in $BACKUP_DIR"
    fi
}

cmd_backup_schedule() {
    local schedule_time="${1:-03:00}"
    
    if ! echo "$schedule_time" | grep -qE '^[0-9]{1,2}:[0-9]{2}$'; then
        error "Invalid time format. Use HH:MM (e.g., 03:00, 14:30)"
    fi
    
    local hour minute
    hour=$(echo "$schedule_time" | cut -d: -f1)
    minute=$(echo "$schedule_time" | cut -d: -f2)
    
    if [ "$hour" -lt 0 ] || [ "$hour" -gt 23 ] || [ "$minute" -lt 0 ] || [ "$minute" -gt 59 ] 2>/dev/null; then
        error "Invalid time. Hour must be 0-23, minute 0-59."
    fi
    
    local script_path
    script_path=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
    local project_dir
    project_dir=$(cd "$(dirname "$0")/.." && pwd)
    local cron_marker="${PROJECT_NAME}-backup-auto"
    
    header "Scheduling Backup for ${PROJECT_NAME}"
    
    local existing
    existing=$(crontab -l 2>/dev/null | grep "# ${cron_marker}$" || true)
    if [ -n "$existing" ]; then
        info "Replacing existing schedule for ${PROJECT_NAME}"
        local new_crontab
        new_crontab=$(crontab -l 2>/dev/null | grep -v "# ${cron_marker}$" || true)
        if [ -z "$new_crontab" ]; then
            crontab -r 2>/dev/null || true
        else
            echo "$new_crontab" | crontab - 2>/dev/null
        fi
    fi
    
    local cron_line="${minute} ${hour} * * * cd '${project_dir}' && '${script_path}' backup:full >> '${project_dir}/backups/cron.log' 2>&1 # ${cron_marker}"
    
    { crontab -l 2>/dev/null || true; echo "$cron_line"; } | crontab -
    
    if crontab -l 2>/dev/null | grep -qF "# ${cron_marker}"; then
        success "Backup scheduled for ${PROJECT_NAME} at ${schedule_time} daily"
        info "Cron entry: ${cron_line}"
        info "Log file: ${project_dir}/backups/cron.log"
    else
        error "Failed to install cron entry. Check crontab permissions."
    fi
}

cmd_backup_unschedule() {
    local cron_marker="${PROJECT_NAME}-backup-auto"
    
    header "Removing Backup Schedule for ${PROJECT_NAME}"
    
    local existing
    existing=$(crontab -l 2>/dev/null | grep "# ${cron_marker}$" || true)
    
    if [ -z "$existing" ]; then
        info "No scheduled backup found for ${PROJECT_NAME}"
        return
    fi
    
    local new_crontab
    new_crontab=$(crontab -l 2>/dev/null | grep -v "# ${cron_marker}$" || true)
    
    if [ -z "$new_crontab" ]; then
        crontab -r 2>/dev/null || true
    else
        echo "$new_crontab" | crontab -
    fi
    
    success "Backup schedule removed for ${PROJECT_NAME}"
}

cmd_backup_crons() {
    header "All Scheduled Backups"
    
    local cron_entries
    cron_entries=$(crontab -l 2>/dev/null | grep "\-backup-auto$" || true)
    
    if [ -z "$cron_entries" ]; then
        info "No scheduled backups found on this server"
        return
    fi
    
    local count=0
    echo ""
    while IFS= read -r line; do
        local project_tag minute hour script_path
        project_tag=$(echo "$line" | sed 's/.*# \(.*\)-backup-auto$/\1/')
        minute=$(echo "$line" | awk '{print $1}')
        hour=$(echo "$line" | awk '{print $2}')
        script_path=$(echo "$line" | sed "s/.* && '\{0,1\}\(.*manage\.sh\)'\{0,1\} .*/\1/" || echo "unknown")
        
        hour=$((10#$hour))
        minute=$((10#$minute))
        printf "  ${GREEN}●${NC} %-20s ${CYAN}%02d:%02d${NC}  ${YELLOW}%s${NC}\n" "$project_tag" "$hour" "$minute" "$script_path"
        count=$((count + 1))
    done <<< "$cron_entries"
    
    echo ""
    info "Total: $count scheduled backup(s)"
}

cmd_backup_clean() {
    local days="${1:-30}"
    
    if ! echo "$days" | grep -qE '^[0-9]+$'; then
        error "Invalid number of days: $days"
    fi
    
    header "Cleaning Backups Older Than ${days} Days"
    
    if [ ! -d "$BACKUP_DIR" ]; then
        info "No backup directory found ($BACKUP_DIR)"
        return
    fi
    
    local cutoff_ts
    cutoff_ts=$(date -d "-${days} days" +%s 2>/dev/null || date -v-${days}d +%s 2>/dev/null)
    
    if [ -z "$cutoff_ts" ]; then
        error "Could not calculate cutoff date"
    fi
    
    local to_delete=()
    
    for f in "$BACKUP_DIR"/full_backup_*.tar.gz; do
        [ -f "$f" ] || continue
        
        local fname
        fname=$(basename "$f")
        local fdate
        fdate=$(echo "$fname" | sed -n 's/full_backup_\([0-9]\{8\}\)_\([0-9]\{6\}\)\.tar\.gz/\1\2/p')
        
        if [ -z "$fdate" ]; then
            continue
        fi
        
        local year month day hour minute second
        year=${fdate:0:4}
        month=${fdate:4:2}
        day=${fdate:6:2}
        hour=${fdate:8:2}
        minute=${fdate:10:2}
        second=${fdate:12:2}
        
        local file_ts
        file_ts=$(date -d "${year}-${month}-${day} ${hour}:${minute}:${second}" +%s 2>/dev/null || \
                  date -j -f "%Y-%m-%d %H:%M:%S" "${year}-${month}-${day} ${hour}:${minute}:${second}" +%s 2>/dev/null)
        
        if [ -n "$file_ts" ] && [ "$file_ts" -lt "$cutoff_ts" ]; then
            local fsize
            fsize=$(du -h "$f" | cut -f1)
            to_delete+=("$f")
            echo -e "  ${RED}✗${NC} $fname  ${CYAN}$fsize${NC}"
        fi
    done
    
    if [ ${#to_delete[@]} -eq 0 ]; then
        info "No backups older than ${days} days found"
        return
    fi
    
    echo ""
    warning "${#to_delete[@]} backup(s) will be permanently deleted"
    echo -n "Are you sure? [y/N]: "
    read -r confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info "Cleanup cancelled."
        return
    fi
    
    local deleted=0
    for f in "${to_delete[@]}"; do
        rm -f "$f"
        deleted=$((deleted + 1))
    done
    
    success "Deleted $deleted backup(s)"
}

cmd_db_shell() {
    header "Opening PostgreSQL Shell"
    get_db_credentials
    info "Connecting to database: $DB_NAME as user: $DB_USER"
    docker exec -it "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME"
}

cmd_db_query() {
    local sql="$*"
    if [ -z "$sql" ]; then
        error "Usage: ./scripts/manage.sh db:query 'SELECT ...'"
        return 1
    fi
    detect_containers
    get_db_credentials
    docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" --pset=pager=off -c "$sql"
}

cmd_db_py() {
    local code="$*"
    if [ -z "$code" ]; then
        error "Usage: ./scripts/manage.sh db:py 'User.query.get(1).to_dict()'"
        return 1
    fi
    detect_containers
    docker exec "$BACKEND_CONTAINER" python3 -c "
import sys, io, os, logging
os.environ['WERKZEUG_RUN_MAIN'] = 'true'
logging.disable(logging.CRITICAL)
from app import create_app
from models import *
app = create_app()
with app.app_context():
    $code
" 2>&1 | grep -v -E '^\[20[0-9]{2}-|^Traceback|^  File |^    |^[A-Za-z]*Error:|^$|LegacyAPIWarning|SAWarning|in logging_config:|task_registered|task_synced|scheduler_loop|scheduler_started|scheduler_stopped|Background scheduler|initialized \||Starting application|Storage provider|MinIO config'
}

cmd_db_sync_password() {
    header "Sync Database Password from .env"
    
    if [ ! -f ".env" ]; then
        error "No .env file found. Nothing to sync."
        return 1
    fi
    
    local env_password=$(grep -E "^POSTGRES_PASSWORD=" .env | head -1 | cut -d'=' -f2-)
    local env_user=$(grep -E "^POSTGRES_USER=" .env | head -1 | cut -d'=' -f2-)
    env_user="${env_user:-ironvolt}"
    local env_db=$(grep -E "^POSTGRES_DB=" .env | head -1 | cut -d'=' -f2-)
    env_db="${env_db:-$env_user}"
    
    if [ -z "$env_password" ]; then
        error "POSTGRES_PASSWORD not found in .env"
        return 1
    fi
    
    detect_containers
    
    if [ -z "$DB_CONTAINER" ]; then
        error "Database container not found. Is Docker running? Try: $0 up"
        return 1
    fi
    
    info "Checking database container readiness..."
    if ! docker exec "$DB_CONTAINER" pg_isready -U "$env_user" > /dev/null 2>&1; then
        error "Database container is not ready. Wait a moment and retry."
        return 1
    fi
    success "Database container is ready"
    
    info "Syncing password for user '${env_user}' in PostgreSQL..."
    info "Container: $DB_CONTAINER"
    info "Connecting via Unix socket (local trust auth)"
    info "Password (first 4 chars): ${env_password:0:4}****"
    
    local output
    output=$(docker exec "$DB_CONTAINER" psql -U "$env_user" -h /var/run/postgresql -d "$env_db" -c "ALTER USER \"${env_user}\" PASSWORD '${env_password}';" 2>&1)
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        success "Password synced: $output"
        echo ""
        info "Now restart the backend to apply:"
        echo "  $0 restart"
        echo ""
        info "Or restart just the backend container:"
        echo "  docker restart ${DB_CONTAINER/database/backend}"
    else
        error "Failed to sync password (exit code: $exit_code)"
        echo ""
        echo -e "  ${YELLOW}psql output:${NC}"
        echo "  $output"
        echo ""
        info "Manual fix — run these commands:"
        echo "  docker exec -it $DB_CONTAINER psql -U ${env_user} -h /var/run/postgresql -d ${env_db}"
        echo "  ALTER USER ${env_user} PASSWORD 'your_new_password';"
        echo "  \\q"
    fi
}

# ===========================================
# Cleanup Commands
# ===========================================
cmd_clean() {
    header "Cleaning Up - Containers Only - Project: $PROJECT_NAME"
    local project_flags=$(get_project_flags)
    warning "This will stop and remove all containers (data volumes preserved)."
    echo -n "Are you sure you want to continue? [y/N]: "
    read -r confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info "Clean cancelled."
        exit 0
    fi
    
    info "Stopping and removing containers..."
    
    # Use project flag to ensure only this project's containers are affected
    $COMPOSE_CMD $project_flags -f "$COMPOSE_FILE" down 2>/dev/null || true
    
    # Remove any remaining project containers using Docker Compose label
    local remaining=$(docker ps -a --filter "label=com.docker.compose.project=${PROJECT_NAME}" --format "{{.Names}}" 2>/dev/null || true)
    if [ -n "$remaining" ]; then
        info "Removing remaining containers: $remaining"
        for container in $remaining; do
            docker rm -f "$container" 2>/dev/null || true
        done
    fi
    
    # Clear the mode file
    clear_compose_mode
    
    success "Containers removed. Data volumes preserved."
}

cmd_clean_all() {
    header "Cleaning Up - Containers AND Volumes - Project: $PROJECT_NAME"
    local project_flags=$(get_project_flags)
    warning "This will stop and remove all containers AND delete all data volumes!"
    warning "ALL DATA WILL BE PERMANENTLY LOST!"
    echo -n "Are you sure you want to continue? [y/N]: "
    read -r confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info "Clean cancelled."
        exit 0
    fi
    
    info "Stopping and removing containers and volumes..."
    
    # Use project flag to ensure only this project's containers are affected
    $COMPOSE_CMD $project_flags -f "$COMPOSE_FILE" down -v 2>/dev/null || true
    
    # Remove any remaining project containers using Docker Compose label
    local remaining=$(docker ps -a --filter "label=com.docker.compose.project=${PROJECT_NAME}" --format "{{.Names}}" 2>/dev/null || true)
    if [ -n "$remaining" ]; then
        info "Removing remaining containers: $remaining"
        for container in $remaining; do
            docker rm -f "$container" 2>/dev/null || true
        done
    fi
    
    # Clear the mode file
    clear_compose_mode
    
    success "Containers and volumes removed."
}

# Force cleanup - directly removes containers by name without compose
cmd_clean_force() {
    header "Force Cleanup - Project: $PROJECT_NAME"
    warning "This will forcefully stop and remove all containers matching project name."
    echo -n "Are you sure you want to continue? [y/N]: "
    read -r confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info "Force clean cancelled."
        exit 0
    fi
    
    info "Finding containers for project: $PROJECT_NAME..."
    
    # Find all containers matching this project using Docker Compose label
    local containers=$(docker ps -a --filter "label=com.docker.compose.project=${PROJECT_NAME}" --format "{{.Names}}" 2>/dev/null || true)
    
    if [ -z "$containers" ]; then
        info "No containers found for project: $PROJECT_NAME"
    else
        info "Found containers: $containers"
        
        # Stop containers first (graceful)
        for container in $containers; do
            info "Stopping: $container"
            docker stop "$container" 2>/dev/null || true
        done
        
        # Remove containers
        for container in $containers; do
            info "Removing: $container"
            docker rm -f "$container" 2>/dev/null || true
        done
        
        success "All project containers forcefully removed"
    fi
    
    # Clear the mode file
    clear_compose_mode
    
    # Wait for ports to be released
    info "Waiting for ports to be released..."
    sleep 3
    
    success "Force cleanup completed!"
}

cmd_clean_images() {
    header "Cleaning Up - Docker Images"
    info "Removing Iron & Volt Docker images..."
    
    local images=$(docker images | grep ironvolt | awk '{print $3}')
    if [ -z "$images" ]; then
        info "No Iron & Volt images found."
        return 0
    fi
    
    echo "$images" | xargs docker rmi -f
    success "Iron & Volt images removed."
}

# ===========================================
# Test Commands
# ===========================================

# Get the script directory for relative paths
get_script_dir() {
    local dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo "$(dirname "$dir")"  # Return parent (project root)
}

# ===========================================
# Test Infrastructure (shared helpers)
# ===========================================

# Parse combinable flags from arguments
# Sets globals: _TEST_DEBUG, _TEST_COVERAGE, _TEST_EMAIL, _TEST_ARGS
_test_parse_flags() {
    _TEST_DEBUG=1
    _TEST_COVERAGE=0
    _TEST_EMAIL=0
    # Rebuild defaults ON for safety — opt-out with --no-build.
    # A long test run against a stale image hides bugs that already landed in
    # source; the cached-layer rebuild cost is small compared to a false green.
    _TEST_BUILD=1
    _TEST_BUILD_NOCACHE=0
    _TEST_FAILFAST=1
    _TEST_HEAVY_ONLY=0
    _TEST_SKIP_HEAVY=0
    _TEST_TEARDOWN=0
    _TEST_FORCE=0
    _TEST_ARGS=()
    for arg in "$@"; do
        case "$arg" in
            --debug|-d)
                _TEST_DEBUG=1
                ;;
            --coverage|-c)
                _TEST_COVERAGE=1
                ;;
            --email)
                _TEST_EMAIL=1
                ;;
            --build|-b)
                _TEST_BUILD=1
                ;;
            --no-build)
                _TEST_BUILD=0
                _TEST_BUILD_NOCACHE=0
                ;;
            --build-no-cache)
                _TEST_BUILD=1
                _TEST_BUILD_NOCACHE=1
                ;;
            --no-failfast)
                _TEST_FAILFAST=0
                ;;
            --no-debug)
                _TEST_DEBUG=0
                ;;
            --heavy-only)
                _TEST_HEAVY_ONLY=1
                ;;
            --skip-heavy)
                _TEST_SKIP_HEAVY=1
                ;;
            --teardown)
                _TEST_TEARDOWN=1
                ;;
            --force)
                _TEST_FORCE=1
                ;;
            *)
                _TEST_ARGS+=("$arg")
                ;;
        esac
    done
}

# Build test images if --build flag is set
_test_maybe_build() {
    if [ "$_TEST_BUILD" = "1" ]; then
        if [ "$_TEST_BUILD_NOCACHE" = "1" ]; then
            cmd_build_test --no-cache
        else
            cmd_build_test
        fi
    fi
    return 0
}

# Start test database and wait for it to be ready
_test_ensure_db() {
    info "Starting test database container..."
    if ! _test_compose up -d --no-deps db-test; then
        error "Failed to start test database container"
        return 1
    fi

    info "Waiting for test database to be ready..."
    local max_attempts=30
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if _test_compose exec -T db-test pg_isready -U ironvolt_test -d ironvolt_test > /dev/null 2>&1; then
            success "Test database is ready!"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 1
    done

    error "Test database failed to start"
    return 1
}

# Build env flags array for docker compose run
# Sets _TEST_ENV_FLAGS array for use as "${_TEST_ENV_FLAGS[@]}"
_test_build_env_flags() {
    _TEST_ENV_FLAGS=(
        -e "DATABASE_URL=postgresql://ironvolt_test:ironvolt_test_secret@db-test:5432/ironvolt_test"
        -e "STORAGE_PROVIDER=local"
        -e "FLASK_SKIP_SCHEDULER=1"
    )
    if [ "$_TEST_DEBUG" = "1" ]; then
        _TEST_ENV_FLAGS+=(-e "LOG_LEVEL=DEBUG")
    fi
}

# Build pytest command
# Args: $1=test_path
_test_pytest_cmd() {
    local test_path="${1:-tests/test_api/}"
    local debug_flags=""
    local coverage_flags=""
    local failfast_flag=""

    if [ "$_TEST_DEBUG" = "1" ]; then
        debug_flags="--log-level=DEBUG --log-cli-level=DEBUG --tb=long"
    else
        debug_flags="--tb=short"
    fi

    if [ "$_TEST_COVERAGE" = "1" ]; then
        coverage_flags="--cov=. --cov-config=.coveragerc --cov-report=html:htmlcov --cov-report=term-missing"
    fi

    if [ "$_TEST_FAILFAST" = "1" ]; then
        failfast_flag="-x"
    fi

    # Pass remaining _TEST_ARGS (after submodule) as extra pytest options.
    # Use printf %q per element so quoted compound args (e.g. -k "A or B")
    # survive the echo→sh -c round-trip without being word-split.
    local extra_pytest_args=""
    if [ ${#_TEST_ARGS[@]} -gt 1 ]; then
        local _arg
        for _arg in "${_TEST_ARGS[@]:1}"; do
            extra_pytest_args="${extra_pytest_args} $(printf '%q' "$_arg")"
        done
    fi

    echo "pip install pytest pytest-cov --quiet && python -m pytest ${test_path} -v ${debug_flags} ${coverage_flags} ${failfast_flag}${extra_pytest_args}"
}

# Report test result
_test_report() {
    local result=$1
    local label="${2:-Tests}"
    if [ $result -eq 0 ]; then
        success "$label passed!"
    else
        # Note: DO NOT use error() here — it calls exit 1, which breaks
        # --no-failfast semantics (later phases never run). Just print the
        # failure and return the rc; callers that want abort-on-fail use
        # `|| exit $?` explicitly.
        echo -e "${RED}[ERROR]${NC} Some $label failed. Check output above."
    fi
    return $result
}

# ===========================================
# Test Commands
# ===========================================

# Background task test files (slow)
_BG_TEST_FILES=(
    "tests/test_api/test_background_tasks_api.py"
    "tests/test_api/test_background_tasks_long_running_api.py"
    "tests/test_api/test_background_tasks_multiworker_api.py"
    "tests/test_api/test_background_tasks_self_test_api.py"
)

# Unit test directories
_UNIT_TEST_DIRS=(
    "tests/test_unit/"
)

# Build path string for unit test directories
_test_unit_paths() {
    echo "${_UNIT_TEST_DIRS[*]}"
}

# ── Unified log directory ──────────────────────────────────────────
#
# Every test:* command writes its logs into a single timestamped directory under
# logs/test_runs/<UTC-timestamp>_<label>/. Captures:
#   - backend.log         pytest stdout/stderr per phase (concat w/ section headers)
#   - backend_heavy.log   stripe_heavy phase output (one section per class)
#   - backend_flaky.log   stripe_flaky phase output (one section per class)
#   - db_test.log         docker logs ironvolt_test-db-test-1 at end
#   - stripe_cli.log      stripe-cli sidecar events (harvested before stop)
#   - summary.log         invoked cmd, flags, per-phase exit codes, total duration
#
# Multi-phase runs (e.g. test:full) init the dir ONCE at cmd level — sub-calls
# to _test_run reuse the existing dir via the _TEST_RUN_DIR global.
_TEST_RUN_DIR=""
_TEST_RUN_STARTED_AT=""

_test_init_run_dir() {
    # Idempotent: no-op if already initialized (for multi-phase orchestration).
    [ -n "$_TEST_RUN_DIR" ] && return 0
    local label_slug="${1:-run}"
    label_slug=$(echo "$label_slug" | tr ' /:' '___' | tr -cd '[:alnum:]_-')
    local ts
    ts=$(date -u +%Y%m%dT%H%M%SZ)
    _TEST_RUN_DIR="$(pwd)/logs/test_runs/${ts}_${label_slug}"
    _TEST_RUN_STARTED_AT="$ts"
    mkdir -p "$_TEST_RUN_DIR" || return 1
    info "[run-dir] $_TEST_RUN_DIR"
    # Seed summary.log with command + flags
    {
        echo "# Test run summary"
        echo "started_at_utc: $ts"
        echo "cwd: $(pwd)"
        echo "argv: $0 $*"
        echo "flags:"
        echo "  debug=$_TEST_DEBUG coverage=$_TEST_COVERAGE email=$_TEST_EMAIL"
        echo "  build=$_TEST_BUILD build_no_cache=$_TEST_BUILD_NOCACHE failfast=$_TEST_FAILFAST"
        echo "  heavy_only=$_TEST_HEAVY_ONLY skip_heavy=$_TEST_SKIP_HEAVY teardown=$_TEST_TEARDOWN force=$_TEST_FORCE"
        echo ""
        echo "# Phases"
    } > "$_TEST_RUN_DIR/summary.log"
    return 0
}

_test_summary_append() {
    # Usage: _test_summary_append "<phase label>" <exit_code>
    [ -z "$_TEST_RUN_DIR" ] && return 0
    local phase="$1"
    local rc="${2:-0}"
    local ts_now
    ts_now=$(date -u +%Y%m%dT%H%M%SZ)
    echo "- [$ts_now] phase=\"$phase\" rc=$rc" >> "$_TEST_RUN_DIR/summary.log"
}

# Capture db-test container logs (Postgres stdout/stderr) into run dir.
# Call BEFORE any teardown that removes the container. Idempotent / best-effort.
_db_test_harvest_logs() {
    [ -z "$_TEST_RUN_DIR" ] && return 0
    local context="${1:-}"
    local dbc
    dbc=$(docker ps -a --format '{{.Names}}' 2>/dev/null | grep -E '^ironvolt_test-db-test-' | head -1 || true)
    [ -z "$dbc" ] && return 0
    {
        echo ""
        echo "────────────────────────────────────────────────────────────────"
        echo "[db-test harvest] $(date -Iseconds) container=$dbc context=${context:-n/a}"
        echo "────────────────────────────────────────────────────────────────"
        docker logs "$dbc" 2>&1 || echo "(docker logs failed — container may already be gone)"
    } >> "$_TEST_RUN_DIR/db_test.log"
    return 0
}

# Finalize: capture db-test logs, print path. Call at end of top-level cmd.
_test_finalize_run_dir() {
    [ -z "$_TEST_RUN_DIR" ] && return 0
    local overall_rc="${1:-0}"
    _db_test_harvest_logs "finalize"
    {
        echo ""
        echo "# Finalization"
        echo "finished_at_utc: $(date -u +%Y%m%dT%H%M%SZ)"
        echo "overall_rc: $overall_rc"
    } >> "$_TEST_RUN_DIR/summary.log"
    info "[run-dir] Logs consolidated → $_TEST_RUN_DIR"
    ls -la "$_TEST_RUN_DIR" 2>/dev/null | awk 'NR>1 {print "    " $NF "  (" $5 " bytes)"}' | head -10
    # Reset so a subsequent invocation in the same shell gets a fresh dir
    _TEST_RUN_DIR=""
    _TEST_RUN_STARTED_AT=""
    return 0
}

# Unified test runner
# Args: $1=test_path (may include --ignore flags), $2=label
_test_run() {
    local test_path="$1"
    local label="${2:-Tests}"

    # Track whether this invocation is standalone (it owns the run dir lifecycle)
    # or part of a multi-phase orchestrator (test:full) that manages the dir.
    local _owns_run_dir=0
    if [ -z "$_TEST_RUN_DIR" ]; then
        _test_init_run_dir "$label" || warning "Failed to init run dir"
        _owns_run_dir=1
    fi

    _test_maybe_build || { [ $_owns_run_dir -eq 1 ] && _test_finalize_run_dir 1; return 1; }
    _test_ensure_db || { [ $_owns_run_dir -eq 1 ] && _test_finalize_run_dir 1; return 1; }

    _test_build_env_flags

    local extra_env=()
    local extra_vol=()

    if [ "$_TEST_EMAIL" = "1" ]; then
        extra_env+=(-e "TEST_FAST=0")
        extra_env+=(-e "MAIL_SERVER=${MAIL_SERVER:-}")
        extra_env+=(-e "MAIL_PORT=${MAIL_PORT:-587}")
        extra_env+=(-e "MAIL_USE_SSL=${MAIL_USE_SSL:-false}")
        extra_env+=(-e "MAIL_USERNAME=${MAIL_USERNAME:-}")
        extra_env+=(-e "MAIL_PASSWORD=${MAIL_PASSWORD:-}")
        extra_env+=(-e "MAIL_DEFAULT_SENDER=${MAIL_DEFAULT_SENDER:-}")
    else
        extra_env+=(-e "TEST_FAST=1")
    fi

    if [ "$_TEST_COVERAGE" = "1" ]; then
        mkdir -p backend/htmlcov
        extra_vol+=(-v "$(pwd)/backend/htmlcov:/app/htmlcov")
    fi

    # Pass Stripe keys for integration tests
    if [ -n "${STRIPE_SECRET_KEY:-}" ]; then
        extra_env+=(-e "STRIPE_SECRET_KEY=${STRIPE_SECRET_KEY}")
    fi
    if [ -n "${STRIPE_WEBHOOK_SECRET:-}" ]; then
        extra_env+=(-e "STRIPE_WEBHOOK_SECRET=${STRIPE_WEBHOOK_SECRET}")
        extra_env+=(-e "STRIPE_TEST_WEBHOOK_SECRET=${STRIPE_WEBHOOK_SECRET}")
    fi

    local pytest_cmd=$(_test_pytest_cmd "$test_path")

    # Append a section header to the host-side backend.log so multi-phase
    # (test:full) concatenation stays readable.
    local host_backend_log=""
    if [ -n "$_TEST_RUN_DIR" ]; then
        host_backend_log="$_TEST_RUN_DIR/backend.log"
        {
            echo ""
            echo "════════════════════════════════════════════════════════════════"
            echo "[phase] $label  started=$(date -Iseconds)"
            echo "════════════════════════════════════════════════════════════════"
        } >> "$host_backend_log"
    fi

    # POSIX sh has no `pipefail`, so capture pytest's exit code to a file and
    # re-exit with it after the `tee` drains. Without this, `tee` (always 0)
    # masks pytest failures and the orchestrator reports phases as green
    # despite real test rojos.
    local inner_cmd="{ ${pytest_cmd}; echo \$? > /tmp/pytest_rc; } 2>&1 | tee logs/test_results.log; exit \$(cat /tmp/pytest_rc)"

    set +e
    if [ -n "$host_backend_log" ]; then
        # Inner `tee` preserves in-container logs/test_results.log (used by
        # `test:logs`). Outer `tee -a` on host consolidates into the run dir.
        _test_compose run --rm --no-deps \
            "${_TEST_ENV_FLAGS[@]}" \
            "${extra_env[@]}" \
            "${extra_vol[@]}" \
            --entrypoint "" \
            backend sh -c "$inner_cmd" 2>&1 | tee -a "$host_backend_log"
        local result=${PIPESTATUS[0]}
    else
        _test_compose run --rm --no-deps \
            "${_TEST_ENV_FLAGS[@]}" \
            "${extra_env[@]}" \
            "${extra_vol[@]}" \
            --entrypoint "" \
            backend sh -c "$inner_cmd"
        local result=$?
    fi
    set -e

    _test_summary_append "$label" "$result"

    if [ "$_TEST_COVERAGE" = "1" ]; then
        info "Coverage report saved to: backend/htmlcov/index.html"
    fi

    _test_report $result "$label"

    # Single-phase commands (test:unit, test:api, test:bg, test:module, test)
    # own the run dir; finalize captures db-test logs and prints path.
    [ $_owns_run_dir -eq 1 ] && _test_finalize_run_dir "$result"

    return $result
}

# Run each stripe_heavy test CLASS in its own pytest invocation, with a cooldown
# between classes so the stripe-cli webhook queue drains. This prevents cross-test
# saturation that TimeoutError's Thunder yearly renewals when heavy tests run back-to-back.
#
# Args: $1=test_path (dir or file), $2=label prefix,
#       $3=marker expression (default: stripe_heavy; may be a pytest -m expression like
#          "stripe_heavy and not stripe_flaky"),
#       $4=tag (default: heavy) — short identifier used for container/log names.
#          MUST be a single alphanumeric token; defaults to "heavy" because marker
#          expressions aren't valid docker/log names.
_test_run_heavy_isolated() {
    local test_path="$1"
    local label="${2:-Stripe heavy tests}"
    local marker="${3:-stripe_heavy}"
    local tag="${4:-heavy}"
    # 5th arg (optional): pre-collected newline-separated class list. When
    # set, the marker-based collection step is skipped and only the listed
    # classes run. Used by the per-class retry loop in
    # _test_run_flaky_with_retry to re-attempt only previously-failed classes.
    local pre_collected_classes="${5:-}"
    local cooldown_seconds=15
    local backend_name="ironvolt_test-backend-${tag}"
    local log_prefix="${tag}-isolated"
    # File where this invocation writes the class IDs that failed (one per
    # line). Wrappers (retry loops) read it post-call to know what to retry.
    # Path is tag-keyed so concurrent isolated runs don't clobber each other.
    local failed_classes_file="/tmp/_test_${tag}_failed_classes.txt"
    : > "$failed_classes_file"

    _test_maybe_build || return 1
    _test_ensure_db || return 1
    _test_build_env_flags

    local base_env=()
    local base_vol=()

    if [ "$_TEST_EMAIL" = "1" ]; then
        base_env+=(-e "TEST_FAST=0")
    else
        base_env+=(-e "TEST_FAST=1")
    fi

    if [ "$_TEST_COVERAGE" = "1" ]; then
        mkdir -p backend/htmlcov
        base_vol+=(-v "$(pwd)/backend/htmlcov:/app/htmlcov")
    fi

    if [ -n "${STRIPE_SECRET_KEY:-}" ]; then
        base_env+=(-e "STRIPE_SECRET_KEY=${STRIPE_SECRET_KEY}")
    fi
    if [ -n "${STRIPE_WEBHOOK_SECRET:-}" ]; then
        base_env+=(-e "STRIPE_WEBHOOK_SECRET=${STRIPE_WEBHOOK_SECRET}")
        base_env+=(-e "STRIPE_TEST_WEBHOOK_SECRET=${STRIPE_WEBHOOK_SECRET}")
    fi

    local debug_flags="--tb=short"
    if [ "$_TEST_DEBUG" = "1" ]; then
        debug_flags="--log-level=DEBUG --log-cli-level=DEBUG --tb=long"
    fi

    # ── Step 1: collect heavy classes ──
    # When the caller passes a pre-collected list (retry path), skip the
    # marker-based discovery — re-running it would also include classes that
    # already passed in a prior attempt.
    local classes
    if [ -n "$pre_collected_classes" ]; then
        classes="$pre_collected_classes"
        info "[${log_prefix}] Using pre-collected class list (retry path)."
    else
        info "[${log_prefix}] Collecting classes with marker='${marker}' under ${test_path}..."
        local collect_err=/tmp/heavy_collect_err.$$
        set +e
        classes=$(_test_compose run --rm -T --no-deps \
            "${_TEST_ENV_FLAGS[@]}" \
            -v "$(pwd)/scripts/stripe_heavy_collect.py:/app/stripe_heavy_collect.py:ro" \
            --entrypoint "" \
            backend sh -c "pip install pytest pytest-cov --quiet && python /app/stripe_heavy_collect.py $(printf '%q' "$test_path") -m $(printf '%q' "$marker")" 2>"$collect_err" </dev/null)
        local collect_rc=$?
        set -e

        if [ $collect_rc -ne 0 ] && [ -z "$classes" ]; then
            echo -e "${RED}[ERROR]${NC} [${log_prefix}] Collection failed (rc=$collect_rc). stderr:"
            [ -s "$collect_err" ] && sed 's/^/    /' "$collect_err"
            rm -f "$collect_err"
            _test_report 1 "$label"
            return 1
        fi
        rm -f "$collect_err"
    fi

    if [ -z "$classes" ]; then
        info "[${log_prefix}] No '${marker}' tests found under ${test_path}."
        _test_report 0 "$label"
        return 0
    fi

    local class_count
    class_count=$(echo "$classes" | wc -l | tr -d ' ')
    info "[${log_prefix}] Found $class_count '${marker}' class(es) — persistent backend + sidecar restart between classes:"
    echo "$classes" | sed 's/^/  - /'

    # ── Step 2: boot PERSISTENT backend for the whole phase 2 ──
    # Previous approach used ephemeral `docker compose run --rm` per class,
    # which created a race: stripe-cli forwarded webhooks to `test-backend`
    # while the new container was still booting (connection refused) or the
    # old one was tearing down (reset by peer). By keeping the backend alive
    # for the entire phase 2, the target hostname resolves stably and the
    # only transient window is the pytest session start (≤5s with warm imports).
    info "[${log_prefix}] Starting persistent backend for this phase..."
    docker rm -f "$backend_name" >/dev/null 2>&1 || true
    set +e
    _test_compose run -d --name "$backend_name" --no-deps \
        "${_TEST_ENV_FLAGS[@]}" \
        "${base_env[@]}" \
        "${base_vol[@]}" \
        -v "$(pwd)/scripts/stripe_heavy_collect.py:/app/stripe_heavy_collect.py:ro" \
        --entrypoint "" \
        backend sh -c "pip install pytest pytest-cov --quiet && tail -f /dev/null" </dev/null
    local boot_rc=$?
    set -e
    if [ $boot_rc -ne 0 ]; then
        error_no_exit() { echo -e "${RED}[ERROR]${NC} $1"; }
        error_no_exit "[${log_prefix}] Failed to start persistent backend (rc=$boot_rc)."
        _test_report 1 "$label"
        return 1
    fi

    # Wait until pytest is importable inside the container (pip install finished).
    local attempts=0
    local max_attempts=60
    while [ $attempts -lt $max_attempts ]; do
        if docker exec "$backend_name" python -c "import pytest" >/dev/null 2>&1; then
            break
        fi
        attempts=$((attempts + 1))
        sleep 1
    done
    if [ $attempts -ge $max_attempts ]; then
        echo -e "${RED}[ERROR]${NC} [${log_prefix}] Persistent backend did not install pytest within ${max_attempts}s."
        docker logs "$backend_name" 2>&1 | tail -30 | sed 's/^/    /'
        docker rm -f "$backend_name" >/dev/null 2>&1 || true
        _test_report 1 "$label"
        return 1
    fi
    info "[${log_prefix}] Persistent backend ready (${attempts}s to install pytest)."

    # Truncate legacy in-container heavy log so it reflects only this run's
    # output (consistent with test_results.log which uses `tee` without `-a`).
    # Done at start rather than at end → robust against aborts / kills: the
    # next run always starts clean regardless of how the previous one ended.
    # Host-side backend_${tag}.log (unified run dir) is untouched — it remains
    # append-only and immutable post-run.
    docker exec "$backend_name" sh -c ": > /app/logs/test_results_${tag}.log" 2>/dev/null || true

    # ── Step 3: loop via `docker exec` on the persistent backend ──
    local overall=0
    local first=1
    local index=0
    local cls
    while IFS= read -r cls; do
        [ -z "$cls" ] && continue
        index=$((index+1))
        if [ "$first" -eq 0 ]; then
            info "[${log_prefix}] Restarting stripe-cli sidecar between ${tag} classes..."
            _stripe_cli_stop >/dev/null 2>&1 || true
            sleep 3
            _stripe_cli_start
            local cls_whsec
            cls_whsec=$(_stripe_cli_wait_for_secret)
            if [ -n "$cls_whsec" ]; then
                info "[${log_prefix}] stripe-cli restarted — webhook secret: ${cls_whsec:0:12}..."
                export STRIPE_WEBHOOK_SECRET="$cls_whsec"
            else
                warning "[${log_prefix}] stripe-cli restart failed — continuing with old secret"
            fi
            info "[${log_prefix}] Cooldown ${cooldown_seconds}s before next class..."
            sleep "$cooldown_seconds"
        fi
        first=0

        echo "================================================================"
        info "[${log_prefix}] [$index/$class_count] Running: $cls"
        echo "================================================================"

        # Host-side per-phase log appended per-class with section header.
        local host_phase_log=""
        if [ -n "$_TEST_RUN_DIR" ]; then
            host_phase_log="$_TEST_RUN_DIR/backend_${tag}.log"
            {
                echo ""
                echo "════════════════════════════════════════════════════════════════"
                echo "[${tag} $index/$class_count] $cls  started=$(date -Iseconds)"
                echo "════════════════════════════════════════════════════════════════"
            } >> "$host_phase_log"
        fi

        set +e
        # docker exec is stable (no container create/destroy), and the backend
        # process is already up so the target for stripe-cli forwards never
        # goes away for more than the ≤5s pytest session transition.
        # NOTE: `docker exec` has no `-T` flag (that belongs to `docker compose`).
        # For non-interactive execution we simply omit `-t`. `-e STRIPE_WEBHOOK_SECRET`
        # is re-passed per exec in case the inter-class restart produced a new
        # whsec (stripe-cli normally returns the same key, but be defensive).
        if [ -n "$host_phase_log" ]; then
            docker exec -i \
                -e "STRIPE_WEBHOOK_SECRET=${STRIPE_WEBHOOK_SECRET:-}" \
                -e "STRIPE_TEST_WEBHOOK_SECRET=${STRIPE_WEBHOOK_SECRET:-}" \
                "$backend_name" \
                sh -c "{ python -m pytest $(printf '%q' "$cls") -v ${debug_flags}; echo \$? > /tmp/pytest_rc; } 2>&1 | tee -a logs/test_results_${tag}.log; exit \$(cat /tmp/pytest_rc)" </dev/null 2>&1 | tee -a "$host_phase_log"
            local rc=${PIPESTATUS[0]}
        else
            docker exec -i \
                -e "STRIPE_WEBHOOK_SECRET=${STRIPE_WEBHOOK_SECRET:-}" \
                -e "STRIPE_TEST_WEBHOOK_SECRET=${STRIPE_WEBHOOK_SECRET:-}" \
                "$backend_name" \
                sh -c "{ python -m pytest $(printf '%q' "$cls") -v ${debug_flags}; echo \$? > /tmp/pytest_rc; } 2>&1 | tee -a logs/test_results_${tag}.log; exit \$(cat /tmp/pytest_rc)" </dev/null
            local rc=$?
        fi
        set -e

        _stripe_cli_harvest_logs "" "[${tag} $index/$class_count] $cls"
        _test_summary_append "${tag}: $cls" "$rc"

        if [ $rc -ne 0 ]; then
            overall=$rc
            echo "$cls" >> "$failed_classes_file"
            warning "[${log_prefix}] Class $cls FAILED with rc=$rc (continuing with remaining classes)"
        fi
    done <<EOF
$classes
EOF

    # ── Step 4: cleanup persistent backend ──
    info "[${log_prefix}] Stopping persistent backend..."
    docker stop --time 5 "$backend_name" >/dev/null 2>&1 || true
    docker rm -f "$backend_name" >/dev/null 2>&1 || true

    info "[${log_prefix}] All classes processed. Overall rc=$overall"
    _test_report $overall "$label"
    return $overall
}

# Run stripe_flaky classes with retry-on-failure (max 3 attempts, 30s cooldown).
# Per-class retry: attempt N+1 only re-runs the classes that failed in
# attempt N. Independent flaky classes don't penalise each other — a green
# class that happens to be in the same set as a flaky one isn't re-run.
# The block passes when every class has passed at least once across the
# attempts; it fails when some class still fails after the final attempt.
#
# Rationale: re-running the WHOLE set every attempt means three classes
# with 70% individual pass rate produce only 0.7³≈34% per-attempt success
# AND three independent retries can each fail on a different class —
# no single attempt is fully green even though every class would have
# passed had it been retried alone. Per-class retry brings the effective
# pass rate per class to ≥1−0.3³ = 97.3% with the same attempt budget.
#
# Args: $1=test_path (dir or file), $2=label prefix
_test_run_flaky_with_retry() {
    local test_path="$1"
    local label="${2:-Stripe flaky tests}"
    local max_attempts=3
    local inter_attempt_sleep=30
    local failed_file="/tmp/_test_flaky_failed_classes.txt"
    local attempt=1
    local rc=0
    local pending_classes=""

    while [ $attempt -le $max_attempts ]; do
        if [ -z "$pending_classes" ] && [ $attempt -eq 1 ]; then
            info "[flaky] Attempt ${attempt}/${max_attempts} — ${label} (full set)"
        else
            local pending_count
            pending_count=$(echo "$pending_classes" | grep -c '.' || true)
            info "[flaky] Attempt ${attempt}/${max_attempts} — ${label} (re-running ${pending_count} previously-failed class(es))"
        fi

        rc=0
        _test_run_heavy_isolated "$test_path" "${label} (attempt ${attempt})" "stripe_flaky" "flaky" "$pending_classes" || rc=$?

        if [ $rc -eq 0 ]; then
            [ $attempt -gt 1 ] && info "[flaky] Block passed on attempt ${attempt}/${max_attempts} (per-class retry rescued the failures)"
            return 0
        fi

        # Capture which classes failed *this* attempt and feed them to
        # the next iteration. The heavy-isolated function writes them
        # one-per-line to the tag-keyed file `_test_flaky_failed_classes.txt`.
        if [ ! -s "$failed_file" ]; then
            warning "[flaky] Attempt ${attempt} failed (rc=${rc}) but no failed-class file produced — bailing out"
            break
        fi
        pending_classes=$(cat "$failed_file")

        if [ $attempt -lt $max_attempts ]; then
            local pc
            pc=$(echo "$pending_classes" | wc -l | tr -d ' ')
            warning "[flaky] Attempt ${attempt} failed (rc=${rc}, ${pc} class(es) still red). Cooling down ${inter_attempt_sleep}s before retry..."
            sleep "$inter_attempt_sleep"
        fi
        attempt=$((attempt + 1))
    done

    warning "[flaky] After ${max_attempts} attempts, the following class(es) still fail:"
    [ -s "$failed_file" ] && sed 's/^/  - /' "$failed_file"
    return $rc
}

# Print active flags summary
_test_show_flags() {
    [ "$_TEST_DEBUG" = "1" ] && info "Debug mode ON: LOG_LEVEL=DEBUG, verbose tracebacks"
    [ "$_TEST_COVERAGE" = "1" ] && info "Coverage mode ON: generating HTML report"
    [ "$_TEST_EMAIL" = "1" ] && warning "Email mode ON: real emails will be sent (TEST_FAST=0)"
    if [ "$_TEST_BUILD" = "1" ]; then
        info "Build mode ON (default): rebuilding test images before running (opt-out: --no-build)"
    else
        warning "Build mode OFF (--no-build): using existing image — may be stale"
    fi
    [ "$_TEST_BUILD_NOCACHE" = "1" ] && info "No-cache mode ON: building without Docker cache"
    [ "$_TEST_HEAVY_ONLY" = "1" ] && info "Heavy-only mode ON: skipping phase 1 (non-heavy tests)"
    [ "$_TEST_SKIP_HEAVY" = "1" ] && info "Skip-heavy mode ON: skipping phase 2 (stripe_heavy tests)"
    [ "$_TEST_TEARDOWN" = "1" ] && info "Teardown mode ON: all test containers will be stopped after run"
    [ "$_TEST_FORCE" = "1" ] && warning "Force mode ON: bypassing pre-flight collision checks"
    return 0
}

# Build ignore flags for excluding background tasks
_test_bg_ignore_flags() {
    local ignores=""
    for f in "${_BG_TEST_FILES[@]}"; do
        ignores="$ignores --ignore=$f"
    done
    echo "$ignores"
}

# Build path for background task tests only
_test_bg_paths() {
    echo "${_BG_TEST_FILES[*]}"
}

# Run all tests EXCLUDING background tasks (API + unit)
# Supports: --debug/-d, --coverage/-c, --email
cmd_test() {
    _test_parse_flags "$@"
    header "Running All Tests (API + Unit, excluding background tasks)"
    _test_show_flags

    local ignore_flags=$(_test_bg_ignore_flags)
    local unit_paths=$(_test_unit_paths)
    _test_run "tests/test_api/ ${unit_paths} ${ignore_flags}" "all tests"
}

# Run ONLY API tests (excluding background tasks)
# Supports: --debug/-d, --coverage/-c, --email
cmd_test_api() {
    _test_parse_flags "$@"
    header "Running API Tests (excluding background tasks)"
    _test_show_flags

    local ignore_flags=$(_test_bg_ignore_flags)
    _test_run "tests/test_api/ ${ignore_flags}" "API tests"
}

# Run ONLY unit tests (services, storage, templates)
# Supports: --debug/-d, --coverage/-c, --email
cmd_test_unit() {
    _test_parse_flags "$@"
    header "Running Unit Tests (services, storage, templates)"
    _test_show_flags

    local unit_paths=$(_test_unit_paths)
    _test_run "$unit_paths" "unit tests"
}

# Run ONLY background task tests
# Supports: --debug/-d, --coverage/-c, --email
_test_run_bg_flaky_with_retry() {
    local bg_paths="$1"
    local label="${2:-background flaky tests}"
    local max_attempts=3
    local inter_attempt_sleep=15
    local attempt=1
    local rc=0
    while [ $attempt -le $max_attempts ]; do
        info "[bg-flaky] Attempt ${attempt}/${max_attempts} — ${label}"
        rc=0
        _test_run "${bg_paths} -m bg_flaky" "${label} (attempt ${attempt})" || rc=$?
        if [ $rc -eq 0 ]; then
            [ $attempt -gt 1 ] && info "[bg-flaky] Passed on attempt ${attempt}/${max_attempts}"
            return 0
        fi
        if [ $attempt -lt $max_attempts ]; then
            warning "[bg-flaky] Attempt ${attempt} failed (rc=${rc}). Cooling down ${inter_attempt_sleep}s before retry..."
            sleep "$inter_attempt_sleep"
        fi
        attempt=$((attempt + 1))
    done
    warning "[bg-flaky] All ${max_attempts} attempts failed (final rc=${rc})"
    return $rc
}

cmd_test_bg() {
    _test_parse_flags "$@"
    header "Running Background Task Tests"
    _test_show_flags

    local bg_paths=$(_test_bg_paths)

    # Phase 1 — deterministic bg tests (excluding bg_flaky)
    local stable_rc=0
    _test_run "${bg_paths} -m 'not bg_flaky'" "background task tests" || stable_rc=$?

    # Phase 2 — bg_flaky tests with retry-on-failure (multiworker cleanup,
    # leader election races). Isolated so their flakiness doesn't pollute
    # the deterministic phase 1 signal.
    local flaky_rc=0
    _test_run_bg_flaky_with_retry "$bg_paths" "background flaky tests" || flaky_rc=$?

    if [ $stable_rc -ne 0 ] || [ $flaky_rc -ne 0 ]; then
        return 1
    fi
    return 0
}

# Run the FULL test suite in strict sequential orchestration:
#   Phase 1/5 — Unit tests
#   Phase 2/5 — API tests (excluding background tasks)
#   Phase 3/5 — Background task tests
#   Phase 4/5 — Stripe integration (light, via stripe-cli sidecar)
#   Phase 5/5 — Stripe integration (heavy, each class isolated + cooldown)
#
# Guarantees:
#   - Sequential: no parallel execution across or within phases (db_session
#     TRUNCATE fixture handles intra-phase isolation).
#   - Rebuild once: honors --build only in Phase 1, disables build flag after.
#   - Auto-teardown at end: stripe-cli sidecar stopped + db-test container
#     brought down to guarantee a clean slate, regardless of pass/fail.
#   - Phase failures do NOT abort remaining phases — all phases always run
#     so the user gets a full picture. Exit code reflects overall pass/fail.
#
# Supports all standard test flags. --teardown is forced ON internally.
cmd_test_full() {
    _test_parse_flags "$@"
    header "Running FULL Test Suite (Unit + API + BG + Stripe light + Stripe heavy)"
    info "Orchestration: strictly sequential phases, no parallel execution, auto-teardown at end"
    _test_show_flags

    # Initialize the unified run dir ONCE for all 5 phases. Sub-calls to
    # _test_run and cmd_test_stripe will see _TEST_RUN_DIR already set and
    # reuse it instead of creating phase-specific dirs.
    _test_init_run_dir "test_full"

    # Capture effective user-passed flags so we can forward them to cmd_test_stripe
    # without --build (image is already built after Phase 1). We pass --no-build
    # explicitly since cmd_test_stripe re-parses flags (which would re-default
    # _TEST_BUILD=1, triggering a redundant rebuild at phase 4).
    local stripe_passthrough=()
    [ "$_TEST_DEBUG" = "1" ] && stripe_passthrough+=("--debug")
    [ "$_TEST_COVERAGE" = "1" ] && stripe_passthrough+=("--coverage")
    [ "$_TEST_EMAIL" = "1" ] && stripe_passthrough+=("--email")
    [ "$_TEST_FAILFAST" = "0" ] && stripe_passthrough+=("--no-failfast")
    [ "$_TEST_HEAVY_ONLY" = "1" ] && stripe_passthrough+=("--heavy-only")
    [ "$_TEST_SKIP_HEAVY" = "1" ] && stripe_passthrough+=("--skip-heavy")
    [ "$_TEST_FORCE" = "1" ] && stripe_passthrough+=("--force")
    stripe_passthrough+=("--no-build")   # image already rebuilt in phase 1
    stripe_passthrough+=("--teardown")   # always teardown at very end

    local total_result=0
    local phase_summary=()
    local aborted=0

    # Helper: skip remaining phases if failfast ON and a prior phase failed.
    _full_should_skip() {
        if [ "$_TEST_FAILFAST" = "1" ] && [ $total_result -ne 0 ]; then
            aborted=1
            return 0
        fi
        return 1
    }

    # Phase 1/5 — Unit Tests (honors --build if provided)
    header "FULL 1/5 — Unit Tests"
    local unit_paths=$(_test_unit_paths)
    if _test_run "$unit_paths" "unit tests"; then
        phase_summary+=("[PASS] 1/5 Unit")
    else
        phase_summary+=("[FAIL] 1/5 Unit")
        total_result=1
    fi

    # Image is now built — disable rebuild for all remaining phases.
    _TEST_BUILD=0
    _TEST_BUILD_NOCACHE=0

    # Phase 2/5 — API Tests (excluding background tasks)
    if _full_should_skip; then
        phase_summary+=("[SKIP] 2/5 API (failfast)")
    else
        header "FULL 2/5 — API Tests (excluding background tasks)"
        local ignore_flags=$(_test_bg_ignore_flags)
        if _test_run "tests/test_api/ ${ignore_flags}" "API tests"; then
            phase_summary+=("[PASS] 2/5 API")
        else
            phase_summary+=("[FAIL] 2/5 API")
            total_result=1
        fi
    fi

    # Phase 3/5 — Background Task Tests (slow)
    # Split into deterministic + bg_flaky-with-retry (multiworker cleanup,
    # leader election races isolated so their flakiness doesn't break the
    # deterministic signal).
    if _full_should_skip; then
        phase_summary+=("[SKIP] 3/5 BG (failfast)")
    else
        header "FULL 3/5 — Background Task Tests"
        local bg_paths=$(_test_bg_paths)
        local bg_stable_rc=0
        local bg_flaky_rc=0
        _test_run "${bg_paths} -m 'not bg_flaky'" "background task tests" || bg_stable_rc=$?
        _test_run_bg_flaky_with_retry "$bg_paths" "background flaky tests" || bg_flaky_rc=$?
        if [ $bg_stable_rc -eq 0 ] && [ $bg_flaky_rc -eq 0 ]; then
            phase_summary+=("[PASS] 3/5 BG")
        else
            phase_summary+=("[FAIL] 3/5 BG (stable=${bg_stable_rc} flaky=${bg_flaky_rc})")
            total_result=1
        fi
    fi

    # Phase 4-5/5 — Stripe integration (light + heavy) delegated to cmd_test_stripe.
    # cmd_test_stripe internally handles its own two phases (light / heavy isolated)
    # plus stripe-cli sidecar lifecycle and --teardown (db-test down at end).
    if _full_should_skip; then
        phase_summary+=("[SKIP] 4-5/5 Stripe (failfast)")
        # Still need to run teardown so db-test doesn't linger even on early abort
        info "[failfast] Skipping Stripe phase — running teardown to clean containers..."
        _test_stripe_teardown 2>/dev/null || true
    else
        header "FULL 4-5/5 — Stripe Integration (light + heavy + auto-teardown)"
        if cmd_test_stripe "${stripe_passthrough[@]}"; then
            phase_summary+=("[PASS] 4-5/5 Stripe (light + heavy)")
        else
            phase_summary+=("[FAIL] 4-5/5 Stripe (light + heavy)")
            total_result=1
        fi
    fi

    # Final summary
    header "FULL TEST SUMMARY"
    for phase in "${phase_summary[@]}"; do
        echo "  $phase"
    done
    if [ $total_result -eq 0 ]; then
        success "ALL PHASES PASSED — full suite green"
    else
        error "ONE OR MORE PHASES FAILED — see phase summary above"
    fi

    # Finalize unified log dir (captures db-test logs, prints path).
    _test_finalize_run_dir "$total_result"
    return $total_result
}

# Run specific test module
# Supports: --debug/-d, --coverage/-c, --email
cmd_test_module() {
    _test_parse_flags "$@"
    local module="${_TEST_ARGS[0]}"
    if [ -z "$module" ]; then
        echo -e "${RED}[ERROR]${NC} Please specify a test module. Run '$0 test:list' to see available modules."
        exit 1
    fi
    header "Running Tests: $module"
    _test_show_flags

    local host_test_dir="tests"
    [ -d "backend/tests" ] && host_test_dir="backend/tests"

    local test_file=""
    if [ -f "${host_test_dir}/test_api/test_${module}_api.py" ]; then
        test_file="tests/test_api/test_${module}_api.py"
    elif [ -f "${host_test_dir}/test_api/test_${module}.py" ]; then
        test_file="tests/test_api/test_${module}.py"
    elif [ -n "$(find "${host_test_dir}/test_unit" -name "test_${module}.py" 2>/dev/null | head -1)" ]; then
        test_file="$(find "${host_test_dir}/test_unit" -name "test_${module}.py" | head -1 | sed "s|^${host_test_dir}/|tests/|")"
    elif [ -f "${host_test_dir}/test_stripe/test_${module}.py" ]; then
        test_file="tests/test_stripe/test_${module}.py -m stripe_integration"
        warning "Stripe test via test:module — stripe-cli NOT started. Use 'test:stripe' for real webhook forwarding."
    else
        local prefix_files
        prefix_files=$(find "${host_test_dir}/test_api" "${host_test_dir}/test_unit" "${host_test_dir}/test_stripe" -name "test_${module}_*.py" 2>/dev/null | sort)
        if [ -n "$prefix_files" ]; then
            local count
            count=$(echo "$prefix_files" | wc -l)
            info "Prefix match: found $count test files for '${module}'"
            local joined
            joined=$(echo "$prefix_files" | sed "s|^${host_test_dir}/|tests/|" | tr '\n' ' ')
            _test_run "$joined" "$module tests ($count files)"
            return $?
        fi
        echo -e "${RED}[ERROR]${NC} Test module '${module}' not found."
        echo "Searched in: test_api/, test_unit/ (recursive)"
        echo "Run '$0 test:list' to see available modules."
        exit 1
    fi

    _test_run "$test_file" "$module tests"
}

# Stripe integration tests (real Stripe API + Test Clocks + stripe-cli webhooks)
cmd_test_stripe() {
    _test_parse_flags "$@"
    header "Running Stripe Integration Tests"
    _test_show_flags

    # Unified run dir — owned by this invocation if no orchestrator (test:full)
    # already set one. Finalization (including db-test log harvest) happens at
    # the bottom of this function before `--teardown` removes containers.
    local _stripe_owns_run_dir=0
    if [ -z "$_TEST_RUN_DIR" ]; then
        _test_init_run_dir "test_stripe"
        _stripe_owns_run_dir=1
    fi

    # Pre-flight anti-collision check: detect dev/prod/test containers that could
    # interfere with stripe-cli webhook forwarding or share the test DB schema.
    _test_stripe_preflight || { [ $_stripe_owns_run_dir -eq 1 ] && _test_finalize_run_dir 1; return 1; }

    if [ -z "${STRIPE_SECRET_KEY:-}" ]; then
        # Try to load from .env
        if [ -f ".env" ]; then
            local sk
            sk=$(grep '^STRIPE_SECRET_KEY=' .env | cut -d= -f2-)
            if [ -n "$sk" ]; then
                export STRIPE_SECRET_KEY="$sk"
                info "Loaded STRIPE_SECRET_KEY from .env"
            fi
        fi
    fi

    if [ -z "${STRIPE_SECRET_KEY:-}" ]; then
        echo -e "${RED}[ERROR]${NC} STRIPE_SECRET_KEY not set. Required for Stripe integration tests."
        echo "Set it in .env or export it: export STRIPE_SECRET_KEY=sk_test_..."
        exit 1
    fi

    # Start stripe-cli sidecar for real webhook forwarding
    local stripe_whsec=""
    _stripe_cli_start
    stripe_whsec=$(_stripe_cli_wait_for_secret)

    if [ -n "$stripe_whsec" ]; then
        info "stripe-cli ready — webhook secret: ${stripe_whsec:0:12}..."
        export STRIPE_WEBHOOK_SECRET="$stripe_whsec"
    else
        warning "stripe-cli failed to start — falling back to unsigned webhooks"
    fi

    # Accept optional submodule filter (e.g., test:stripe paths → only lifecycle_paths)
    local stripe_module="${_TEST_ARGS[0]:-}"
    local test_path="tests/test_stripe/"
    local test_label_prefix="Stripe integration tests"

    if [ -n "$stripe_module" ]; then
        local host_test_dir="tests"
        [ -d "backend/tests" ] && host_test_dir="backend/tests"
        if [ -f "${host_test_dir}/test_stripe/test_${stripe_module}.py" ]; then
            test_path="tests/test_stripe/test_${stripe_module}.py"
            test_label_prefix="Stripe: ${stripe_module} tests"
            info "Running subset: test_${stripe_module}.py"
        else
            echo -e "${RED}[ERROR]${NC} Stripe test module '${stripe_module}' not found at test_stripe/test_${stripe_module}.py"
            _stripe_cli_stop
            _test_stripe_teardown
            exit 1
        fi
    fi

    # Two-phase run to avoid stripe-cli sidecar saturation on heavy tests:
    # Phase 1 — everything EXCEPT stripe_heavy (grouped, single pytest invocation)
    # Phase 2 — each stripe_heavy class in its OWN pytest invocation with inter-test
    #           cooldown so stripe-cli webhook queue drains between heavy tests.
    local phase1_result=0
    local phase2_result=0

    if [ "$_TEST_HEAVY_ONLY" = "1" ]; then
        info "--heavy-only: skipping phase 1"
    else
        local phase1_target="${test_path} -m 'stripe_integration and not stripe_heavy and not stripe_flaky'"
        info "Phase 1/3 — ${test_label_prefix} (excluding stripe_heavy + stripe_flaky)"
        # `|| phase1_result=$?` keeps `set -e` from aborting before teardown/cleanup
        # below when phase 1 fails.
        _test_run "$phase1_target" "${test_label_prefix} (phase 1)" || phase1_result=$?
    fi

    if [ "$_TEST_SKIP_HEAVY" = "1" ]; then
        info "--skip-heavy: skipping phase 2 (heavy tests)"
    else
        if [ "$_TEST_HEAVY_ONLY" != "1" ]; then
            # After phase 1, stripe-cli has seen ~8 tests worth of webhooks.
            # Even with a short cooldown, Path 10 (full renewal cascade with
            # yearly clock advances) can time out waiting for credits because
            # the sidecar is still processing backlog. Restart it to guarantee
            # a clean queue for phase 2.
            info "Restarting stripe-cli sidecar for clean queue before heavy tests..."
            _stripe_cli_stop >/dev/null 2>&1 || true
            sleep 3
            _stripe_cli_start
            stripe_whsec=$(_stripe_cli_wait_for_secret)
            if [ -n "$stripe_whsec" ]; then
                info "stripe-cli restarted — webhook secret: ${stripe_whsec:0:12}..."
                export STRIPE_WEBHOOK_SECRET="$stripe_whsec"
            else
                warning "stripe-cli restart failed — continuing with old secret"
            fi
            info "Cooldown 15s so restarted sidecar stabilizes..."
            sleep 15
        fi
        info "Phase 2/3 — ${test_label_prefix} (stripe_heavy excluding stripe_flaky, each class isolated + cooldown)"
        # `|| phase2_result=$?` keeps `set -e` from aborting before teardown/cleanup
        # below when phase 2 fails.
        _test_run_heavy_isolated "$test_path" "${test_label_prefix} (phase 2: heavy)" "stripe_heavy and not stripe_flaky" "heavy" || phase2_result=$?
    fi

    # Phase 3 — stripe_flaky classes (paths that saturate stripe-cli under load).
    # Wrapped in retry loop: up to 3 attempts, 30s cooldown between them.
    # Each attempt delegates per-class isolation + sidecar restart to the same
    # helper used in Phase 2. A single successful attempt short-circuits.
    local phase3_result=0
    if [ "$_TEST_SKIP_HEAVY" = "1" ]; then
        info "--skip-heavy: skipping phase 3 (stripe_flaky tests)"
    elif [ "$_TEST_HEAVY_ONLY" = "1" ]; then
        # --heavy-only covers phase 2 + 3 together
        _test_run_flaky_with_retry "$test_path" "${test_label_prefix} (phase 3: flaky)" || phase3_result=$?
    else
        _test_run_flaky_with_retry "$test_path" "${test_label_prefix} (phase 3: flaky)" || phase3_result=$?
    fi

    # Always stop stripe-cli sidecar — no lingering containers
    _stripe_cli_stop

    # Harvest db-test logs NOW, while container may still exist — teardown
    # below removes it. If orchestrator owns the run dir (test:full), it will
    # re-harvest at its own finalize; idempotent append is safe.
    _db_test_harvest_logs "test_stripe-end"

    # Optional full teardown of test containers (db-test, stripe-cli already stopped).
    if [ "$_TEST_TEARDOWN" = "1" ]; then
        info "--teardown: stopping all test containers (db-test)..."
        _test_stripe_teardown
    fi

    # Consolidated summary entries
    _test_summary_append "stripe phase 1 (light)" "$phase1_result"
    _test_summary_append "stripe phase 2 (heavy)" "$phase2_result"
    _test_summary_append "stripe phase 3 (flaky)" "$phase3_result"

    local stripe_overall=0
    if [ $phase1_result -ne 0 ] || [ $phase2_result -ne 0 ] || [ $phase3_result -ne 0 ]; then
        stripe_overall=1
    fi

    # Finalize run dir only if we own it (direct test:stripe invocation).
    [ $_stripe_owns_run_dir -eq 1 ] && _test_finalize_run_dir "$stripe_overall"

    return $stripe_overall
}

# Phase 3 only — run stripe_flaky classes isolated + retry.
# Thin wrapper: starts/stops stripe-cli sidecar, delegates work to
# `_test_run_flaky_with_retry`. Useful to validate the flaky-suite infra
# before running the full stripe orchestration.
cmd_test_stripe_flaky() {
    _test_parse_flags "$@"
    header "Running Stripe Flaky Lifecycle Paths (Phase 3 only)"
    _test_show_flags

    local _stripe_owns_run_dir=0
    if [ -z "$_TEST_RUN_DIR" ]; then
        _test_init_run_dir "test_stripe_flaky"
        _stripe_owns_run_dir=1
    fi

    _test_stripe_preflight || { [ $_stripe_owns_run_dir -eq 1 ] && _test_finalize_run_dir 1; return 1; }

    if [ -z "${STRIPE_SECRET_KEY:-}" ] && [ -f ".env" ]; then
        local sk
        sk=$(grep '^STRIPE_SECRET_KEY=' .env | cut -d= -f2-)
        [ -n "$sk" ] && export STRIPE_SECRET_KEY="$sk" && info "Loaded STRIPE_SECRET_KEY from .env"
    fi
    if [ -z "${STRIPE_SECRET_KEY:-}" ]; then
        echo -e "${RED}[ERROR]${NC} STRIPE_SECRET_KEY not set. Required for Stripe integration tests."
        exit 1
    fi

    _stripe_cli_start
    local stripe_whsec
    stripe_whsec=$(_stripe_cli_wait_for_secret)
    if [ -n "$stripe_whsec" ]; then
        info "stripe-cli ready — webhook secret: ${stripe_whsec:0:12}..."
        export STRIPE_WEBHOOK_SECRET="$stripe_whsec"
    else
        warning "stripe-cli failed to start — flaky tests require real webhooks, aborting"
        _stripe_cli_stop
        [ $_stripe_owns_run_dir -eq 1 ] && _test_finalize_run_dir 1
        return 1
    fi

    local test_path="tests/test_stripe/"
    local phase3_result=0
    _test_run_flaky_with_retry "$test_path" "Stripe flaky (phase 3 only)" || phase3_result=$?

    _stripe_cli_stop
    _db_test_harvest_logs "test_stripe_flaky-end"

    if [ "$_TEST_TEARDOWN" = "1" ]; then
        info "--teardown: stopping all test containers (db-test)..."
        _test_stripe_teardown
    fi

    _test_summary_append "stripe phase 3 (flaky, standalone)" "$phase3_result"
    [ $_stripe_owns_run_dir -eq 1 ] && _test_finalize_run_dir "$phase3_result"
    return $phase3_result
}

# Pre-flight check for test:stripe runs.
# Fails loud if another test session is active (would share db-test schema /
# stripe-cli port) OR if dev/prod backend containers are up (they share the
# main DB or could interfere via docker-compose projects).
# Detects BOTH:
#   - Persistent `up` containers (`ironvolt_(backend|web)-1$`, `ironvolt_db-1$`)
#   - Ephemeral `docker compose run -*` containers (`ironvolt-backend-run-*`,
#     `ironvolt_test-backend-run-*`). These linger if a prior `run` was killed
#     or exited without `--rm` cleanup, and consume CPU/memory/DB connections.
# Use --force to override the check (not recommended).
_test_stripe_preflight() {
    info "Pre-flight: checking for interfering containers..."

    # 1) Current test session already active → hard abort.
    # Matches: ironvolt_test-backend-run-*, ironvolt_test-stripe-cli-1
    local active_test
    active_test=$(docker ps --format '{{.Names}}' | grep -E '^ironvolt_test-(backend-run|stripe-cli)' || true)
    if [ -n "$active_test" ]; then
        error "Another test session is active — would collide on db-test schema and stripe-cli."
        echo "$active_test" | sed 's/^/    /'
        if [ "$_TEST_FORCE" = "1" ]; then
            warning "--force set, continuing anyway (may produce false failures)."
        else
            echo "Wait for the other run to finish, or stop it with:"
            echo "    ./scripts/manage.sh test:clean"
            return 1
        fi
    fi

    # 2) Dev/prod containers — persistent `up` form (`_backend-1`, `_web-1`, `_db-1`).
    # These are the real dev stack: bind ports on the shared network, share
    # the same logical database, and always interfere with test isolation.
    local active_devprod_up
    active_devprod_up=$(docker ps --format '{{.Names}}' | grep -E '^ironvolt_(backend|web|db|redis)-1$' || true)

    # 3) Dev/prod containers — ephemeral `docker compose run -*` form
    # (`ironvolt-backend-run-*`). These are the lingering ad-hoc runs. They
    # don't bind host ports but still consume resources and can hold DB
    # connections. Always kill them before starting a test session.
    local active_devprod_run
    active_devprod_run=$(docker ps --format '{{.Names}}' | grep -E '^ironvolt-[a-z]+-run-' || true)

    local active_devprod="${active_devprod_up}${active_devprod_run:+$'\n'}${active_devprod_run}"
    if [ -n "$active_devprod" ]; then
        warning "Dev/prod containers active — would run in parallel with tests:"
        echo "$active_devprod" | sed 's/^/    /'
        if [ "$_TEST_FORCE" = "1" ]; then
            warning "--force set, continuing anyway."
        else
            info "Stopping interfering containers..."
            # cmd_down handles the persistent `up` containers via compose down.
            if [ -n "$active_devprod_up" ]; then
                cmd_down >/dev/null 2>&1 || true
            fi
            # Ephemeral `run -*` containers survive compose down (different project
            # scope / already exited managed containers). Kill them directly.
            if [ -n "$active_devprod_run" ]; then
                echo "$active_devprod_run" | xargs -r docker stop --time 5 >/dev/null 2>&1 || true
                echo "$active_devprod_run" | xargs -r docker rm -f >/dev/null 2>&1 || true
            fi
            # Recheck
            active_devprod_up=$(docker ps --format '{{.Names}}' | grep -E '^ironvolt_(backend|web|db|redis)-1$' || true)
            active_devprod_run=$(docker ps --format '{{.Names}}' | grep -E '^ironvolt-[a-z]+-run-' || true)
            if [ -n "$active_devprod_up" ] || [ -n "$active_devprod_run" ]; then
                error "Could not stop all interfering containers. Run './scripts/manage.sh down' and try again."
                docker ps --format '{{.Names}}' | grep ironvolt | sed 's/^/    /'
                return 1
            fi
            success "Interfering containers stopped."
        fi
    fi

    success "Pre-flight OK — no parallel containers running."
    return 0
}

# Tear down test containers (db-test). stripe-cli is stopped via _stripe_cli_stop
# separately. Ephemeral backend-run containers use --rm so self-clean.
_test_stripe_teardown() {
    _test_compose down -v --remove-orphans --timeout 5 >/dev/null 2>&1 || true
    success "Test containers down."
}

# Report all IronVolt docker containers active right now, tagged by role.
# Use this before running tests to see if parallel containers would collide.
cmd_test_status() {
    header "IronVolt container status"
    local all
    all=$(docker ps --format '{{.Names}}\t{{.Status}}' | grep -E '(ironvolt|iron_volt)' || true)
    if [ -z "$all" ]; then
        success "No IronVolt containers running."
        return 0
    fi
    echo
    echo -e "  ${BOLD}Name${NC}\t${BOLD}Status${NC}\t${BOLD}Role${NC}"
    while IFS=$'\t' read -r name status; do
        local role="unknown"
        case "$name" in
            ironvolt_test-backend-run-*) role="${GREEN}test backend (ephemeral)${NC}" ;;
            ironvolt_test-stripe-cli-*) role="${GREEN}test stripe-cli sidecar${NC}" ;;
            ironvolt_test-db-test-*) role="${DIM}test DB (persistent, OK)${NC}" ;;
            ironvolt-backend-run-*) role="${YELLOW}dev/prod ephemeral RUN${NC}" ;;
            ironvolt_backend-1|ironvolt_web-1|ironvolt_db-1|ironvolt_redis-1) role="${YELLOW}dev/prod UP${NC}" ;;
            *) role="${DIM}other${NC}" ;;
        esac
        echo -e "  $name\t$status\t$role"
    done <<< "$all"
    echo
}

# Stop ALL IronVolt containers — test (incl. db-test), dev/prod, ephemeral, persistent.
# Use this after a bad run to get back to a fully clean state.
# By default tears down EVERYTHING including db-test (next run will re-init schema).
# Pass --keep-db to preserve db-test (faster re-run when iterating).
cmd_test_clean() {
    header "Cleaning IronVolt containers"
    local keep_db=0
    for arg in "$@"; do
        [ "$arg" = "--keep-db" ] && keep_db=1
    done

    info "Stopping dev/prod (compose down)..."
    cmd_down >/dev/null 2>&1 || true

    info "Killing ephemeral run containers..."
    local ephemeral
    ephemeral=$(docker ps -a --format '{{.Names}}' | grep -E '^ironvolt(_test)?-[a-z]+-run-' || true)
    if [ -n "$ephemeral" ]; then
        echo "$ephemeral" | xargs -r docker stop --time 5 >/dev/null 2>&1 || true
        echo "$ephemeral" | xargs -r docker rm -f >/dev/null 2>&1 || true
    fi

    info "Stopping stripe-cli sidecar (if running)..."
    _stripe_cli_stop >/dev/null 2>&1 || true

    if [ "$keep_db" = "1" ]; then
        info "Keeping test DB (--keep-db)..."
    else
        info "Stopping test DB (default — use --keep-db to preserve)..."
        _test_compose down -v --remove-orphans --timeout 5 >/dev/null 2>&1 || true
    fi

    # Also prune any stopped zombies
    docker container prune -f --filter 'label=com.docker.compose.project=ironvolt*' >/dev/null 2>&1 || true

    success "Cleanup done. Remaining IronVolt containers:"
    local remaining
    remaining=$(docker ps --format '{{.Names}}' | grep ironvolt || true)
    if [ -z "$remaining" ]; then
        echo "    (none)"
    else
        echo "$remaining" | sed 's/^/    /'
    fi
}

# ── stripe-cli lifecycle helpers ──────────────────────────────────

_stripe_cli_start() {
    local project_flags
    project_flags=$(get_test_project_flags)

    info "Starting stripe-cli sidecar..."
    COMPOSE_PROJECT_NAME="$TEST_PROJECT_NAME" \
        $COMPOSE_CMD $project_flags \
        -f "$COMPOSE_FILE" -f "$COMPOSE_TEST_FILE" \
        --profile stripe \
        up -d stripe-cli 2>/dev/null
}

_stripe_cli_wait_for_secret() {
    local project_flags
    project_flags=$(get_test_project_flags)
    local attempt=0
    local max_attempts=30

    while [ $attempt -lt $max_attempts ]; do
        local whsec
        whsec=$(COMPOSE_PROJECT_NAME="$TEST_PROJECT_NAME" \
            $COMPOSE_CMD $project_flags \
            -f "$COMPOSE_FILE" -f "$COMPOSE_TEST_FILE" \
            logs stripe-cli 2>&1 | grep -oP 'whsec_\S+' | head -1)
        if [ -n "$whsec" ]; then
            echo "$whsec"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 1
    done
    return 1
}

_stripe_cli_stop() {
    local project_flags
    project_flags=$(get_test_project_flags)

    # Harvest logs before destroying the container — once stopped/removed,
    # `docker logs` returns nothing. This captures the last window of
    # forwarding activity so post-mortems don't miss webhook-level errors.
    _stripe_cli_harvest_logs "" "before-stop" 2>/dev/null || true

    info "Stopping stripe-cli sidecar..."
    COMPOSE_PROJECT_NAME="$TEST_PROJECT_NAME" \
        $COMPOSE_CMD $project_flags \
        -f "$COMPOSE_FILE" -f "$COMPOSE_TEST_FILE" \
        --profile stripe \
        stop stripe-cli 2>/dev/null
    COMPOSE_PROJECT_NAME="$TEST_PROJECT_NAME" \
        $COMPOSE_CMD $project_flags \
        -f "$COMPOSE_FILE" -f "$COMPOSE_TEST_FILE" \
        --profile stripe \
        rm -f stripe-cli 2>/dev/null
}

# ── stripe-cli log harvesting ──────────────────────────────────
#
# stripe-cli runs as a separate container from the backend test container.
# Its stdout contains webhook-level events (dispatched, forwarded, errors)
# that are invisible to pytest because pytest only sees backend responses.
# A webhook that fails forwarding (DNS race after sidecar restart, 5xx from
# backend, connection refused) is logged by stripe-cli but may leave a test
# passing or failing ambiguously. This helper captures the sidecar log into
# a common host-side file so it can be reviewed alongside pytest output.
#
# Args:
#   $1 = host log path (default: /tmp/test_results_stripe_cli.log)
#   $2 = context tag (e.g. "[heavy 2/3] TestPath4...")
_stripe_cli_harvest_logs() {
    # Default target: unified run dir if active, else /tmp (legacy fallback).
    local host_log="${1:-}"
    if [ -z "$host_log" ]; then
        if [ -n "$_TEST_RUN_DIR" ]; then
            host_log="$_TEST_RUN_DIR/stripe_cli.log"
        else
            host_log="/tmp/test_results_stripe_cli.log"
        fi
    fi
    local context="${2:-}"

    local sidecar
    sidecar=$(docker ps -a --format '{{.Names}}' 2>/dev/null | grep -E '^ironvolt_test-stripe-cli-' | head -1 || true)
    [ -z "$sidecar" ] && return 0

    mkdir -p "$(dirname "$host_log")" 2>/dev/null || true

    {
        echo ""
        echo "────────────────────────────────────────────────────────────────"
        echo "[stripe-cli harvest] $(date -Iseconds) container=$sidecar context=${context:-n/a}"
        echo "────────────────────────────────────────────────────────────────"
        docker logs "$sidecar" 2>&1 || echo "(docker logs failed — container may already be gone)"
    } >> "$host_log"

    # Surface error-like lines to stdout so the run log shows them inline
    local err_count
    err_count=$(docker logs "$sidecar" 2>&1 | grep -cE '\[ERROR\]|\[5[0-9]{2}\]|refused|timeout|lookup .* no such host' || true)
    err_count=${err_count:-0}
    if [ "$err_count" -gt 0 ]; then
        warning "[stripe-cli] ${err_count} error-like line(s) detected in sidecar (context=${context:-n/a}). First 10:"
        docker logs "$sidecar" 2>&1 | grep -E '\[ERROR\]|\[5[0-9]{2}\]|refused|timeout|lookup .* no such host' | head -10 | sed 's/^/    /'
        info "[stripe-cli] Full sidecar log appended to: $host_log"
    fi
    return 0
}

# Deprecation shim: test:coverage → test --coverage
cmd_test_coverage_deprecated() {
    warning "'test:coverage' has been removed."
    info "Use instead: $0 test --coverage"
    info "  You can also combine: $0 test --coverage --debug"
    exit 1
}

# Start test infrastructure (db-test only, backend runs via 'docker compose run')
cmd_test_up() {
    header "Starting Test Infrastructure - Project: $TEST_PROJECT_NAME"
    local project_flags=$(get_test_project_flags)
    info "Starting test database..."
    COMPOSE_PROJECT_NAME="$TEST_PROJECT_NAME" $COMPOSE_CMD $project_flags -f "$COMPOSE_FILE" -f "$COMPOSE_TEST_FILE" up -d --no-deps db-test
    success "Test infrastructure started!"
}

# Stop and remove test containers
cmd_test_down() {
    header "Stopping Test Infrastructure - Project: $TEST_PROJECT_NAME"
    local project_flags=$(get_test_project_flags)
    info "Stopping and removing test containers..."
    COMPOSE_PROJECT_NAME="$TEST_PROJECT_NAME" $COMPOSE_CMD $project_flags -f "$COMPOSE_FILE" -f "$COMPOSE_TEST_FILE" down --remove-orphans
    success "Test infrastructure stopped!"
}

# View test logs from Docker volume
cmd_test_logs() {
    local lines="100"
    local mode="last"
    for arg in "$@"; do
        if [ "$arg" = "-f" ] || [ "$arg" = "follow" ]; then
            mode="follow"
        elif [[ "$arg" =~ ^[0-9]+$ ]]; then
            lines="$arg"
        fi
    done
    header "Test Logs"

    local volume_name="${PROJECT_NAME}_backend_logs"
    local log_file="test_results.log"

    if ! docker run --rm -v "$volume_name:/logs" alpine test -f "/logs/$log_file" 2>/dev/null; then
        warn "No test log file found in volume $volume_name"
        info "Run './scripts/manage.sh test' first to generate logs."
        return 1
    fi

    if [ "$mode" = "follow" ] || [ "$mode" = "-f" ]; then
        info "Following test logs (Ctrl+C to stop)..."
        echo ""
        docker run --rm -v "$volume_name:/logs" alpine tail -n "$lines" -f "/logs/$log_file"
    else
        info "Showing last $lines lines of test logs..."
        info "Use '$0 test:logs $lines -f' to follow in real time"
        echo ""
        docker run --rm -v "$volume_name:/logs" alpine tail -n "$lines" "/logs/$log_file"
    fi
}

# List available test modules organized by category
cmd_test_list() {
    header "Available Test Modules"
    echo ""
    echo -e "  ${BOLD}${BLUE}API Tests${NC} ${DIM}(test:api)${NC}${BOLD}:${NC}"
    echo ""
    echo -e "  ${BOLD}Core:${NC}"
    echo "    auth, users, courses, billing, credits, payments, financial"
    echo ""
    echo -e "  ${BOLD}Features:${NC}"
    echo "    blog, banners, geo, location, theme, modules, messaging"
    echo "    membership_lifecycle, fifo_credit_allocation"
    echo "    crud_protections, email_send_integration"
    echo "    settings, doc_templates, document_templates"
    echo "    categories, files, help, legal_documents"
    echo "    reports, stats, storage_audit, subscriptions"
    echo "    attendance_extended, audit_events"
    echo ""
    echo -e "  ${BOLD}Deep API:${NC}"
    echo "    banners_deep, billing_deep, doc_templates_deep"
    echo "    messaging_deep, settings_deep, users_deep"
    echo ""
    echo -e "  ${BOLD}Extended API:${NC}"
    echo "    auth_extended, billing_extended, blog_extended"
    echo "    booking_extended, campaigns_extended, credits_extended"
    echo "    doc_templates_extended, financial_extended, geo_extended"
    echo "    messaging_extended, payments_extended, settings_extended"
    echo "    subscriptions_extended, theme_extended, users_extended"
    echo ""
    echo -e "  ${BOLD}Timezone:${NC}"
    echo "    timezone_attendance_courses, timezone_bookings, timezone_documents"
    echo "    timezone_memberships, timezone_stats_billing"
    echo ""
    echo -e "  ${BOLD}E-Commerce:${NC}"
    echo "    ecommerce_catalog, ecommerce_cart, ecommerce_checkout"
    echo "    ecommerce_orders, ecommerce_inventory"
    echo "    ecommerce_webhooks, ecommerce_integrations, ecommerce_regression"
    echo ""
    echo -e "  ${BOLD}Background Tasks${NC} ${YELLOW}(slow - use test:bg)${NC}${BOLD}:${NC}"
    echo "    background_tasks, background_tasks_long_running"
    echo "    background_tasks_multiworker, background_tasks_self_test"
    echo ""
    echo -e "  ${BOLD}${BLUE}Unit Tests${NC} ${DIM}(test:unit)${NC}${BOLD}:${NC}"
    echo -e "  ${DIM}Location: tests/test_unit/ (auto-discovered recursively)${NC}"
    echo ""
    echo -e "  ${BOLD}services/:${NC}"
    echo "    auth_service, billing_service, blog_service, booking_service"
    echo "    course_service, email_service, stats_service, theme_service"
    echo "    user_service, invoice_state_manager, logging"
    echo ""
    echo -e "  ${BOLD}services/ (e-commerce):${NC}"
    echo "    ecommerce_pricing, ecommerce_state_machines, ecommerce_state_machines_full"
    echo "    ecommerce_stock, ecommerce_checkout, ecommerce_cart"
    echo "    ecommerce_locks, ecommerce_misc"
    echo "    ecommerce_integration_checkout, ecommerce_integration_refund"
    echo "    ecommerce_integration_webhooks, ecommerce_integration_billing"
    echo "    ecommerce_integration_amazon, ecommerce_integration_ysell"
    echo ""
    echo -e "  ${BOLD}storage/:${NC}"
    echo "    storage_service"
    echo ""
    echo -e "  ${BOLD}templates/:${NC}"
    echo "    document_templates_unit"
    echo ""
    echo -e "${BOLD}Commands:${NC}"
    echo "  $0 test                             # Run all tests (API + Unit, excluding bg)"
    echo "  $0 test:api                         # Run only API tests (excluding bg)"
    echo "  $0 test:unit                        # Run only unit tests (fast)"
    echo "  $0 test:bg                          # Run only background task tests (slow)"
    echo "  $0 test:full                        # Run FULL suite: Unit→API→BG→Stripe+teardown"
    echo "  $0 test:module auth                 # Run a specific module (auto-finds location)"
    echo ""
    echo -e "${BOLD}Combinable Flags:${NC}"
    echo "  --debug, -d       Verbose logging (LOG_LEVEL=DEBUG, long tracebacks)"
    echo "  --coverage, -c    Generate HTML coverage report"
    echo "  --email           Enable real email sending (TEST_FAST=0)"
    echo "  --build, -b       Rebuild test images (default: ON)"
    echo "  --no-build        Skip rebuild (opt-out, uses existing image)"
    echo "  --build-no-cache  Rebuild test images without Docker cache"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo "  $0 test --debug --coverage          # All tests with debug + coverage"
    echo "  $0 test:api -c                      # API tests with coverage"
    echo "  $0 test:unit -d                     # Unit tests with debug"
    echo "  $0 test:bg --email                  # Background tests with real emails"
    echo "  $0 test:module billing -d -c        # Billing tests, debug + coverage"
    echo "  $0 test:module invoice_state_manager # Unit test module (auto-detected)"
    echo "  $0 test:module messaging --build    # Rebuild + run messaging tests"
    echo "  $0 test:module ecommerce -d         # All e-commerce tests (prefix match, 22 files)"
    echo ""
}

# ===========================================
# Health Commands
# ===========================================
cmd_health() {
    header "Health Check - All Services"
    
    echo -e "${BOLD}Checking service health...${NC}\n"
    
    # Check Frontend
    echo -n "Frontend (Nginx):    "
    if curl -sf http://localhost/health > /dev/null 2>&1; then
        echo -e "${GREEN}HEALTHY${NC}"
    elif curl -sf http://localhost > /dev/null 2>&1; then
        echo -e "${GREEN}RUNNING${NC}"
    else
        echo -e "${RED}UNHEALTHY${NC}"
    fi
    
    # Check Backend (port 5008 in dev, 5001 in prod)
    echo -n "Backend (Flask):     "
    if curl -sf http://localhost:5008/api/health > /dev/null 2>&1; then
        echo -e "${GREEN}HEALTHY${NC}"
    elif curl -sf http://localhost:5001/api/health > /dev/null 2>&1; then
        echo -e "${GREEN}HEALTHY${NC} (production port)"
    else
        echo -e "${RED}UNHEALTHY${NC}"
    fi
    
    # Check Database
    get_db_credentials
    echo -n "Database (PostgreSQL): "
    if docker exec "$DB_CONTAINER" pg_isready -U "$DB_USER" -d "$DB_NAME" > /dev/null 2>&1; then
        echo -e "${GREEN}HEALTHY${NC}"
    else
        echo -e "${RED}UNHEALTHY${NC}"
    fi
    
    # Check MinIO
    echo -n "MinIO (Storage):     "
    if curl -sf http://localhost:9000/minio/health/live > /dev/null 2>&1; then
        echo -e "${GREEN}HEALTHY${NC}"
    else
        echo -e "${YELLOW}NOT RUNNING${NC} (optional in dev mode)"
    fi
    
    echo ""
}

cmd_diagnose() {
    local port="${1:-}"
    
    header "Diagnostics - Port and Container Analysis"
    
    # Show configured ports from compose files
    echo -e "${BOLD}Configured Ports from Compose Files:${NC}"
    echo "  docker-compose.yml:"
    grep -E '^\s*-\s*"[0-9]+:[0-9]+"' docker-compose.yml 2>/dev/null | sed 's/^/    /' || echo "    (none found)"
    echo "  docker-compose.dev.yml:"
    grep -E '^\s*-\s*"[0-9]+:[0-9]+"' docker-compose.dev.yml 2>/dev/null | sed 's/^/    /' || echo "    (none found)"
    echo ""
    
    # Show project containers using Docker Compose label for exact matching
    echo -e "${BOLD}Project Containers ($PROJECT_NAME):${NC}"
    docker ps -a --filter "label=com.docker.compose.project=${PROJECT_NAME}" --format "{{.Names}}: {{.Status}} | Ports: {{.Ports}}" 2>/dev/null | sed 's/^/  /' || echo "  (none running)"
    echo ""
    
    # Show all containers with port bindings
    echo -e "${BOLD}All Docker Containers with Port Bindings:${NC}"
    docker ps --format "  {{.Names}}: {{.Ports}}" 2>/dev/null | grep -v "^$" || echo "  (none)"
    echo ""
    
    # If specific port requested, analyze it
    if [ -n "$port" ]; then
        echo -e "${BOLD}Analysis for Port $port:${NC}"
        
        # Check with ss
        echo "  Socket status (ss):"
        ss -tlnp 2>/dev/null | grep ":$port " | sed 's/^/    /' || echo "    Port $port is free (not in use)"
        
        # Check with netstat as fallback
        if command -v netstat &>/dev/null; then
            echo "  Socket status (netstat):"
            netstat -tlnp 2>/dev/null | grep ":$port " | sed 's/^/    /' || echo "    Port $port is free"
        fi
        
        # Check docker containers using this port
        echo "  Docker containers binding to port $port:"
        docker ps --format "{{.Names}}: {{.Ports}}" 2>/dev/null | grep "$port->" | sed 's/^/    /' || echo "    (none)"
        
        # Check with lsof if available
        if command -v lsof &>/dev/null; then
            echo "  Process using port $port (lsof):"
            lsof -i :$port 2>/dev/null | tail -n +2 | sed 's/^/    /' || echo "    (none found)"
        fi
    else
        # Default ports to check
        echo -e "${BOLD}Common Iron & Volt Ports Status:${NC}"
        for p in 80 443 5000 5001 5005 5008 5432 9000 9001; do
            local status=$(check_port_available "$p" 2>/dev/null || echo "error")
            if [ "$status" = "free" ]; then
                echo -e "  Port $p: ${GREEN}FREE${NC}"
            elif [ "$status" = "ironvolt" ]; then
                echo -e "  Port $p: ${BLUE}IRONVOLT${NC}"
            else
                echo -e "  Port $p: ${RED}IN USE${NC} - $status"
            fi
        done
    fi
    
    echo ""
    info "To diagnose a specific port: $0 diagnose <port>"
    echo ""
}

# ===========================================
# Environment Commands
# ===========================================
cmd_env_generate() {
    # Parse flags
    local REGENERATE_SECRETS=false
    for arg in "$@"; do
        case "$arg" in
            --regenerate-secrets|--secrets)
                REGENERATE_SECRETS=true
                ;;
        esac
    done
    
    header "Environment Configuration Generator"
    if [ "$REGENERATE_SECRETS" = true ]; then
        echo ""
        echo -e "  ${YELLOW}⚠  Secret regeneration mode${NC}"
        echo -e "  ${GREEN}[REGENERATE]${NC} JWT_SECRET_KEY, INTERNAL_API_SECRET (stateless — safe to rotate)"
        echo -e "  ${CYAN}[PROTECTED]${NC}  POSTGRES_PASSWORD, MINIO_ROOT_PASSWORD (stateful — changing breaks connections)"
        echo ""
    fi
    
    local ENV_TARGET=".env"
    local ENV_TEMPLATE=".env.example"
    local UPDATE_MODE=false
    
    if [ ! -f "$ENV_TEMPLATE" ]; then
        error ".env.example not found. Cannot generate .env without template."
    fi
    
    if [ -f "$ENV_TARGET" ]; then
        warning ".env already exists."
        echo -n "Update it (add missing variables, keep existing values)? [Y/n]: "
        read -r confirm
        if [[ "$confirm" =~ ^[Nn]$ ]]; then
            info "Generation cancelled."
            return 0
        fi
        UPDATE_MODE=true
        info "Update mode: existing values will be preserved, missing variables will be added."
    fi
    
    # Helper: read existing value from .env or return empty
    get_existing() {
        local key="$1"
        if [ "$UPDATE_MODE" = true ] && [ -f "$ENV_TARGET" ]; then
            grep -E "^${key}=" "$ENV_TARGET" 2>/dev/null | head -1 | cut -d'=' -f2- || true
        fi
    }
    
    # Helper: prompt user for value with default
    # Uses /dev/tty for prompt and input so it works inside $() captures
    ask_value() {
        local key="$1"
        local description="$2"
        local default_val="$3"
        local existing=$(get_existing "$key")
        local actual_default="${existing:-$default_val}"
        local input=""
        
        if [ -n "$actual_default" ]; then
            echo -n "  $description [$actual_default]: " > /dev/tty
            read -r input < /dev/tty || true
            echo "${input:-$actual_default}"
        else
            echo -n "  $description: " > /dev/tty
            read -r input < /dev/tty || true
            echo "$input"
        fi
    }
    
    # Helper: generate secure random string
    generate_secret() {
        openssl rand -base64 48 | tr -d '/+=' | head -c 40
    }
    
    echo ""
    echo -e "${BOLD}${BLUE}[1/6] Project Configuration${NC}"
    echo ""
    local val_project=$(ask_value "COMPOSE_PROJECT_NAME" "Project name" "ironvolt")
    local val_frontend_port=$(ask_value "FRONTEND_PORT" "Frontend port" "5005")
    local val_backend_port=$(ask_value "BACKEND_PORT" "Backend API port" "5004")
    local val_db_port=$(ask_value "DB_PORT" "Database port" "5435")
    local val_minio_api_port=$(ask_value "MINIO_API_PORT" "MinIO API port" "9000")
    local val_minio_console_port=$(ask_value "MINIO_CONSOLE_PORT" "MinIO Console port" "9001")
    
    echo ""
    echo -e "${BOLD}${BLUE}[2/6] Database Configuration${NC}"
    echo ""
    local val_pg_user=$(ask_value "POSTGRES_USER" "PostgreSQL user" "$val_project")
    local val_pg_db=$(ask_value "POSTGRES_DB" "PostgreSQL database" "$val_project")
    local existing_pg_pass=$(get_existing "POSTGRES_PASSWORD")
    local val_pg_pass="${existing_pg_pass}"
    if [ -z "$val_pg_pass" ] || [ "$val_pg_pass" = "CHANGE_ME_postgres_password" ]; then
        val_pg_pass=$(generate_secret)
        echo -e "  ${GREEN}[AUTO]${NC} POSTGRES_PASSWORD generated"
    elif [ "$REGENERATE_SECRETS" = true ]; then
        echo -e "  ${CYAN}[PROTECTED]${NC} POSTGRES_PASSWORD (stateful service — change requires ALTER USER in PostgreSQL)"
    else
        echo -e "  ${CYAN}[KEPT]${NC} POSTGRES_PASSWORD (existing value preserved)"
    fi
    
    echo ""
    echo -e "${BOLD}${BLUE}[3/6] Security${NC}"
    echo ""
    local existing_jwt=$(get_existing "JWT_SECRET_KEY")
    local val_jwt="${existing_jwt}"
    if [ -z "$val_jwt" ] || [ "$val_jwt" = "CHANGE_ME_jwt_secret_key" ] || [ "$REGENERATE_SECRETS" = true ]; then
        val_jwt=$(generate_secret)
        echo -e "  ${GREEN}[AUTO]${NC} JWT_SECRET_KEY generated"
    else
        echo -e "  ${CYAN}[KEPT]${NC} JWT_SECRET_KEY (existing value preserved)"
    fi
    local val_jwt_access_minutes=$(ask_value "JWT_ACCESS_TOKEN_MINUTES" "Access token lifetime (minutes)" "30")
    local val_jwt_refresh_minutes=$(ask_value "JWT_REFRESH_TOKEN_MINUTES" "Refresh token lifetime (minutes, 60=1hour)" "60")
    local existing_internal_secret=$(get_existing "INTERNAL_API_SECRET")
    local val_internal_secret="${existing_internal_secret}"
    if [ -z "$val_internal_secret" ] || [ "$val_internal_secret" = "CHANGE_ME_internal_api_secret" ] || [ "$REGENERATE_SECRETS" = true ]; then
        val_internal_secret=$(generate_secret)
        echo -e "  ${GREEN}[AUTO]${NC} INTERNAL_API_SECRET generated"
    else
        echo -e "  ${CYAN}[KEPT]${NC} INTERNAL_API_SECRET (existing value preserved)"
    fi
    
    echo ""
    echo -e "${BOLD}${BLUE}[4/6] Storage (MinIO)${NC}"
    echo ""
    local val_minio_user=$(ask_value "MINIO_ROOT_USER" "MinIO admin user" "minioadmin")
    local val_minio_bucket=$(ask_value "MINIO_BUCKET" "MinIO bucket name" "$val_project")
    local val_minio_public_url=$(ask_value "MINIO_PUBLIC_URL" "MinIO public URL" "http://localhost:${val_minio_api_port}")
    local existing_minio_pass=$(get_existing "MINIO_ROOT_PASSWORD")
    local val_minio_pass="${existing_minio_pass}"
    if [ -z "$val_minio_pass" ] || [ "$val_minio_pass" = "CHANGE_ME_minio_password" ]; then
        val_minio_pass=$(generate_secret)
        echo -e "  ${GREEN}[AUTO]${NC} MINIO_ROOT_PASSWORD generated"
    elif [ "$REGENERATE_SECRETS" = true ]; then
        echo -e "  ${CYAN}[PROTECTED]${NC} MINIO_ROOT_PASSWORD (stateful service — change requires MinIO reconfiguration)"
    else
        echo -e "  ${CYAN}[KEPT]${NC} MINIO_ROOT_PASSWORD (existing value preserved)"
    fi
    
    echo ""
    echo -e "${BOLD}${BLUE}[5/6] Frontend & Email${NC}"
    echo ""
    local val_frontend_url=$(ask_value "FRONTEND_URL" "Public frontend URL" "https://your-domain.com")
    echo ""
    info "Email configuration (leave defaults to configure later):"
    local val_mail_server=$(ask_value "MAIL_SERVER" "SMTP server" "smtp.example.com")
    local val_mail_port=$(ask_value "MAIL_PORT" "SMTP port" "587")
    local val_mail_tls=$(ask_value "MAIL_USE_TLS" "Use STARTTLS - port 587 (true/false)" "true")
    local val_mail_ssl=$(ask_value "MAIL_USE_SSL" "Use SSL - port 465 (true/false)" "false")
    local val_mail_user=$(ask_value "MAIL_USERNAME" "SMTP username" "your_email@example.com")
    local val_mail_pass=$(ask_value "MAIL_PASSWORD" "SMTP password" "CHANGE_ME_mail_password")
    local val_mail_sender=$(ask_value "MAIL_DEFAULT_SENDER" "Default sender email" "$val_mail_user")
    
    # Preserve existing Stripe/PayPal/reCAPTCHA/Dark Visitors values or use placeholders
    local val_stripe_test_sk=$(get_existing "STRIPE_TEST_SECRET_KEY")
    local val_stripe_test_pk=$(get_existing "STRIPE_TEST_PUBLISHABLE_KEY")
    local val_stripe_test_wh=$(get_existing "STRIPE_TEST_WEBHOOK_SECRET")
    local val_stripe_live_sk=$(get_existing "STRIPE_LIVE_SECRET_KEY")
    local val_stripe_live_pk=$(get_existing "STRIPE_LIVE_PUBLISHABLE_KEY")
    local val_stripe_live_wh=$(get_existing "STRIPE_LIVE_WEBHOOK_SECRET")
    local val_stripe_sk=$(get_existing "STRIPE_SECRET_KEY")
    local val_stripe_pk=$(get_existing "STRIPE_PUBLISHABLE_KEY")
    local val_stripe_wh=$(get_existing "STRIPE_WEBHOOK_SECRET")
    local val_paypal_test_cid=$(get_existing "PAYPAL_TEST_CLIENT_ID")
    local val_paypal_test_cs=$(get_existing "PAYPAL_TEST_CLIENT_SECRET")
    local val_paypal_test_wh=$(get_existing "PAYPAL_TEST_WEBHOOK_ID")
    local val_paypal_live_cid=$(get_existing "PAYPAL_LIVE_CLIENT_ID")
    local val_paypal_live_cs=$(get_existing "PAYPAL_LIVE_CLIENT_SECRET")
    local val_paypal_live_wh=$(get_existing "PAYPAL_LIVE_WEBHOOK_ID")
    local val_paypal_mode=$(get_existing "PAYPAL_MODE")
    local val_paypal_cid=$(get_existing "PAYPAL_CLIENT_ID")
    local val_paypal_cs=$(get_existing "PAYPAL_CLIENT_SECRET")
    local val_paypal_wh=$(get_existing "PAYPAL_WEBHOOK_ID")
    local val_recaptcha_site=$(get_existing "RECAPTCHA_SITE_KEY")
    local val_recaptcha_secret=$(get_existing "RECAPTCHA_SECRET_KEY")
    local val_dark_visitors=$(get_existing "DARK_VISITORS_API_KEY")
    
    echo ""
    echo -e "${BOLD}${BLUE}[6/6] E-Commerce Integrations${NC}"
    echo ""
    info "Amazon SP-API (leave empty to configure later in Admin Panel):"
    local val_amazon_client_id=$(ask_value "AMAZON_SP_CLIENT_ID" "Amazon SP-API Client ID" "")
    local val_amazon_client_secret=$(ask_value "AMAZON_SP_CLIENT_SECRET" "Amazon SP-API Client Secret" "")
    local val_amazon_refresh_token=$(ask_value "AMAZON_SP_REFRESH_TOKEN" "Amazon SP-API Refresh Token" "")
    local val_amazon_marketplace_id=$(ask_value "AMAZON_MARKETPLACE_ID" "Amazon Marketplace ID" "A1RKKUPIHCS9HS")
    local val_amazon_seller_id=$(ask_value "AMAZON_SELLER_ID" "Amazon Seller ID" "")
    local val_amazon_mode=$(ask_value "AMAZON_MODE" "Amazon mode (simulated/production)" "simulated")
    echo ""
    info "Ysell WMS (leave empty to configure later in Admin Panel):"
    local val_ysell_api_key=$(ask_value "YSELL_API_KEY" "Ysell API Key" "")
    local val_ysell_api_secret=$(ask_value "YSELL_API_SECRET" "Ysell API Secret" "")
    local val_ysell_warehouse_id=$(ask_value "YSELL_WAREHOUSE_ID" "Ysell Warehouse ID" "")
    local val_ysell_base_url=$(ask_value "YSELL_BASE_URL" "Ysell Base URL" "")
    local val_ysell_mode=$(ask_value "YSELL_MODE" "Ysell mode (simulated/production)" "simulated")
    
    # Preserve other existing values
    local val_log_level=$(get_existing "LOG_LEVEL")
    local val_gunicorn_workers=$(get_existing "GUNICORN_WORKERS")
    local val_gunicorn_threads=$(get_existing "GUNICORN_THREADS")
    local val_gunicorn_timeout=$(get_existing "GUNICORN_TIMEOUT")
    
    # Write the .env file
    echo ""
    info "Writing $ENV_TARGET..."
    
    cat > "$ENV_TARGET" << ENVEOF
# ===========================================
# Iron & Volt - Environment Configuration
# ===========================================
# Generated by: ./scripts/manage.sh env:generate
# Generated at: $(date '+%Y-%m-%d %H:%M:%S')
# ===========================================

# ===========================================
# Docker Project Configuration
# ===========================================
COMPOSE_PROJECT_NAME=${val_project}

# ===========================================
# Port Configuration
# ===========================================
FRONTEND_PORT=${val_frontend_port}
BACKEND_PORT=${val_backend_port}
DB_PORT=${val_db_port}
MINIO_API_PORT=${val_minio_api_port}
MINIO_CONSOLE_PORT=${val_minio_console_port}

# ===========================================
# Database Configuration (PostgreSQL)
# ===========================================
POSTGRES_USER=${val_pg_user}
POSTGRES_PASSWORD=${val_pg_pass}
POSTGRES_DB=${val_pg_db}

# ===========================================
# Application Security
# ===========================================
JWT_SECRET_KEY=${val_jwt}
JWT_ACCESS_TOKEN_MINUTES=${val_jwt_access_minutes}
JWT_REFRESH_TOKEN_MINUTES=${val_jwt_refresh_minutes}
INTERNAL_API_SECRET=${val_internal_secret}
FLASK_ENV=production
SEED_DATABASE=false

# ===========================================
# Stripe Payment Configuration
# ===========================================
STRIPE_TEST_SECRET_KEY=${val_stripe_test_sk:-sk_test_your_test_secret_key}
STRIPE_TEST_PUBLISHABLE_KEY=${val_stripe_test_pk:-pk_test_your_test_publishable_key}
STRIPE_TEST_WEBHOOK_SECRET=${val_stripe_test_wh:-whsec_your_test_webhook_secret}
STRIPE_LIVE_SECRET_KEY=${val_stripe_live_sk:-sk_live_your_live_secret_key}
STRIPE_LIVE_PUBLISHABLE_KEY=${val_stripe_live_pk:-pk_live_your_live_publishable_key}
STRIPE_LIVE_WEBHOOK_SECRET=${val_stripe_live_wh:-whsec_your_live_webhook_secret}
STRIPE_SECRET_KEY=${val_stripe_sk:-sk_test_your_test_secret_key}
STRIPE_PUBLISHABLE_KEY=${val_stripe_pk:-pk_test_your_test_publishable_key}
STRIPE_WEBHOOK_SECRET=${val_stripe_wh:-whsec_your_webhook_secret}

# ===========================================
# PayPal Payment Configuration
# ===========================================
# Sandbox (test) — get at https://developer.paypal.com/dashboard/applications/sandbox
PAYPAL_TEST_CLIENT_ID=${val_paypal_test_cid:-your_sandbox_client_id}
PAYPAL_TEST_CLIENT_SECRET=${val_paypal_test_cs:-your_sandbox_client_secret}
PAYPAL_TEST_WEBHOOK_ID=${val_paypal_test_wh:-your_sandbox_webhook_id}
# Live — get at https://developer.paypal.com/dashboard/applications/live
PAYPAL_LIVE_CLIENT_ID=${val_paypal_live_cid:-your_live_client_id}
PAYPAL_LIVE_CLIENT_SECRET=${val_paypal_live_cs:-your_live_client_secret}
PAYPAL_LIVE_WEBHOOK_ID=${val_paypal_live_wh:-your_live_webhook_id}
# Active bootstrap (Admin Panel > Settings > PayPal overrides via SystemSettings)
PAYPAL_MODE=${val_paypal_mode:-sandbox}
PAYPAL_CLIENT_ID=${val_paypal_cid:-your_sandbox_client_id}
PAYPAL_CLIENT_SECRET=${val_paypal_cs:-your_sandbox_client_secret}
PAYPAL_WEBHOOK_ID=${val_paypal_wh:-your_sandbox_webhook_id}

# ===========================================
# Email Configuration (SMTP)
# ===========================================
MAIL_SERVER=${val_mail_server}
MAIL_PORT=${val_mail_port}
MAIL_USE_TLS=${val_mail_tls}
MAIL_USE_SSL=${val_mail_ssl}
MAIL_USERNAME=${val_mail_user}
MAIL_PASSWORD=${val_mail_pass}
MAIL_DEFAULT_SENDER=${val_mail_sender}

# ===========================================
# reCAPTCHA Configuration
# ===========================================
RECAPTCHA_SITE_KEY=${val_recaptcha_site:-your_recaptcha_site_key}
RECAPTCHA_SECRET_KEY=${val_recaptcha_secret:-your_recaptcha_secret_key}

# ===========================================
# Storage Configuration
# ===========================================
STORAGE_PROVIDER=minio
MINIO_ROOT_USER=${val_minio_user}
MINIO_ROOT_PASSWORD=${val_minio_pass}
MINIO_BUCKET=${val_minio_bucket}
MINIO_PUBLIC_URL=${val_minio_public_url}
MINIO_SECURE=false

# ===========================================
# Frontend Configuration
# ===========================================
FRONTEND_URL=${val_frontend_url}
VITE_API_URL=http://localhost:5001
FLASK_URL=http://backend:5001

# ===========================================
# Dark Visitors Configuration
# ===========================================
DARK_VISITORS_API_KEY=${val_dark_visitors}

# ===========================================
# E-Commerce Integrations (Amazon SP-API + Ysell WMS)
# ===========================================
# Mode: 'simulated' (sandbox, no real API calls) or 'production' (real API calls)
AMAZON_SP_CLIENT_ID=${val_amazon_client_id}
AMAZON_SP_CLIENT_SECRET=${val_amazon_client_secret}
AMAZON_SP_REFRESH_TOKEN=${val_amazon_refresh_token}
AMAZON_MARKETPLACE_ID=${val_amazon_marketplace_id:-A1RKKUPIHCS9HS}
AMAZON_SELLER_ID=${val_amazon_seller_id}
AMAZON_MODE=${val_amazon_mode:-simulated}
YSELL_API_KEY=${val_ysell_api_key}
YSELL_API_SECRET=${val_ysell_api_secret}
YSELL_WAREHOUSE_ID=${val_ysell_warehouse_id}
YSELL_BASE_URL=${val_ysell_base_url}
YSELL_MODE=${val_ysell_mode:-simulated}

# ===========================================
# Logging Configuration
# ===========================================
LOG_LEVEL=${val_log_level:-WARNING}
LOG_DIR=/app/logs
LOG_MAX_BYTES=52428800
LOG_BACKUP_COUNT=10

# ===========================================
# Application Configuration
# ===========================================
APP_UID=1000
APP_GID=1000

# ===========================================
# Gunicorn Configuration (Production)
# ===========================================
GUNICORN_WORKERS=${val_gunicorn_workers:-4}
GUNICORN_THREADS=${val_gunicorn_threads:-2}
GUNICORN_TIMEOUT=${val_gunicorn_timeout:-120}
ENVEOF

    echo ""
    success ".env file generated successfully!"
    echo ""
    echo -e "${BOLD}Summary of auto-generated secrets:${NC}"
    if [ -z "$existing_pg_pass" ] || [ "$existing_pg_pass" = "CHANGE_ME_postgres_password" ]; then
        echo -e "  POSTGRES_PASSWORD   = ${YELLOW}${val_pg_pass}${NC}"
    fi
    if [ -z "$existing_jwt" ] || [ "$existing_jwt" = "CHANGE_ME_jwt_secret_key" ] || [ "$REGENERATE_SECRETS" = true ]; then
        echo -e "  JWT_SECRET_KEY      = ${YELLOW}${val_jwt}${NC}"
    fi
    if [ -z "$existing_internal_secret" ] || [ "$existing_internal_secret" = "CHANGE_ME_internal_api_secret" ] || [ "$REGENERATE_SECRETS" = true ]; then
        echo -e "  INTERNAL_API_SECRET = ${YELLOW}${val_internal_secret}${NC}"
    fi
    if [ -z "$existing_minio_pass" ] || [ "$existing_minio_pass" = "CHANGE_ME_minio_password" ]; then
        echo -e "  MINIO_ROOT_PASSWORD = ${YELLOW}${val_minio_pass}${NC}"
    fi
    echo ""
    warning "Save these secrets securely! They won't be shown again."
    echo ""
    info "Next steps:"
    echo "  1. Configure your Stripe keys in .env (get them from https://dashboard.stripe.com/apikeys)"
    echo "  2. Configure reCAPTCHA keys (get them from https://www.google.com/recaptcha/admin)"
    echo "  3. Update FRONTEND_URL with your actual domain"
    echo "  4. Run: $0 build && $0 up"
    echo ""
}

cmd_env_repair() {
    header "Environment File Repair & Normalization"
    
    local ENV_TARGET=".env"
    
    if [ ! -f "$ENV_TARGET" ]; then
        error "No .env file found. Use '$0 env:generate' to create one."
    fi
    
    # Create timestamped backup
    local backup_file=".env.backup.$(date '+%Y%m%d_%H%M%S')"
    cp "$ENV_TARGET" "$backup_file"
    success "Backup created: $backup_file"
    
    echo ""
    info "Analyzing current .env..."
    echo ""
    
    # Read all current values
    declare -A current_values
    local issues=()
    local fixes=()
    
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        
        if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*) ]]; then
            local key="${BASH_REMATCH[1]}"
            local val="${BASH_REMATCH[2]}"
            current_values["$key"]="$val"
        fi
    done < "$ENV_TARGET"
    
    # --- Detect and fix issues ---
    
    # 1. Legacy MinIO variables
    if [ -n "${current_values[MINIO_ACCESS_KEY]+x}" ]; then
        issues+=("MINIO_ACCESS_KEY is obsolete (docker-compose derives it from MINIO_ROOT_USER)")
        # If MINIO_ROOT_USER is missing, migrate the value
        if [ -z "${current_values[MINIO_ROOT_USER]+x}" ]; then
            current_values[MINIO_ROOT_USER]="${current_values[MINIO_ACCESS_KEY]}"
            fixes+=("Migrated MINIO_ACCESS_KEY -> MINIO_ROOT_USER")
        fi
        unset 'current_values[MINIO_ACCESS_KEY]'
        fixes+=("Removed MINIO_ACCESS_KEY")
    fi
    
    if [ -n "${current_values[MINIO_SECRET_KEY]+x}" ]; then
        issues+=("MINIO_SECRET_KEY is obsolete (docker-compose derives it from MINIO_ROOT_PASSWORD)")
        if [ -z "${current_values[MINIO_ROOT_PASSWORD]+x}" ]; then
            current_values[MINIO_ROOT_PASSWORD]="${current_values[MINIO_SECRET_KEY]}"
            fixes+=("Migrated MINIO_SECRET_KEY -> MINIO_ROOT_PASSWORD")
        fi
        unset 'current_values[MINIO_SECRET_KEY]'
        fixes+=("Removed MINIO_SECRET_KEY")
    fi
    
    if [ -n "${current_values[MINIO_USE_SSL]+x}" ]; then
        issues+=("MINIO_USE_SSL is obsolete (use MINIO_SECURE instead)")
        if [ -z "${current_values[MINIO_SECURE]+x}" ]; then
            current_values[MINIO_SECURE]="${current_values[MINIO_USE_SSL]}"
            fixes+=("Migrated MINIO_USE_SSL -> MINIO_SECURE")
        fi
        unset 'current_values[MINIO_USE_SSL]'
        fixes+=("Removed MINIO_USE_SSL")
    fi
    
    if [ -n "${current_values[MINIO_ENDPOINT]+x}" ]; then
        issues+=("MINIO_ENDPOINT is obsolete (hardcoded as minio:9000 in docker-compose)")
        unset 'current_values[MINIO_ENDPOINT]'
        fixes+=("Removed MINIO_ENDPOINT")
    fi
    
    # MAIL_USE_TLS is valid (used by docker-compose.yml and docker-compose.prod.yml)
    # Ensure it has a default if missing
    if [ -z "${current_values[MAIL_USE_TLS]+x}" ]; then
        current_values[MAIL_USE_TLS]="true"
        fixes+=("Added missing variable: MAIL_USE_TLS=true")
    fi
    
    # 2. Check for duplicate SEED_DATABASE
    local seed_count=$(grep -c "^SEED_DATABASE=" "$ENV_TARGET" 2>/dev/null || echo "0")
    if [ "$seed_count" -gt 1 ]; then
        issues+=("SEED_DATABASE appears $seed_count times")
        fixes+=("Deduplicated SEED_DATABASE (keeping last value)")
    fi
    
    # 3. Check for duplicate STRIPE_WEBHOOK_SECRET / RECAPTCHA_SITE_KEY
    for dup_key in STRIPE_WEBHOOK_SECRET RECAPTCHA_SITE_KEY; do
        local dup_count=$(grep -c "^${dup_key}=" "$ENV_TARGET" 2>/dev/null || echo "0")
        if [ "$dup_count" -gt 1 ]; then
            issues+=("$dup_key appears $dup_count times")
            fixes+=("Deduplicated $dup_key (keeping value)")
        fi
    done
    
    # 4. Ensure required variables exist with defaults
    local -A required_defaults=(
        [COMPOSE_PROJECT_NAME]="ironvolt"
        [FRONTEND_PORT]="5005"
        [BACKEND_PORT]="5004"
        [DB_PORT]="5435"
        [MINIO_API_PORT]="9000"
        [MINIO_CONSOLE_PORT]="9001"
        [FLASK_ENV]="production"
        [SEED_DATABASE]="false"
        [JWT_ACCESS_TOKEN_MINUTES]="30"
        [JWT_REFRESH_TOKEN_MINUTES]="60"
        [STORAGE_PROVIDER]="minio"
        [MINIO_SECURE]="false"
        [VITE_API_URL]="http://localhost:5001"
        [FLASK_URL]="http://backend:5001"
        [LOG_LEVEL]="WARNING"
        [LOG_DIR]="/app/logs"
        [LOG_MAX_BYTES]="52428800"
        [LOG_BACKUP_COUNT]="10"
        [APP_UID]="1000"
        [APP_GID]="1000"
        [GUNICORN_WORKERS]="4"
        [GUNICORN_THREADS]="2"
        [GUNICORN_TIMEOUT]="120"
        [AMAZON_MODE]="simulated"
        [YSELL_MODE]="simulated"
    )
    
    for key in "${!required_defaults[@]}"; do
        if [ -z "${current_values[$key]+x}" ]; then
            current_values[$key]="${required_defaults[$key]}"
            fixes+=("Added missing variable: $key=${required_defaults[$key]}")
        fi
    done
    
    # Helper to get value or empty string
    v() {
        echo "${current_values[$1]:-$2}"
    }
    
    # Report issues
    if [ ${#issues[@]} -eq 0 ]; then
        success "No issues found in .env"
    else
        echo -e "${BOLD}Issues found:${NC}"
        for issue in "${issues[@]}"; do
            echo -e "  ${YELLOW}!${NC} $issue"
        done
    fi
    
    echo ""
    
    if [ ${#fixes[@]} -eq 0 ] && [ ${#issues[@]} -eq 0 ]; then
        info "Your .env is already clean. No changes needed."
        rm -f "$backup_file"
        return 0
    fi
    
    echo -e "${BOLD}Fixes to apply:${NC}"
    for fix in "${fixes[@]}"; do
        echo -e "  ${GREEN}+${NC} $fix"
    done
    echo ""
    
    echo -n "Apply fixes and rewrite .env in normalized format? [Y/n]: "
    read -r confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        info "Repair cancelled. Backup removed."
        rm -f "$backup_file"
        return 0
    fi
    
    # Write normalized .env
    cat > "$ENV_TARGET" << ENVEOF
# ===========================================
# Iron & Volt - Environment Configuration
# ===========================================
# Repaired by: ./scripts/manage.sh env:repair
# Repaired at: $(date '+%Y-%m-%d %H:%M:%S')
# Backup: $backup_file
# ===========================================

# ===========================================
# Docker Project Configuration
# ===========================================
COMPOSE_PROJECT_NAME=$(v COMPOSE_PROJECT_NAME ironvolt)

# ===========================================
# Port Configuration
# ===========================================
FRONTEND_PORT=$(v FRONTEND_PORT 5005)
BACKEND_PORT=$(v BACKEND_PORT 5004)
DB_PORT=$(v DB_PORT 5435)
MINIO_API_PORT=$(v MINIO_API_PORT 9000)
MINIO_CONSOLE_PORT=$(v MINIO_CONSOLE_PORT 9001)

# ===========================================
# Database Configuration (PostgreSQL)
# ===========================================
POSTGRES_USER=$(v POSTGRES_USER ironvolt)
POSTGRES_PASSWORD=$(v POSTGRES_PASSWORD "")
POSTGRES_DB=$(v POSTGRES_DB ironvolt)

# ===========================================
# Application Security
# ===========================================
JWT_SECRET_KEY=$(v JWT_SECRET_KEY "")
JWT_ACCESS_TOKEN_MINUTES=$(v JWT_ACCESS_TOKEN_MINUTES 30)
JWT_REFRESH_TOKEN_MINUTES=$(v JWT_REFRESH_TOKEN_MINUTES 60)
INTERNAL_API_SECRET=$(v INTERNAL_API_SECRET "")
FLASK_ENV=$(v FLASK_ENV production)
SEED_DATABASE=$(v SEED_DATABASE false)

# ===========================================
# Stripe Payment Configuration
# ===========================================
STRIPE_TEST_SECRET_KEY=$(v STRIPE_TEST_SECRET_KEY "")
STRIPE_TEST_PUBLISHABLE_KEY=$(v STRIPE_TEST_PUBLISHABLE_KEY "")
STRIPE_TEST_WEBHOOK_SECRET=$(v STRIPE_TEST_WEBHOOK_SECRET "")
STRIPE_LIVE_SECRET_KEY=$(v STRIPE_LIVE_SECRET_KEY "")
STRIPE_LIVE_PUBLISHABLE_KEY=$(v STRIPE_LIVE_PUBLISHABLE_KEY "")
STRIPE_LIVE_WEBHOOK_SECRET=$(v STRIPE_LIVE_WEBHOOK_SECRET "")
STRIPE_SECRET_KEY=$(v STRIPE_SECRET_KEY "")
STRIPE_PUBLISHABLE_KEY=$(v STRIPE_PUBLISHABLE_KEY "")
STRIPE_WEBHOOK_SECRET=$(v STRIPE_WEBHOOK_SECRET "")

# ===========================================
# PayPal Payment Configuration
# ===========================================
PAYPAL_TEST_CLIENT_ID=$(v PAYPAL_TEST_CLIENT_ID "")
PAYPAL_TEST_CLIENT_SECRET=$(v PAYPAL_TEST_CLIENT_SECRET "")
PAYPAL_TEST_WEBHOOK_ID=$(v PAYPAL_TEST_WEBHOOK_ID "")
PAYPAL_LIVE_CLIENT_ID=$(v PAYPAL_LIVE_CLIENT_ID "")
PAYPAL_LIVE_CLIENT_SECRET=$(v PAYPAL_LIVE_CLIENT_SECRET "")
PAYPAL_LIVE_WEBHOOK_ID=$(v PAYPAL_LIVE_WEBHOOK_ID "")
PAYPAL_MODE=$(v PAYPAL_MODE sandbox)
PAYPAL_CLIENT_ID=$(v PAYPAL_CLIENT_ID "")
PAYPAL_CLIENT_SECRET=$(v PAYPAL_CLIENT_SECRET "")
PAYPAL_WEBHOOK_ID=$(v PAYPAL_WEBHOOK_ID "")

# ===========================================
# Email Configuration (SMTP)
# ===========================================
MAIL_SERVER=$(v MAIL_SERVER "")
MAIL_PORT=$(v MAIL_PORT 587)
MAIL_USE_TLS=$(v MAIL_USE_TLS true)
MAIL_USE_SSL=$(v MAIL_USE_SSL false)
MAIL_USERNAME=$(v MAIL_USERNAME "")
MAIL_PASSWORD=$(v MAIL_PASSWORD "")
MAIL_DEFAULT_SENDER=$(v MAIL_DEFAULT_SENDER "")

# ===========================================
# reCAPTCHA Configuration
# ===========================================
RECAPTCHA_SITE_KEY=$(v RECAPTCHA_SITE_KEY "")
RECAPTCHA_SECRET_KEY=$(v RECAPTCHA_SECRET_KEY "")

# ===========================================
# Storage Configuration
# ===========================================
STORAGE_PROVIDER=$(v STORAGE_PROVIDER minio)
MINIO_ROOT_USER=$(v MINIO_ROOT_USER minioadmin)
MINIO_ROOT_PASSWORD=$(v MINIO_ROOT_PASSWORD "")
MINIO_BUCKET=$(v MINIO_BUCKET ironvolt)
MINIO_PUBLIC_URL=$(v MINIO_PUBLIC_URL "http://localhost:9000")
MINIO_SECURE=$(v MINIO_SECURE false)

# ===========================================
# Frontend Configuration
# ===========================================
FRONTEND_URL=$(v FRONTEND_URL "")
VITE_API_URL=$(v VITE_API_URL "http://localhost:5001")
FLASK_URL=$(v FLASK_URL "http://backend:5001")

# ===========================================
# Dark Visitors Configuration
# ===========================================
DARK_VISITORS_API_KEY=$(v DARK_VISITORS_API_KEY "")

# ===========================================
# E-Commerce Integrations (Amazon SP-API + Ysell WMS)
# ===========================================
AMAZON_SP_CLIENT_ID=$(v AMAZON_SP_CLIENT_ID "")
AMAZON_SP_CLIENT_SECRET=$(v AMAZON_SP_CLIENT_SECRET "")
AMAZON_SP_REFRESH_TOKEN=$(v AMAZON_SP_REFRESH_TOKEN "")
AMAZON_MARKETPLACE_ID=$(v AMAZON_MARKETPLACE_ID "A1RKKUPIHCS9HS")
AMAZON_SELLER_ID=$(v AMAZON_SELLER_ID "")
AMAZON_MODE=$(v AMAZON_MODE simulated)
YSELL_API_KEY=$(v YSELL_API_KEY "")
YSELL_API_SECRET=$(v YSELL_API_SECRET "")
YSELL_WAREHOUSE_ID=$(v YSELL_WAREHOUSE_ID "")
YSELL_BASE_URL=$(v YSELL_BASE_URL "")
YSELL_MODE=$(v YSELL_MODE simulated)

# ===========================================
# Logging Configuration
# ===========================================
LOG_LEVEL=$(v LOG_LEVEL WARNING)
LOG_DIR=$(v LOG_DIR /app/logs)
LOG_MAX_BYTES=$(v LOG_MAX_BYTES 52428800)
LOG_BACKUP_COUNT=$(v LOG_BACKUP_COUNT 10)

# ===========================================
# Application Configuration
# ===========================================
APP_UID=$(v APP_UID 1000)
APP_GID=$(v APP_GID 1000)

# ===========================================
# Gunicorn Configuration (Production)
# ===========================================
GUNICORN_WORKERS=$(v GUNICORN_WORKERS 4)
GUNICORN_THREADS=$(v GUNICORN_THREADS 2)
GUNICORN_TIMEOUT=$(v GUNICORN_TIMEOUT 120)
ENVEOF

    echo ""
    success ".env repaired and normalized!"
    echo -e "  Original backup: ${BOLD}$backup_file${NC}"
    echo ""
    
    if [ ${#fixes[@]} -gt 0 ]; then
        echo -e "${BOLD}Changes applied:${NC}"
        for fix in "${fixes[@]}"; do
            echo -e "  ${GREEN}✓${NC} $fix"
        done
        echo ""
    fi
}

# ===========================================
# Help Command
# ===========================================
cmd_help() {
    echo -e "${BOLD}${CYAN}"
    echo "  ___                     _    __     __    _ _   "
    echo " |_ _|_ _ ___  _ _    ___| |_  \ \   / /__ | | |_ "
    echo "  | || '_/ _ \| ' \  / -_)  _|  \ \ / / _ \| |  _|"
    echo " |___|_| \___/|_||_| \___|\__|   \_V_/\___/|_|\__|"
    echo -e "${NC}"
    echo -e "${BOLD}Docker Management Script${NC}"
    echo ""
    echo -e "${BOLD}Usage:${NC} $0 [global-options] <command> [options]"
    echo ""
    echo -e "${BOLD}${BLUE}Global Options:${NC}"
    echo "  -p, --project NAME   Set project name (default: ironvolt or COMPOSE_PROJECT_NAME)"
    echo "  --env-file FILE      Specify an env file to use"
    echo ""
    echo -e "${BOLD}${BLUE}Build Commands:${NC}"
    echo "  build [OPTIONS]    Build all Docker images"
    echo "  build:dev [OPTS]   Build development images"
    echo "  build:prod [OPTS]  Build production images"
    echo "  build:test [OPTS]  Build test images"
    echo ""
    echo -e "${BOLD}${BLUE}Build Options:${NC}"
    echo "  --no-cache         Build without using cache"
    echo "  --pull             Always pull newer base images"
    echo "  --parallel         Build images in parallel"
    echo ""
    echo -e "${BOLD}${BLUE}Lifecycle Commands:${NC}"
    echo "  up                 Start all services (production mode)"
    echo "  up:dev             Start in development mode (with hot reload)"
    echo "  up:prod            Start in production mode"
    echo "  down               Stop and remove all containers"
    echo "  restart            Restart all services"
    echo "  restart [service]  Restart a specific service"
    echo ""
    echo -e "${BOLD}${BLUE}Utility Commands:${NC}"
    echo "  logs               Show logs for all services (follow mode)"
    echo "  logs [service]     Show logs for a specific service"
    echo "  shell [service]    Open shell in container (default: backend)"
    echo "  status             Show container status"
    echo ""
    echo -e "${BOLD}${BLUE}Database Commands:${NC}"
    echo "  db:migrate         Run Flask database migrations"
    echo "  db:heads           Check for divergent migration heads"
    echo "  db:merge           Merge divergent migration heads"
    echo "  db:current         Show current migration state in database"
    echo "  db:stamp <rev>     Stamp database with specific revision (use to fix orphan heads)"
    echo "  db:init            Initialize database from models (drops all tables!)"
    echo "  db:clean           Clean transactional data (bookings, invoices, etc)"
    echo "  db:seed:config     Seed only EmailTemplates"
    echo "  db:seed:users           Seed all 4 quick access users from fixtures (legacy)"
    echo "  db:seed:owner           Seed only the owner superadmin (eacaja+admin@gmail.com)"
    echo "  db:seed:quick-defaults  Seed only manager + instructor + client (no superadmin)"
    echo "  db:seed:minimal    Seed database with minimal demo data"
    echo "  db:seed:max        Seed database with complete demo data"
    echo "  db:seed:geo        Seed GEO data (stats, quotes, FAQ)"
    echo "  db:seed:posts      Seed blog posts with demo content"
    echo "  db:seed:legal [lang]  Seed legal documents — lang: es (default), en, fr, it"
    echo "  db:seed:emails [lang]              Seed email templates — lang: es (default), en, fr, it"
    echo "  db:seed:document-templates [lang]  Seed document templates — lang: es (default), en, fr, it"
    echo "  db:seed:all-templates [lang]       Seed ALL templates (emails + documents) — lang: es (default), en, fr, it"
    echo "  db:seed:theme-ironvolt  Seed Iron-Volt theme templates"
    echo "  db:seed:theme-luttebien Seed Luttebien theme templates"
    echo "  db:seed:theme-all       Seed all theme templates"
    echo "  db:shell           Open PostgreSQL shell"
    echo "  db:query 'SQL'     Execute SQL query (non-interactive)"
    echo "  db:py 'CODE'       Execute Python code with ORM (non-interactive, log-filtered)"
    echo "  db:sync-password   Sync POSTGRES_PASSWORD from .env into PostgreSQL (fixes auth failures)"
    echo ""
    echo -e "${BOLD}${BLUE}Backup & Restore Commands:${NC}"
    echo "  backup:full            Create full backup: database + all storage files (.tar.gz)"
    echo "  restore:full FILE      Restore full backup from .tar.gz archive"
    echo "  backup:list            List available backups with metadata"
    echo "  backup:schedule [TIME] Schedule daily backup at TIME (default: 03:00). Reschedules if exists."
    echo "  backup:unschedule      Remove scheduled backup for this project"
    echo "  backup:crons           List all scheduled backups on this server"
    echo "  backup:clean [DAYS]    Delete backups older than DAYS (default: 30)"
    echo ""
    echo -e "${BOLD}${BLUE}Content Commands:${NC}"
    echo "  sync-manual        Sync user manual (MANUAL_USUARIO.md) to storage (overwrites)"
    echo "  theme:import FILE  Import a theme ZIP into the system (upsert by slug)"
    echo ""
    echo -e "${BOLD}${BLUE}Test Commands:${NC}"
    echo "  test [FLAGS]                 Run all tests (API + Unit, excluding bg)"
    echo "  test:api [FLAGS]             Run only API tests (excluding bg)"
    echo "  test:unit [FLAGS]            Run only unit tests (test_unit/, recursive)"
    echo "  test:bg [FLAGS]              Run only background task tests (slow)"
    echo "  test:full [FLAGS]            Run FULL suite sequentially: Unit → API → BG →"
    echo "                                 Stripe light → Stripe heavy (auto-teardown)"
    echo "  test:all [FLAGS]             Alias for test:full"
    echo "  test:todos [FLAGS]           Alias for test:full"
    echo "  test:module NAME [FLAGS]     Run specific module (auto-finds location)"
    echo "  test:stripe [MODULE] [FLAGS]  Run Stripe integration tests (requires STRIPE_SECRET_KEY)"
    echo "                                 Optional MODULE: e.g., 'lifecycle_paths' runs only path tests"
    echo "  test:stripe:flaky [FLAGS]    Run ONLY stripe_flaky classes (Phase 3 isolated + retry)"
    echo "  test:build [OPTS]            Build test Docker images (alias for build:test)"
    echo "  test:up                      Start test infrastructure (db, minio)"
    echo "  test:down                    Stop and remove test containers"
    echo "  test:status                  Inventory of test/dev/prod containers (used by skill self-check)"
    echo "  test:clean [--keep-db]       Full teardown of test stack (alias for test:down + cleanup)"
    echo "  test:logs [N] [-f]           View test logs (last N lines, -f to follow)"
    echo "  test:list                    List available test modules and flags"
    echo ""
    echo -e "${BOLD}${BLUE}Test Flags (combinable):${NC}"
    echo "  --debug, -d                  Verbose logging (LOG_LEVEL=DEBUG, long tracebacks)"
    echo "  --coverage, -c               Generate HTML coverage report"
    echo "  --email                      Enable real email sending (TEST_FAST=0)"
    echo "  --build, -b                  Rebuild test images (default: ON)"
    echo "  --no-build                   Skip rebuild (opt-out, uses existing image)"
    echo "  --build-no-cache             Rebuild test images without Docker cache"
    echo "  --no-failfast                Run all tests even if one fails (default: stop on first failure)"
    echo "  --no-debug                   Disable debug output (default: debug ON with --tb=long)"
    echo ""
    echo -e "${BOLD}${BLUE}Environment Commands:${NC}"
    echo "  env:generate               Interactive .env generator (creates or updates .env)"
    echo "  env:generate --secrets     Same, but regenerates stateless tokens (JWT, Internal API Secret)"
    echo "  env:repair                 Analyze and fix .env (removes obsolete vars, normalizes format)"
    echo ""
    echo -e "${BOLD}${BLUE}Health & Diagnostics:${NC}"
    echo "  health             Check health of all services"
    echo "  diagnose           Analyze ports and containers"
    echo "  diagnose [port]    Analyze a specific port"
    echo ""
    echo -e "${BOLD}${BLUE}Cleanup Commands:${NC}"
    echo "  clean              Stop and remove containers (keeps volumes)"
    echo "  clean:all          Stop and remove containers AND volumes (destroys data)"
    echo "  clean:force        Force remove containers by name (ignores compose files)"
    echo "  clean:images       Remove Iron & Volt Docker images"
    echo ""
    echo -e "${BOLD}${BLUE}Skill Management:${NC}"
    echo "  install:skill <nombre> [--symlink] [--force]"
    echo "                     Install skill from skills/<nombre>/ to .claude/skills/<nombre>"
    echo "                     Default: copy (runtime-portable). --symlink opt-in for zero-drift dev."
    echo "                     Tras editar la skill en el repo, re-run con --force para refrescar."
    echo "  uninstall:skill <nombre>"
    echo "                     Remove skill from .claude/skills/ (rm -rf de la copia o symlink)"
    echo "  skills:list        List all skills available in repo + installed in .claude/skills/"
    echo "  skills:sync-scripts"
    echo "                     Sync watched scripts (manage.sh, mt.sh, etc.) to skills'"
    echo "                     bundled copy. Run after editing scripts/ before commit."
    echo ""
    echo -e "${BOLD}${BLUE}Help:${NC}"
    echo "  help               Show this help message"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo "  $0 up:dev                    # Start development environment"
    echo "  $0 logs backend              # Follow backend logs"
    echo "  $0 shell database            # Open database shell"
    echo "  $0 backup:full               # Create full backup (DB + storage) as .tar.gz"
    echo "  $0 restore:full ./backups/full_backup_20260322_120000.tar.gz"
    echo "  $0 backup:list               # List all available backups"
    echo "  $0 backup:schedule 03:00     # Schedule daily backup at 3AM"
    echo "  $0 backup:schedule 14:30     # Reschedule to 2:30PM"
    echo "  $0 backup:unschedule         # Remove scheduled backup"
    echo "  $0 backup:crons              # List all scheduled backups on server"
    echo "  $0 backup:clean 30           # Delete backups older than 30 days"
    echo ""
    echo -e "${BOLD}Multi-Instance Examples:${NC}"
    echo "  # Run two instances with different configs and ports:"
    echo "  $0 -p ironvolt-staging --env-file .env.staging up:dev"
    echo "  $0 -p ironvolt-prod --env-file .env.production up"
    echo ""
    echo "  # Manage specific instance:"
    echo "  $0 -p ironvolt-staging logs backend"
    echo "  $0 -p ironvolt-prod status"
    echo ""
}

# ===========================================
# Main Command Router
# ===========================================

# Global array to store remaining args after flag parsing.
# Uses an array (not a string) so quoted compound args (e.g. -k "A or B")
# survive without being word-split.
REMAINING_ARGS=()

# Parse global flags before command (modifies global variables directly)
parse_global_flags() {
    REMAINING_ARGS=()
    while [ $# -gt 0 ]; do
        case "$1" in
            -p|--project)
                if [ -z "$2" ] || [[ "$2" == -* ]]; then
                    error "Option $1 requires a project name argument"
                fi
                PROJECT_NAME="$2"
                shift 2
                ;;
            --env-file)
                if [ -z "$2" ] || [[ "$2" == -* ]]; then
                    error "Option $1 requires a file path argument"
                fi
                ENV_FILE="$2"
                shift 2
                ;;
            -*)
                # Unknown flag - stop parsing flags
                break
                ;;
            *)
                # Not a flag - this is the command
                break
                ;;
        esac
    done
    # Store remaining arguments preserving word boundaries
    REMAINING_ARGS=("$@")
}

# ============================================================================
# Skill management — install/uninstall/list/sync skills under .claude/skills/
# ============================================================================
# Strategy:
#  - Default: copia recursiva desde repo/skills/<name>/ → .claude/skills/<name>/.
#    Pro: portable (no depende de ruta absoluta del repo), runtime-friendly
#    (algunos indexers de skill no resuelven symlinks de forma fiable),
#    permite distribuir .claude/skills/ standalone.
#    Con: tras editar la skill en el repo, hay que re-run con --force para refrescar.
#  - Opt-in --symlink: cero drift, edición iterativa inmediata. Útil en dev cuando
#    la skill está en heavy iteration. Caveat: Windows requiere developer mode;
#    runtimes que indexan `.claude/skills/` con `find -L` o `realpath` pueden
#    detectarlo tarde (cold start).
#  - --force: overwrite con validación previa (target debe ser una skill válida).

cmd_install_skill() {
    local skill_name="${1:-}"
    local mode="copy"
    local force=0

    if [ -z "$skill_name" ] || [[ "$skill_name" == --* ]]; then
        error "install:skill <nombre> [--symlink] [--force]"
        return 2
    fi
    shift

    while [ $# -gt 0 ]; do
        case "$1" in
            --symlink) mode="symlink" ;;
            --copy)    mode="copy" ;;  # explícito (default) — aceptado por compat
            --force)   force=1 ;;
            *) error "Flag desconocido: $1"; return 2 ;;
        esac
        shift
    done

    # Pre-check 1: nombre válido (lowercase + hyphens, inicia con letra)
    if [[ ! "$skill_name" =~ ^[a-z][a-z0-9-]*$ ]]; then
        error "Nombre inválido '$skill_name': lowercase + [a-z0-9-], debe iniciar con letra"
        return 2
    fi

    local repo_root
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
        error "No es un repo git"
        return 2
    }

    local source_dir="$repo_root/skills/$skill_name"
    local target_root="${CLAUDE_SKILLS_DIR:-$repo_root/.claude/skills}"
    local target_dir="$target_root/$skill_name"

    # Pre-check 2: source válida
    if [ ! -f "$source_dir/SKILL.md" ]; then
        error "Skill source no encontrada: $source_dir/SKILL.md"
        return 1
    fi

    # Pre-check 3: target dir padre creable
    local target_root_existed=1
    [ -d "$target_root" ] || target_root_existed=0
    mkdir -p "$target_root" || { error "No puedo crear $target_root"; return 1; }

    # Pre-check 4: target ya existe
    if [ -e "$target_dir" ] || [ -L "$target_dir" ]; then
        # Idempotencia: symlink ya apunta al source correcto
        if [ -L "$target_dir" ] \
            && [ "$(readlink "$target_dir")" = "$source_dir" ] \
            && [ "$mode" = "symlink" ]; then
            info "Skill '$skill_name' ya instalada (symlink up-to-date)"
            return 0
        fi

        if [ $force -eq 0 ]; then
            error "Target ya existe: $target_dir
  Usa '--force' para sobrescribir (refrescar copia tras editar fuente),
  o 'uninstall:skill $skill_name' primero"
            return 1
        fi

        # --force: validar que el target ES una skill antes de rm -rf
        local existing_skill_md=""
        if [ -L "$target_dir" ] && [ -f "$(readlink -f "$target_dir")/SKILL.md" ]; then
            existing_skill_md="$(readlink -f "$target_dir")/SKILL.md"
        elif [ -f "$target_dir/SKILL.md" ]; then
            existing_skill_md="$target_dir/SKILL.md"
        fi

        if [ -z "$existing_skill_md" ]; then
            error "--force rechazado: $target_dir no parece una skill (no SKILL.md). Aborto."
            return 1
        fi

        warning "--force activado, eliminando $target_dir"
        rm -rf "$target_dir"
    fi

    # Install
    if [ "$mode" = "symlink" ]; then
        ln -s "$source_dir" "$target_dir" || { error "ln -s falló"; return 1; }
        success "Symlink creado: $target_dir -> $source_dir"
    else
        # cp -rL para resolver symlinks dentro del source (defensivo); --no-preserve=mode
        # evita arrastrar permisos restrictivos de archivos del repo si los hubiera.
        cp -rL "$source_dir" "$target_dir" || { error "cp -rL falló"; return 1; }
        success "Copia creada en $target_dir"
        info "Tras editar la skill en $source_dir, ejecuta: install:skill $skill_name --force"
    fi

    # Mensaje restart
    echo ""
    echo "========================================"
    if [ $target_root_existed -eq 0 ]; then
        warning "RESTART REQUERIDO: $target_root se creó por primera vez."
        echo "Reinicia Claude Code en este directorio para activar la skill."
    else
        info "Skill '$skill_name' instalada. Restart de Claude Code recomendado para activar."
    fi
    echo "========================================"
}

cmd_uninstall_skill() {
    local skill_name="${1:-}"
    if [ -z "$skill_name" ]; then
        error "uninstall:skill <nombre>"
        return 2
    fi

    local repo_root
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
        error "No es un repo git"
        return 2
    }

    local target_root="${CLAUDE_SKILLS_DIR:-$repo_root/.claude/skills}"
    local target_dir="$target_root/$skill_name"

    if [ ! -e "$target_dir" ] && [ ! -L "$target_dir" ]; then
        warning "Skill '$skill_name' no instalada en $target_root (no-op)"
        return 0
    fi

    # Validar antes de rm — el target debe ser una skill (con SKILL.md)
    local skill_md=""
    if [ -L "$target_dir" ] && [ -f "$(readlink -f "$target_dir")/SKILL.md" ]; then
        skill_md="$(readlink -f "$target_dir")/SKILL.md"
    elif [ -d "$target_dir" ] && [ -f "$target_dir/SKILL.md" ]; then
        skill_md="$target_dir/SKILL.md"
    fi

    if [ -z "$skill_md" ]; then
        error "$target_dir no parece una skill (no SKILL.md). Aborto."
        return 1
    fi

    if [ -L "$target_dir" ]; then
        rm "$target_dir"
        success "Symlink eliminado: $target_dir"
    else
        rm -rf "$target_dir"
        success "Copia eliminada: $target_dir"
    fi
}

cmd_skills_list() {
    local repo_root
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
        error "No es un repo git"
        return 2
    }

    local target_root="${CLAUDE_SKILLS_DIR:-$repo_root/.claude/skills}"
    local source_root="$repo_root/skills"

    echo "=== Skills disponibles en el repo (\$REPO/skills/) ==="
    if [ -d "$source_root" ]; then
        for d in "$source_root"/*/; do
            [ -d "$d" ] || continue
            local name="$(basename "$d")"
            local installed="not installed"
            if [ -L "$target_root/$name" ]; then
                installed="installed (symlink → $(readlink "$target_root/$name"))"
            elif [ -d "$target_root/$name" ]; then
                installed="installed (copy)"
            fi
            echo "  $name — $installed"
        done
    else
        echo "  (ninguna)"
    fi

    echo ""
    echo "=== Skills instaladas en $target_root ==="
    if [ -d "$target_root" ]; then
        for d in "$target_root"/*/; do
            [ -e "$d" ] || [ -L "${d%/}" ] || continue
            local name="$(basename "${d%/}")"
            if [ -L "${d%/}" ]; then
                echo "  $name (symlink → $(readlink "${d%/}"))"
            else
                echo "  $name (copy)"
            fi
        done
    else
        echo "  (dir no existe)"
    fi
}

cmd_skills_sync_scripts() {
    # Sincroniza scripts del repo (scripts/<X>) a la copia adjunta de cada skill
    # (skills/<name>/scripts/<X>). Defensa contra drift entre el orquestador del
    # repo y la copia bundled en la skill — útil tras editar manage.sh / mt.sh.
    local repo_root
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
        error "No es un repo git"
        return 2
    }

    local source_scripts="$repo_root/scripts"
    local skills_root="$repo_root/skills"

    [ -d "$skills_root" ] || { warning "No hay $skills_root — no-op"; return 0; }

    # Watched scripts (alineado con sync-skill-scripts.sh:25 WATCHED_SCRIPTS)
    local watched=("manage.sh" "mt.sh" "stripe_heavy_collect.py" "validate_migrations.sh")
    local synced=0

    for skill_dir in "$skills_root"/*/; do
        [ -d "$skill_dir/scripts" ] || continue
        local skill_name="$(basename "${skill_dir%/}")"
        for script in "${watched[@]}"; do
            local src="$source_scripts/$script"
            local dst="$skill_dir/scripts/$script"
            [ -f "$src" ] || continue
            [ -f "$dst" ] || continue
            if ! diff -q "$src" "$dst" >/dev/null 2>&1; then
                cp "$src" "$dst"
                success "[$skill_name] sync: $script"
                synced=$((synced + 1))
            fi
        done
    done

    if [ $synced -eq 0 ]; then
        info "Todas las copias de scripts ya están sincronizadas"
    else
        info "$synced archivo(s) sincronizado(s). Recuerda: git add skills/.../scripts/ + commit"
    fi
}

main() {
    # Parse global flags first (directly modifies PROJECT_NAME and ENV_FILE)
    parse_global_flags "$@"
    set -- "${REMAINING_ARGS[@]}"
    
    # Export COMPOSE_PROJECT_NAME for container naming in docker-compose files
    # Must be done after flag parsing to pick up -p/--project overrides
    export COMPOSE_PROJECT_NAME="$PROJECT_NAME"
    
    local command="${1:-help}"
    shift 1 2>/dev/null || true
    
    # Handle commands that don't require Docker first
    case "$command" in
        help|--help|-h)
            cmd_help
            exit 0
            ;;
        test)
            cmd_test "$@"
            exit $?
            ;;
        test:bg)
            cmd_test_bg "$@"
            exit $?
            ;;
        test:all|test:full|test:todos)
            cmd_test_full "$@"
            exit $?
            ;;
        test:module)
            cmd_test_module "$@"
            exit $?
            ;;
        test:stripe)
            cmd_test_stripe "$@"
            exit $?
            ;;
        test:stripe:flaky)
            cmd_test_stripe_flaky "$@"
            exit $?
            ;;
        test:coverage)
            cmd_test_coverage_deprecated
            exit $?
            ;;
        test:logs)
            cmd_test_logs "$@"
            exit $?
            ;;
        test:list)
            cmd_test_list
            exit 0
            ;;
        test:clean)
            cmd_test_clean
            exit $?
            ;;
        test:status)
            cmd_test_status
            exit 0
            ;;
        env:generate)
            cmd_env_generate "$@"
            exit $?
            ;;
        env:repair)
            cmd_env_repair
            exit $?
            ;;
    esac
    
    # All other commands require Docker
    check_docker
    
    case "$command" in
        # Build commands
        build)
            cmd_build "$@"
            ;;
        build:dev)
            cmd_build_dev "$@"
            ;;
        build:prod)
            cmd_build_prod "$@"
            ;;
        build:test)
            cmd_build_test "$@"
            ;;
        
        # Lifecycle commands
        up)
            cmd_up
            ;;
        up:dev)
            cmd_up_dev
            ;;
        up:prod)
            cmd_up_prod
            ;;
        down)
            cmd_down
            ;;
        restart)
            cmd_restart "$@"
            ;;
        
        # Utility commands
        logs)
            cmd_logs "$@"
            ;;
        shell)
            cmd_shell "$@"
            ;;
        status)
            cmd_status
            ;;
        
        # Database commands
        db:migrate)
            cmd_db_migrate
            ;;
        db:init)
            cmd_db_init
            ;;
        db:clean)
            cmd_db_clean
            ;;
        db:heads)
            cmd_db_heads
            ;;
        db:merge)
            cmd_db_merge
            ;;
        db:current)
            cmd_db_current
            ;;
        db:stamp)
            cmd_db_stamp "$1"
            ;;
        db:seed:users)
            cmd_db_seed_users
            ;;
        db:seed:owner)
            cmd_db_seed_owner
            ;;
        db:seed:quick-defaults)
            cmd_db_seed_quick_defaults
            ;;
        db:seed:config)
            cmd_db_seed_config
            ;;
        db:seed:minimal)
            cmd_db_seed_minimal
            ;;
        db:seed:max)
            cmd_db_seed_max
            ;;
        db:seed:geo)
            cmd_db_seed_geo
            ;;
        db:seed:posts)
            cmd_db_seed_posts
            ;;
        db:seed:legal)
            cmd_db_seed_legal "$2"
            ;;
        db:seed:theme-ironvolt)
            cmd_db_seed_theme_ironvolt
            ;;
        db:seed:theme-luttebien)
            cmd_db_seed_theme_luttebien
            ;;
        db:seed:theme-all)
            cmd_db_seed_theme_all
            ;;
        db:seed:emails)
            cmd_db_seed_emails "$2"
            ;;
        db:seed:document-templates)
            cmd_db_seed_document_templates "$2"
            ;;
        db:seed:all-templates)
            cmd_db_seed_all_templates "$2"
            ;;
        
        # Content commands
        sync-manual)
            cmd_sync_manual
            ;;
        theme:import)
            cmd_theme_import "$@"
            ;;
        
        # Full backup & restore commands (only supported format is the tar.gz
        # archive produced by `backup:full` — database-only dumps were removed
        # to avoid format confusion)
        backup:full)
            cmd_backup_full
            ;;
        restore:full)
            cmd_restore_full "$@"
            ;;
        backup:list)
            cmd_backup_list
            ;;
        backup:schedule)
            cmd_backup_schedule "$@"
            ;;
        backup:unschedule)
            cmd_backup_unschedule
            ;;
        backup:crons)
            cmd_backup_crons
            ;;
        backup:clean)
            cmd_backup_clean "$@"
            ;;
        
        db:shell)
            cmd_db_shell
            ;;
        db:query)
            cmd_db_query "$@"
            ;;
        db:py)
            cmd_db_py "$@"
            ;;
        db:sync-password)
            cmd_db_sync_password
            ;;
        
        # Test commands
        test)
            cmd_test "$@"
            ;;
        test:api)
            cmd_test_api "$@"
            ;;
        test:unit)
            cmd_test_unit "$@"
            ;;
        test:bg)
            cmd_test_bg "$@"
            ;;
        test:all|test:full|test:todos)
            cmd_test_full "$@"
            ;;
        test:module)
            cmd_test_module "$@"
            ;;
        test:stripe)
            cmd_test_stripe "$@"
            ;;
        test:stripe:flaky)
            cmd_test_stripe_flaky "$@"
            ;;
        test:up)
            cmd_test_up
            ;;
        test:down)
            cmd_test_down
            ;;
        test:build)
            cmd_build_test "$@"
            ;;
        test:coverage)
            cmd_test_coverage_deprecated
            ;;
        test:logs)
            cmd_test_logs "$@"
            ;;
        test:list)
            cmd_test_list
            ;;
        test:clean)
            cmd_test_clean
            ;;
        test:status)
            cmd_test_status
            ;;

        # Environment commands
        env:generate)
            cmd_env_generate "$@"
            ;;
        env:repair)
            cmd_env_repair
            ;;
        
        # Health & Diagnostics commands
        health)
            cmd_health
            ;;
        diagnose)
            cmd_diagnose "$@"
            ;;
        
        # Cleanup commands
        clean)
            cmd_clean
            ;;
        clean:all)
            cmd_clean_all
            ;;
        clean:force)
            cmd_clean_force
            ;;
        clean:images)
            cmd_clean_images
            ;;

        # Skill management
        install:skill)
            cmd_install_skill "$@"
            ;;
        uninstall:skill)
            cmd_uninstall_skill "$@"
            ;;
        skills:list)
            cmd_skills_list
            ;;
        skills:sync-scripts)
            cmd_skills_sync_scripts
            ;;

        # Help
        help|--help|-h)
            cmd_help
            ;;
        
        *)
            error "Unknown command: $command\nRun '$0 help' for usage information."
            ;;
    esac
}

# Run main function with all arguments
main "$@"
