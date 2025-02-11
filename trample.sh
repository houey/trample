#!/bin/bash

# Default values
ROLE_NAME="OrganizationAccountAccessRole"
OUTPUT_DIR="trample_results"
RESUME_FILE=""

# Add verbose flag and logging function
VERBOSE=false

log() {
    local level="$1"
    shift
    if [[ "$VERBOSE" == "true" ]] || [[ "$level" != "DEBUG" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" >&2
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--role)
            ROLE_NAME="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --resume)
            RESUME_FILE="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Function to assume role in an account
assume_role() {
    local account_id="$1"
    local role_name="$2"
    
    log "INFO" "Attempting to assume role ${role_name} in account ${account_id}"
    local result
    result=$(aws sts assume-role \
        --role-arn "arn:aws:iam::${account_id}:role/${role_name}" \
        --role-session-name "TrampleSession" 2>&1)
    
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to assume role: $result"
        return 1
    fi
    log "DEBUG" "Successfully assumed role"
    echo "$result"
}

# Function to enumerate resources in an account
enumerate_account() {
    local account_id="$1"
    local ou_name="$2"
    local org_id="$3"
    
    log "INFO" "Enumerating resources in account ${account_id} (OU: ${ou_name})"
    
    # Assume role in the account
    local credentials
    credentials=$(assume_role "$account_id" "$ROLE_NAME")
    if [ $? -ne 0 ]; then
        log "ERROR" "Skipping account ${account_id} due to assume role failure"
        return 1
    fi
    
    # Export temporary credentials
    export AWS_ACCESS_KEY_ID=$(echo "$credentials" | jq -r '.Credentials.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo "$credentials" | jq -r '.Credentials.SecretAccessKey')
    export AWS_SESSION_TOKEN=$(echo "$credentials" | jq -r '.Credentials.SessionToken')
    
    # Enumerate S3 buckets
    log "DEBUG" "Enumerating s3 resources"
    local output_file="$OUTPUT_DIR/${org_id}_${ou_name}_${account_id}_s3.json"
    aws s3api list-buckets 2>/dev/null | jq '.' > "$output_file"
    if [ -s "$output_file" ]; then
        log "INFO" "Saved s3 resources to ${output_file}"
    else
        log "WARN" "No s3 resources found or permission denied"
        rm -f "$output_file"
    fi
    
    # Enumerate EC2 instances
    log "DEBUG" "Enumerating ec2 resources"
    output_file="$OUTPUT_DIR/${org_id}_${ou_name}_${account_id}_ec2.json"
    aws ec2 describe-instances 2>/dev/null | jq '.' > "$output_file"
    if [ -s "$output_file" ]; then
        log "INFO" "Saved ec2 resources to ${output_file}"
    else
        log "WARN" "No ec2 resources found or permission denied"
        rm -f "$output_file"
    fi
    
    # Enumerate IAM users and roles
    log "DEBUG" "Enumerating iam resources"
    output_file="$OUTPUT_DIR/${org_id}_${ou_name}_${account_id}_iam.json"
    (aws iam list-users 2>/dev/null; aws iam list-roles 2>/dev/null) | jq '.' > "$output_file"
    if [ -s "$output_file" ]; then
        log "INFO" "Saved iam resources to ${output_file}"
    else
        log "WARN" "No iam resources found or permission denied"
        rm -f "$output_file"
    fi
    
    # Enumerate Lambda functions
    log "DEBUG" "Enumerating lambda resources"
    output_file="$OUTPUT_DIR/${org_id}_${ou_name}_${account_id}_lambda.json"
    aws lambda list-functions 2>/dev/null | jq '.' > "$output_file"
    if [ -s "$output_file" ]; then
        log "INFO" "Saved lambda resources to ${output_file}"
    else
        log "WARN" "No lambda resources found or permission denied"
        rm -f "$output_file"
    fi
    
    # Enumerate RDS instances
    log "DEBUG" "Enumerating rds resources"
    output_file="$OUTPUT_DIR/${org_id}_${ou_name}_${account_id}_rds.json"
    aws rds describe-db-instances 2>/dev/null | jq '.' > "$output_file"
    if [ -s "$output_file" ]; then
        log "INFO" "Saved rds resources to ${output_file}"
    else
        log "WARN" "No rds resources found or permission denied"
        rm -f "$output_file"
    fi
    
    # Clear credentials
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
    log "DEBUG" "Cleared temporary credentials"
}

# Main function to enumerate organization
enumerate_org() {
    # First verify Organizations access
    if ! aws organizations describe-organization >/dev/null 2>&1; then
        log "ERROR" "Unable to access AWS Organizations. Please verify your permissions and AWS Organizations access"
        exit 1
    fi

    # Get organization ID with error handling
    local org_id
    org_id=$(aws organizations describe-organization --query 'Organization.Id' --output text)
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to get organization ID"
        exit 1
    fi
    log "INFO" "Successfully found organization ID: ${org_id}"

    # Get root ID with error handling
    local root_id
    root_id=$(aws organizations list-roots --query 'Roots[0].Id' --output text)
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to get root ID"
        exit 1
    fi
    log "INFO" "Successfully found root ID: ${root_id}"

    # Function to process organizational units recursively
    process_ou() {
        local parent_id="$1"
        local parent_name="$2"
        
        log "INFO" "Processing OU: ${parent_name} (${parent_id})"

        # List OUs in the parent with error handling
        local ous
        ous=$(aws organizations list-organizational-units-for-parent \
            --parent-id "$parent_id" \
            --output json 2>/dev/null)
        
        if [ $? -eq 0 ] && [ -n "$ous" ]; then
            echo "$ous" | jq -r '.OrganizationalUnits[] | select(.Id != null and .Name != null) | "\(.Id) \(.Name)"' | \
            while read -r ou_id ou_name; do
                if [ -n "$ou_id" ] && [ -n "$ou_name" ]; then
                    log "INFO" "Found OU: ${ou_name} (${ou_id})"
                    
                    # List accounts in the OU
                    aws organizations list-accounts-for-parent \
                        --parent-id "$ou_id" \
                        --output json 2>/dev/null | \
                    jq -r '.Accounts[] | select(.Id != null) | .Id' | \
                    while read -r account_id; do
                        if [ -n "$account_id" ]; then
                            enumerate_account "$account_id" "$ou_name" "$org_id"
                        fi
                    done
                    
                    # Recurse into nested OUs
                    process_ou "$ou_id" "$ou_name"
                fi
            done
        else
            log "WARN" "No OUs found or permission denied for parent: ${parent_id}"
        fi
    }
    
    # Start processing from root
    log "INFO" "Starting enumeration from root"
    process_ou "$root_id" "root"
}

# Resume from file if specified, otherwise start fresh
if [ -n "$RESUME_FILE" ] && [ -f "$RESUME_FILE" ]; then
    echo "Resuming from $RESUME_FILE"
    # Add resume logic here
else
    enumerate_org
fi
