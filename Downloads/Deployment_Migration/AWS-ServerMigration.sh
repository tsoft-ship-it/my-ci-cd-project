#!/bin/bash

# =============================================================================
# AWS SERVER MIGRATION SCRIPT
# EC2 instance launch, configuration, and management
# =============================================================================
# Usage: ./AWS-ServerMigration.sh --territory US --action launch
# =============================================================================

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/aws_migration_${TIMESTAMP}.log"

# Create log directory
mkdir -p "$LOG_DIR"

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# =============================================================================
# TERRITORY CONFIGURATION
# =============================================================================

declare -A TERRITORY_CONFIG

# US Configuration
TERRITORY_CONFIG["US_REGION"]="us-east-1"
TERRITORY_CONFIG["US_VPC_CIDR"]="10.1.0.0/16"
TERRITORY_CONFIG["US_PRIMARY_DNS"]="10.1.1.10"
TERRITORY_CONFIG["US_SECONDARY_DNS"]="10.1.1.20"
TERRITORY_CONFIG["US_DOMAIN"]="company.local"

# EU Configuration
TERRITORY_CONFIG["EU_REGION"]="eu-west-1"
TERRITORY_CONFIG["EU_VPC_CIDR"]="10.2.0.0/16"
TERRITORY_CONFIG["EU_PRIMARY_DNS"]="10.2.1.10"
TERRITORY_CONFIG["EU_SECONDARY_DNS"]="10.2.1.20"
TERRITORY_CONFIG["EU_DOMAIN"]="eu.company.local"

# APAC Configuration
TERRITORY_CONFIG["APAC_REGION"]="ap-southeast-1"
TERRITORY_CONFIG["APAC_VPC_CIDR"]="10.3.0.0/16"
TERRITORY_CONFIG["APAC_PRIMARY_DNS"]="10.3.1.10"
TERRITORY_CONFIG["APAC_SECONDARY_DNS"]="10.3.1.20"
TERRITORY_CONFIG["APAC_DOMAIN"]="apac.company.local"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

print_header() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC} $1"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════════════╝${NC}"
}

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
    -t, --territory TERRITORY       Territory code (US, EU, APAC, CA, AU)
    -a, --action ACTION             Action to perform (launch, configure, create-ami, terminate, list, status)
    -i, --instance-id ID            EC2 instance ID
    -m, --ami-id ID                 AMI ID (for launch action)
    -s, --subnet-id ID              Subnet ID (for launch action)
    -n, --instance-name NAME        Instance name (for launch action)
    -z, --instance-type TYPE        Instance type (default: m5.xlarge)
    -p, --private-ip IP             Private IP address
    --environment ENV               Environment (Production, Staging, Development)
    --dry-run                       Show what would be done without doing it
    -v, --verbose                   Verbose output
    -h, --help                      Show this help message

EXAMPLES:
    # Launch new instance
    ./AWS-ServerMigration.sh -t US -a launch -m ami-12345678 -s subnet-12345678

    # Get instance status
    ./AWS-ServerMigration.sh -t US -a status -i i-0123456789abcdef

    # Create AMI from instance
    ./AWS-ServerMigration.sh -t US -a create-ami -i i-0123456789abcdef

    # Terminate instance
    ./AWS-ServerMigration.sh -t US -a terminate -i i-0123456789abcdef

EOF
}

# =============================================================================
# PARSING ARGUMENTS
# =============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--territory)
                TERRITORY="$2"
                shift 2
                ;;
            -a|--action)
                ACTION="$2"
                shift 2
                ;;
            -i|--instance-id)
                INSTANCE_ID="$2"
                shift 2
                ;;
            -m|--ami-id)
                AMI_ID="$2"
                shift 2
                ;;
            -s|--subnet-id)
                SUBNET_ID="$2"
                shift 2
                ;;
            -n|--instance-name)
                INSTANCE_NAME="$2"
                shift 2
                ;;
            -z|--instance-type)
                INSTANCE_TYPE="$2"
                shift 2
                ;;
            -p|--private-ip)
                PRIVATE_IP="$2"
                shift 2
                ;;
            --environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

validate_territory() {
    case "$TERRITORY" in
        US|EU|APAC|CA|AU)
            return 0
            ;;
        *)
            log_error "Invalid territory: $TERRITORY"
            return 1
            ;;
    esac
}

validate_aws_credentials() {
    if ! aws sts get-caller-identity &>/dev/null; then
        log_error "AWS credentials not configured. Run 'aws configure'"
        return 1
    fi
    
    local ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
    log_success "AWS Account: $ACCOUNT"
    return 0
}

get_config_value() {
    local KEY="${TERRITORY}_${1}"
    echo "${TERRITORY_CONFIG[$KEY]}"
}

# =============================================================================
# AWS OPERATIONS
# =============================================================================

launch_instance() {
    print_header "Launching EC2 Instance - Territory: $TERRITORY"
    
    if [[ -z "$AMI_ID" ]] || [[ -z "$SUBNET_ID" ]]; then
        log_error "AMI_ID and SUBNET_ID are required for launch action"
        return 1
    fi
    
    local REGION=$(get_config_value "REGION")
    local INSTANCE_TYPE="${INSTANCE_TYPE:-m5.xlarge}"
    local INSTANCE_NAME="${INSTANCE_NAME:-${TERRITORY}SUPDFS01-2025}"
    local ENVIRONMENT="${ENVIRONMENT:-Production}"
    
    log_info "Configuration:"
    log_info "  Region: $REGION"
    log_info "  AMI ID: $AMI_ID"
    log_info "  Instance Type: $INSTANCE_TYPE"
    log_info "  Instance Name: $INSTANCE_NAME"
    log_info "  Subnet: $SUBNET_ID"
    [[ -n "$PRIVATE_IP" ]] && log_info "  Private IP: $PRIVATE_IP"
    log_info "  Environment: $ENVIRONMENT"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN - No instance will be launched"
        return 0
    fi
    
    # Build launch command
    local LAUNCH_CMD="aws ec2 run-instances \
        --image-id $AMI_ID \
        --instance-type $INSTANCE_TYPE \
        --subnet-id $SUBNET_ID \
        --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME},{Key=Territory,Value=$TERRITORY},{Key=Environment,Value=$ENVIRONMENT}]' \
        --region $REGION"
    
    if [[ -n "$PRIVATE_IP" ]]; then
        LAUNCH_CMD="$LAUNCH_CMD --private-ip-address $PRIVATE_IP"
    fi
    
    if [[ "$VERBOSE" == "true" ]]; then
        log_info "Command: $LAUNCH_CMD"
    fi
    
    local RESULT
    if RESULT=$(eval "$LAUNCH_CMD" 2>&1); then
        local INSTANCE_ID=$(echo "$RESULT" | jq -r '.Instances[0].InstanceId')
        local PRIVATE_IP_ASSIGNED=$(echo "$RESULT" | jq -r '.Instances[0].PrivateIpAddress')
        
        log_success "Instance launched successfully"
        log_info "Instance ID: $INSTANCE_ID"
        log_info "Private IP: $PRIVATE_IP_ASSIGNED"
        log_info "State: $(echo "$RESULT" | jq -r '.Instances[0].State.Name')"
        
        # Save instance ID
        echo "$INSTANCE_ID" > "${LOG_DIR}/instance_id_${TERRITORY}.txt"
        
        # Wait for running state
        log_info "Waiting for instance to reach running state..."
        if aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"; then
            log_success "Instance is running"
        fi
        
        return 0
    else
        log_error "Failed to launch instance: $RESULT"
        return 1
    fi
}

get_instance_status() {
    print_header "Getting Instance Status - Territory: $TERRITORY"
    
    if [[ -z "$INSTANCE_ID" ]]; then
        log_error "INSTANCE_ID is required"
        return 1
    fi
    
    local REGION=$(get_config_value "REGION")
    
    log_info "Querying instance: $INSTANCE_ID"
    
    local STATUS
    if STATUS=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --region "$REGION" \
        --output json 2>&1); then
        
        local STATE=$(echo "$STATUS" | jq -r '.Reservations[0].Instances[0].State.Name')
        local PRIVATE_IP=$(echo "$STATUS" | jq -r '.Reservations[0].Instances[0].PrivateIpAddress')
        local NAME=$(echo "$STATUS" | jq -r '.Reservations[0].Instances[0].Tags[] | select(.Key=="Name") | .Value')
        
        log_success "Instance Status:"
        log_info "  Instance ID: $INSTANCE_ID"
        log_info "  Name: $NAME"
        log_info "  State: $STATE"
        log_info "  Private IP: $PRIVATE_IP"
        
        return 0
    else
        log_error "Failed to get instance status: $STATUS"
        return 1
    fi
}

create_ami_from_instance() {
    print_header "Creating AMI from Instance - Territory: $TERRITORY"
    
    if [[ -z "$INSTANCE_ID" ]]; then
        log_error "INSTANCE_ID is required"
        return 1
    fi
    
    local REGION=$(get_config_value "REGION")
    local IMAGE_NAME="${TERRITORY}SUPDFS01-Prepared-$(date +%Y%m%d)"
    
    log_info "Creating AMI from instance: $INSTANCE_ID"
    log_info "AMI Name: $IMAGE_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN - No AMI will be created"
        return 0
    fi
    
    local RESULT
    if RESULT=$(aws ec2 create-image \
        --instance-id "$INSTANCE_ID" \
        --name "$IMAGE_NAME" \
        --description "Prepared server image - Territory: $TERRITORY - Date: $(date +%Y-%m-%d)" \
        --region "$REGION" \
        --output json 2>&1); then
        
        local IMAGE_ID=$(echo "$RESULT" | jq -r '.ImageId')
        
        log_success "AMI creation initiated"
        log_info "Image ID: $IMAGE_ID"
        
        # Save image ID
        echo "$IMAGE_ID" > "${LOG_DIR}/ami_id_${TERRITORY}.txt"
        
        log_info "Waiting for AMI to complete (this may take several minutes)..."
        if aws ec2 wait image-available --image-ids "$IMAGE_ID" --region "$REGION"; then
            log_success "AMI is available"
        fi
        
        return 0
    else
        log_error "Failed to create AMI: $RESULT"
        return 1
    fi
}

terminate_instance() {
    print_header "Terminating Instance - Territory: $TERRITORY"
    
    if [[ -z "$INSTANCE_ID" ]]; then
        log_error "INSTANCE_ID is required"
        return 1
    fi
    
    local REGION=$(get_config_value "REGION")
    
    log_warning "About to terminate instance: $INSTANCE_ID"
    
    if [[ "$DRY_RUN" != "true" ]] && [[ "$FORCE" != "true" ]]; then
        read -p "Are you sure? (yes/no): " CONFIRM
        if [[ "$CONFIRM" != "yes" ]]; then
            log_info "Termination cancelled"
            return 0
        fi
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN - Instance will not be terminated"
        return 0
    fi
    
    local RESULT
    if RESULT=$(aws ec2 terminate-instances \
        --instance-ids "$INSTANCE_ID" \
        --region "$REGION" \
        --output json 2>&1); then
        
        log_success "Instance termination initiated"
        log_info "Instance ID: $INSTANCE_ID"
        
        return 0
    else
        log_error "Failed to terminate instance: $RESULT"
        return 1
    fi
}

list_instances() {
    print_header "Listing Instances - Territory: $TERRITORY"
    
    local REGION=$(get_config_value "REGION")
    
    log_info "Querying instances in $REGION..."
    
    aws ec2 describe-instances \
        --filters "Name=tag:Territory,Values=$TERRITORY" "Name=instance-state-name,Values=running,stopped,pending" \
        --region "$REGION" \
        --query 'Reservations[].Instances[].[InstanceId, State.Name, InstanceType, PrivateIpAddress, Tags[?Key==`Name`].Value|[0]]' \
        --output table
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    print_header "AWS Server Migration Script - Version 1.0"
    
    log_info "Timestamp: $(date)"
    log_info "Log file: $LOG_FILE"
    
    # Parse arguments
    parse_args "$@"
    
    # Validate inputs
    if [[ -z "$TERRITORY" ]] || [[ -z "$ACTION" ]]; then
        log_error "Territory and Action are required"
        print_usage
        exit 1
    fi
    
    if ! validate_territory; then
        exit 1
    fi
    
    if ! validate_aws_credentials; then
        exit 1
    fi
    
    # Execute action
    case "$ACTION" in
        launch)
            launch_instance
            ;;
        status)
            get_instance_status
            ;;
        create-ami)
            create_ami_from_instance
            ;;
        terminate)
            terminate_instance
            ;;
        list)
            list_instances
            ;;
        *)
            log_error "Unknown action: $ACTION"
            exit 1
            ;;
    esac
    
    echo ""
    log_success "Script execution completed"
}

# Execute main
main "$@"
