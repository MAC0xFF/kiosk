#!/bin/bash

# Colors still useful for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global vars
TOKEN=""
API_KEY=""
ORG_ID=""
TERMINAL_GROUP=""

# Function to check if dialog is installed
check_dialog() {
    if ! command -v dialog &> /dev/null; then
        echo -e "${RED}Error: 'dialog' is not installed.${NC}"
        echo "Please install it:"
        echo "  Ubuntu/Debian: sudo apt-get install dialog"
        echo "  CentOS/RHEL: sudo yum install dialog"
        echo "  macOS: brew install dialog"
        exit 1
    fi
}

# Function to show message box
show_msg() {
    local title="$1"
    local message="$2"
    local type="${3:-msgbox}" # msgbox, infobox, etc.
    
    dialog --title "$title" --"$type" "$message" 0 0
}

# Function to show input box
get_input() {
    local title="$1"
    local prompt="$2"
    local init_value="$3"
    local result
    
    result=$(dialog --title "$title" --inputbox "$prompt" 0 0 "$init_value" 3>&1 1>&2 2>&3)
    echo "$result"
}

# Function for getting a token
get_token() {
    API_KEY=$(get_input "Authentication" "Enter your API key:" "$API_KEY")
    
    if [[ -z "$API_KEY" ]]; then
        show_msg "Error" "API key cannot be empty!" "msgbox"
        return 1
    fi
    
    TOKEN=$(curl -sX POST \
        --url https://api-ru.iiko.services/api/1/access_token \
        --header 'Content-Type: application/json' \
        --data "{ \"apiLogin\": \"$API_KEY\" }" | jq -r '.token')    
    
    if [[ $TOKEN != null && $TOKEN != "" ]]; then
        show_msg "Success" "Token successfully received!\n\nToken: $TOKEN" "msgbox"
    else
        show_msg "Error" "Error obtaining token!" "msgbox"
        TOKEN=""
    fi
}

# Function for getting a list of organizations
get_organizations() {
    if [[ -z $TOKEN ]]; then
        show_msg "Error" "Token not received. Please obtain a token first." "msgbox"
        return 1
    fi
    
    local result
    result=$(curl -sX GET \
        --url https://api-ru.iiko.services/api/1/organizations \
        --header "Authorization: Bearer $TOKEN" \
        --header 'Content-Type: application/json' \
        --data "{\"returnAdditionalInfo\": true, \"includeDisabled\": true}")
    
    # Format output for dialog
    local org_list=$(echo "$result" | jq -r '.organizations[] | "\(.id)\n\(.name)"' | sed 's/"/\\"/g')
    
    if [[ -z "$org_list" ]]; then
        show_msg "Error" "No organizations found or error occurred!" "msgbox"
        return 1
    fi
    
    # Create temporary file for organization list
    local tempfile=$(mktemp)
    echo "$org_list" > "$tempfile"
    
    dialog --title "Organizations" --textbox "$tempfile" 20 80
    rm "$tempfile"
    
    # Ask for organization ID
    local new_org_id=$(get_input "Organization ID" "Enter organization ID to save:" "$ORG_ID")
    if [[ ! -z "$new_org_id" ]]; then
        ORG_ID=$new_org_id
        show_msg "Success" "Organization ID saved: $ORG_ID" "msgbox"
    fi
}

# Function for getting terminal groups
get_terminal_groups() {
    if [[ -z $TOKEN ]]; then
        show_msg "Error" "Token not received. Please obtain a token first." "msgbox"
        return 1
    fi
    
    # Get organization ID if not set
    if [[ -z $ORG_ID ]]; then
        ORG_ID=$(get_input "Organization ID" "Enter organization ID:" "")
        if [[ -z "$ORG_ID" ]]; then
            show_msg "Error" "Organization ID is required!" "msgbox"
            return 1
        fi
    else
        local new_org_id=$(get_input "Organization ID" "Press Enter to use current: $ORG_ID\n\nOr enter new ID:" "$ORG_ID")
        if [[ ! -z "$new_org_id" ]]; then
            ORG_ID=$new_org_id
        fi
    fi
    
    local result
    result=$(curl -sX POST \
        --url https://api-ru.iiko.services/api/1/terminal_groups \
        --header "Authorization: Bearer $TOKEN" \
        --header 'Content-Type: application/json' \
        --data "{\"organizationIds\": [ \"$ORG_ID\" ], \"includeDisabled\": false}")
    
    # Format output
    local formatted_result=$(echo "$result" | jq -r '
        "TERMINAL GROUPS:\n" +
        "===============\n" +
        ([.terminalGroups[].items[] | "ID: \(.id)\nName: \(.name)\n---"] | join("\n")) +
        "\n\nTERMINAL GROUPS IN SLEEP:\n" +
        "=========================\n" +
        ([.terminalGroupsInSleep[].items[] | "ID: \(.id)\nName: \(.name)\n---"] | join("\n"))
    ')
    
    if [[ -z "$formatted_result" ]]; then
        show_msg "Error" "No terminal groups found!" "msgbox"
        return 1
    fi
    
    # Create temporary file for output
    local tempfile=$(mktemp)
    echo "$formatted_result" > "$tempfile"
    
    dialog --title "Terminal Groups" --textbox "$tempfile" 30 80
    rm "$tempfile"
    
    # Ask for terminal group
    local new_terminal_group=$(get_input "Terminal Group" "Enter terminal group ID to save:" "$TERMINAL_GROUP")
    if [[ ! -z "$new_terminal_group" ]]; then
        TERMINAL_GROUP=$new_terminal_group
        show_msg "Success" "Terminal group saved: $TERMINAL_GROUP" "msgbox"
    fi
}

# Function for getting payment types
get_payment_types() {
    if [[ -z $TOKEN ]]; then
        show_msg "Error" "Token not received. Please obtain a token first." "msgbox"
        return 1
    fi
    
    # Get organization ID if not set
    if [[ -z $ORG_ID ]]; then
        ORG_ID=$(get_input "Organization ID" "Enter organization ID:" "")
        if [[ -z "$ORG_ID" ]]; then
            show_msg "Error" "Organization ID is required!" "msgbox"
            return 1
        fi
    else
        local new_org_id=$(get_input "Organization ID" "Press Enter to use current: $ORG_ID\n\nOr enter new ID:" "$ORG_ID")
        if [[ ! -z "$new_org_id" ]]; then
            ORG_ID=$new_org_id
        fi
    fi
    
    local result
    result=$(curl -sX POST \
        --url https://api-ru.iiko.services/api/1/payment_types \
        --header "Authorization: Bearer $TOKEN" \
        --header 'Content-Type: application/json' \
        --data "{\"organizationIds\": [ \"$ORG_ID\" ] }")
    
    # Format output
    local formatted_result=$(echo "$result" | jq -r '
        .paymentTypes[] | 
        "ID: \(.id)\n" +
        "Name: \(.name)\n" +
        "Type: \(.paymentTypeKind)\n" +
        "Marketing Campaigns: \(.applicableMarketingCampaigns)\n" +
        "---"
    ')
    
    if [[ -z "$formatted_result" ]]; then
        show_msg "Error" "No payment types found!" "msgbox"
        return 1
    fi
    
    local tempfile=$(mktemp)
    echo "$formatted_result" > "$tempfile"
    
    dialog --title "Payment Types" --textbox "$tempfile" 30 80
    rm "$tempfile"
}

# Function for getting customer information
get_customer_info() {
    if [[ -z $TOKEN ]]; then
        show_msg "Error" "Token not received. Please obtain a token first." "msgbox"
        return 1
    fi
    
    # Get organization ID if not set
    if [[ -z $ORG_ID ]]; then
        ORG_ID=$(get_input "Organization ID" "Enter organization ID:" "")
        if [[ -z "$ORG_ID" ]]; then
            show_msg "Error" "Organization ID is required!" "msgbox"
            return 1
        fi
    else
        local new_org_id=$(get_input "Organization ID" "Press Enter to use current: $ORG_ID\n\nOr enter new ID:" "$ORG_ID")
        if [[ ! -z "$new_org_id" ]]; then
            ORG_ID=$new_org_id
        fi
    fi
    
    local phone=$(get_input "Phone Number" "Enter customer phone number:" "")
    
    if [[ -z "$phone" ]]; then
        show_msg "Error" "Phone number is required!" "msgbox"
        return 1
    fi
    
    local result
    result=$(curl -sX POST \
        --url https://api-ru.iiko.services/api/1/loyalty/iiko/customer/info \
        --header "Authorization: Bearer $TOKEN" \
        --header 'Content-Type: application/json' \
        --data "{\"phone\": \"$phone\", \"type\": \"phone\", \"organizationId\": \"$ORG_ID\"}")
    
    # Format JSON output
    local formatted_result=$(echo "$result" | jq '.' 2>/dev/null)
    
    if [[ -z "$formatted_result" ]]; then
        show_msg "Error" "No customer information found!" "msgbox"
        return 1
    fi
    
    local tempfile=$(mktemp)
    echo "$formatted_result" > "$tempfile"
    
    dialog --title "Customer Information" --textbox "$tempfile" 30 100
    rm "$tempfile"
}

# Function for resetting the organization ID
reset_org_id() {
    ORG_ID=""
    TERMINAL_GROUP=""
    show_msg "Success" "Organization ID and Terminal Group have been reset!" "msgbox"
}

# Function for showing the current status
show_status() {
    local status=""
    
    if [[ -z $TOKEN ]]; then
        status+="Token: NOT RECEIVED\n"
    else
        status+="Token: RECEIVED\n"
        status+="Token (first 20 chars): ${TOKEN:0:20}...\n"
    fi
    
    if [[ ! -z $API_KEY ]]; then
        status+="\nAPI Key: $API_KEY\n"
    fi
    
    status+="\n"
    
    if [[ -z $ORG_ID ]]; then
        status+="Organization ID: NOT SET\n"
    else
        status+="Organization ID: $ORG_ID\n"
    fi
    
    if [[ -z $TERMINAL_GROUP ]]; then
        status+="Terminal Group: NOT SET\n"
    else
        status+="Terminal Group: $TERMINAL_GROUP\n"
    fi
    
    show_msg "Current Status" "$status" "msgbox"
}

# Main function
main() {
    check_dialog
    
    while true; do
        # Create menu
        choice=$(dialog --clear --title "IIKO API TOOL v1.0" \
            --menu "Choose an operation:" 20 70 10 \
            1 "Get authentication token" \
            2 "Get list of organizations" \
            3 "Get terminal groups" \
            4 "Get payment types" \
            5 "Get client information" \
            6 "Reset organization ID" \
            7 "Show current status" \
            0 "Exit" \
            3>&1 1>&2 2>&3)
        
        # Check if user pressed Cancel
        if [[ $? -ne 0 ]]; then
            clear
            echo -e "${GREEN}Goodbye!${NC}"
            exit 0
        fi
        
        case $choice in
            1) get_token ;;
            2) get_organizations ;;
            3) get_terminal_groups ;;
            4) get_payment_types ;;
            5) get_customer_info ;;
            6) reset_org_id ;;
            7) show_status ;;
            0) 
                clear
                echo -e "${GREEN}Goodbye!${NC}"
                exit 0
                ;;
        esac
    done
}

# Start the program
main
