#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

# Global vars
TOKEN=""
API_KEY=""
ORG_ID=""
TERMINAL_GROUP=""
ExternalIikoWebMenu_ID=""

# Function for getting a token
get_token() {
    echo -e "${YELLOW}=== Getting an authentication token ===${NC}"
    read -p "Enter your API key: " API_KEY
    echo
    TOKEN=$(curl -sX POST \
        --url https://api-ru.iiko.services/api/1/access_token \
        --header 'Content-Type: application/json' \
        --data "{ \"apiLogin\": \"$API_KEY\" }" | jq -r '.token')    
    if [[ $TOKEN != null && $TOKEN != "" ]]; then
        echo -e "${GREEN}Token successfully received!${NC}"
        echo -e "Token: ${BLUE}$TOKEN${NC}"
    else
        echo -e "${RED}Error obtaining token!${NC}"
        TOKEN=""
    fi
}

# Function for getting a list of organizations
get_organizations() {
    echo -e "${YELLOW}=== Obtaining a list of organizations ===${NC}"
    if [[ -z $TOKEN ]]; then
        echo -e "${RED}Error: Token not received. Please obtain a token first.${NC}"
        return 1
    fi 
    curl -sX GET \
        --url https://api-ru.iiko.services/api/1/organizations \
        --header "Authorization: Bearer $TOKEN" \
        --header 'Content-Type: application/json' \
        --data "{\"returnAdditionalInfo\": true, \"includeDisabled\": true}" | \
        jq -r '.organizations[] | "ID: \(.id)\nName: \(.name)\n---"'
}

# Function for getting terminal groups
get_terminal_groups() {
    echo -e "${YELLOW}=== Obtaining terminal groups ===${NC}"
    if [[ -z $TOKEN ]]; then
        echo -e "${RED}Error: Token not received. Please obtain a token first.${NC}"
        return 1
    fi
    if [[ -z $ORG_ID ]]; then
        read -p "Enter organization ID: " ORG_ID
    else
        echo -e "Current Organization ID: ${BLUE}$ORG_ID${NC}"
        read -p "Press Enter to use the current one, or enter a new ID: " new_org_id
        if [[ ! -z $new_org_id ]]; then
            ORG_ID=$new_org_id
        fi
    fi 
    curl -sX POST \
        --url https://api-ru.iiko.services/api/1/terminal_groups \
        --header "Authorization: Bearer $TOKEN" \
        --header 'Content-Type: application/json' \
        --data "{\"organizationIds\": [ \"$ORG_ID\" ], \"includeDisabled\": false}" | \
        jq '{ 
            terminalGroups: [.terminalGroups[].items[] | {id, name}], 
            terminalGroupsInSleep: [.terminalGroupsInSleep[].items[] | {id, name}] 
        }'
}

# Function for getting payment types
get_payment_types() {
    echo -e "${YELLOW}=== Receiving payment types ===${NC}"
    if [[ -z $TOKEN ]]; then
        echo -e "${RED}Error: Token not received. Please obtain a token first.${NC}"
        return 1
    fi
    if [[ -z $ORG_ID ]]; then
        read -p "Enter organization ID: " ORG_ID
    else
        echo -e "Current Organization ID: ${BLUE}$ORG_ID${NC}"
        read -p "Press Enter to use the current one, or enter a new ID: " new_org_id
        if [[ ! -z $new_org_id ]]; then
            ORG_ID=$new_org_id
        fi
    fi
    curl -sX POST \
        --url https://api-ru.iiko.services/api/1/payment_types \
        --header "Authorization: Bearer $TOKEN" \
        --header 'Content-Type: application/json' \
        --data "{\"organizationIds\": [ \"$ORG_ID\" ] }" | \
        jq '.paymentTypes[] |= del(.terminalGroups) | .paymentTypes[]  
        | {id, name, applicableMarketingCampaigns, paymentTypeKind}'
}

# Function for getting customer information
get_customer_info() {
    echo -e "${YELLOW}=== Obtaining information about the client ===${NC}"
    
    if [[ -z $TOKEN ]]; then
        echo -e "${RED}Error: Token not received. Please obtain a token first.${NC}"
        return 1
    fi
    if [[ -z $ORG_ID ]]; then
        read -p "Enter organization ID: " ORG_ID
    else
        echo -e "Current Organization ID: ${BLUE}$ORG_ID${NC}"
        read -p "Press Enter to use the current one, or enter a new ID: " new_org_id
        if [[ ! -z $new_org_id ]]; then
            ORG_ID=$new_org_id
        fi
    fi
    read -p "Enter your phone number (format +79103972345): " number
    curl -sX POST \
        --url https://api-ru.iiko.services/api/1/loyalty/iiko/customer/info \
        --header "Authorization: Bearer $TOKEN" \
        --header 'Content-Type: application/json' \
        --data "{\"phone\": \"$number\", \"type\": \"phone\", \"organizationId\": \"$ORG_ID\"}" | jq
}

# Function for getting nomenclature
get_nomenclature() {
    echo -e "${YELLOW}=== Obtaining nomenclature ===${NC}"
    
    if [[ -z $TOKEN ]]; then
        echo -e "${RED}Error: Token not received. Please obtain a token first.${NC}"
        return 1
    fi
    
    local current_org="$ORG_ID"
    if [[ -z $current_org ]]; then
        read -p "Enter organization ID: " current_org
    else
        echo -e "Current Organization ID: ${BLUE}$current_org${NC}"
        read -p "Press Enter to use the current one, or enter a new ID: " new_org_id
        if [[ ! -z $new_org_id ]]; then
            current_org=$new_org_id
        fi
    fi
    
    echo -e "${YELLOW}Retrieving nomenclature...${NC}"
    curl -sX POST \
        --url https://api-ru.iiko.services/api/1/nomenclature \
        --header "Authorization: Bearer $TOKEN" \
        --header 'Content-Type: application/json' \
        --data "{\"organizationId\":  \"$current_org\" }" | jq > ~/nomenclature.txt
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}Nomenclature saved to ~/nomenclature.txt${NC}"
        read -p "Do you want to view the file with less? (y/n): " view_choice
        if [[ $view_choice == "y" || $view_choice == "Y" ]]; then
            less ~/nomenclature.txt
        fi
    else
        echo -e "${RED}Error retrieving nomenclature${NC}"
    fi
}

# Function for getting external Iiko Web Menu ID
get_external_menus() {
    echo -e "${YELLOW}=== Obtaining external Iiko Web Menu ID ===${NC}"
    
    if [[ -z $TOKEN ]]; then
        echo -e "${RED}Error: Token not received. Please obtain a token first.${NC}"
        return 1
    fi
    
    curl -sX POST \
        --url 'https://api-ru.iiko.services/api/2/menu' \
        --header "Authorization: Bearer $TOKEN" \
        --header 'Content-Type: application/json' | jq
}

# Function for getting menu by ID
get_menu_by_id() {
    echo -e "${YELLOW}=== Obtaining menu by external ID ===${NC}"
    
    if [[ -z $TOKEN ]]; then
        echo -e "${RED}Error: Token not received. Please obtain a token first.${NC}"
        return 1
    fi
    
    local current_org="$ORG_ID"
    if [[ -z $current_org ]]; then
        read -p "Enter organization ID: " current_org
    else
        echo -e "Current Organization ID: ${BLUE}$current_org${NC}"
        read -p "Press Enter to use the current one, or enter a new ID: " new_org_id
        if [[ ! -z $new_org_id ]]; then
            current_org=$new_org_id
        fi
    fi
    
    read -p "Enter external menu ID: " menuID
    
    echo -e "${YELLOW}Retrieving menu...${NC}"
    curl -sX POST \
        --url 'https://api-ru.iiko.services/api/2/menu/by_id' \
        --header "Authorization: Bearer $TOKEN" \
        --header 'Content-Type: application/json'  \
        --data "{\"organizationIds\": [ \"$current_org\"],  \"externalMenuId\":  \"$menuID\"}" | jq > ~/menu.txt
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}Menu saved to ~/menu.txt${NC}"
        read -p "Do you want to view the file with less? (y/n): " view_choice
        if [[ $view_choice == "y" || $view_choice == "Y" ]]; then
            less ~/menu.txt
        fi
    else
        echo -e "${RED}Error retrieving menu${NC}"
    fi
}

# Function for resetting the organization ID
reset_org_id() {
    ORG_ID=""
    echo -e "${GREEN}Organization ID reset${NC}"
}

# Function for showing the current status
show_status() {
    echo -e "${YELLOW}=== Current Status ===${NC}"
    
    if [[ -z $TOKEN ]]; then
        echo -e "Token: ${RED}not received${NC}"
    else
        echo -e "Token: ${GREEN}received${NC}"
    fi
    
    if [[ ! -z $API_KEY ]]; then
        echo -e "API Key: ${BLUE}${API_KEY}${NC}"
    fi
    
    if [[ -z $ORG_ID ]]; then
        echo -e "Organization ID: ${RED}not set${NC}"
    else
        echo -e "Organization ID: ${BLUE}$ORG_ID${NC}"
    fi
    
    if [[ -z $TERMINAL_GROUP ]]; then
        echo -e "Terminal group: ${RED}not set${NC}"
    else
        echo -e "Terminal group: ${BLUE}$TERMINAL_GROUP${NC}"
    fi  

    if [[ -z $ExternalIikoWebMenu_ID ]]; then
        echo -e "External Iiko Web Menu ID: ${RED}not set${NC}"
    else
        echo -e "External Iiko Web Menu ID: ${BLUE}$ExternalIikoWebMenu_ID${NC}"
    fi     
}

show_menu() {
    clear
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}         IIKO API TOOL v1.0            ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    show_status
    echo ""
    echo -e "${YELLOW}Available operations:${NC}"
    echo "1) Get authentication token"
    echo "2) Get list of organizations"
    echo "3) Get terminal groups"
    echo "4) Get payment types"
    echo "5) Get client information"
    echo "6) Get nomenclature (saves to file)"
    echo "7) Get external Iiko Web Menu ID"
    echo "8) Get menu by external Iiko Web Menu ID (saves to file)"
    echo "9) Reset organization ID"
    echo "10) Show status"
    echo "0|q|Q) Exit"
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo ""
}

main() {
    while true; do
        show_menu
        read -p "Select an operation (0-10): " choice
        case $choice in
            1) get_token ;;
            2) get_organizations; read -p 'Organization ID: ' ORG_ID ;;
            3) get_terminal_groups; read -p 'Terminal group: ' TERMINAL_GROUP ;;
            4) get_payment_types ;;
            5) get_customer_info ;;
            6) get_nomenclature ;;
            7) get_external_menus; read -p 'Iiko Web Menu ID: ' ExternalIikoWebMenu_ID ;;
            8) get_menu_by_id ;;
            9) reset_org_id ;;
            10) show_status ;;
            0|q|Q) echo -e "${GREEN}Goodbye!${NC}"; exit 0 ;;
            *) echo -e "${RED}Incorrect choice! Please select 0-10${NC}" ;;
        esac
        echo ""
        read -p "Press Enter to continue..."
    done
}

# Start the program
main
