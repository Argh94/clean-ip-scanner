#!/data/data/com.termux/files/usr/bin/bash

RED='\e[31m'
GREEN='\e[32m'
CYAN='\e[36m'
RESET='\e[0m'

setup_termux() {
    echo -e "${GREEN}Updating system and installing required packages...${RESET}"
    pkg update && pkg upgrade -y
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error updating system. Try changing the Termux repository with 'termux-change-repo' or check your internet connection.${RESET}"
        exit 1
    fi
    for pkg in curl jq dnsutils; do
        command -v $pkg >/dev/null 2>&1 || {
            echo -e "${GREEN}Installing $pkg...${RESET}"
            pkg install $pkg -y
            if [ $? -ne 0 ]; then
                echo -e "${RED}Error installing $pkg. Please check your internet connection.${RESET}"
                exit 1
            fi
        }
    done
    echo -e "${GREEN}Packages successfully installed and updated.${RESET}"
}

get_first_ip() {
    local cidr=$1
    base_ip=$(echo "$cidr" | cut -d'/' -f1)
    IFS='.' read -r a b c d <<< "$base_ip"
    first_ip="$a.$b.$c.$((d + 1))"
    echo "$first_ip"
}

check_ping() {
    local ip=$1
    local source=$2
    local temp_file=$3
    ping_result=$(ping -c 4 -W 7 "$ip" 2>/dev/null | grep -o "time=[0-9.]* ms" | awk -F'=' '{print $2}' | sort -n | head -1)
    if [ -n "$ping_result" ]; then
        echo "$source,$ip,$ping_result" >> "$temp_file"
        echo -e "${CYAN}[$source] $ip: $ping_result${RESET}"
    else
        echo "$source,$ip,Unreachable" >> "$temp_file"
        echo -e "${RED}[$source] $ip: Unreachable${RESET}"
    fi
}

delete_script() {
    echo -e "${GREEN}Deleting script and related files...${RESET}"
    rm -f /data/data/com.termux/files/usr/tmp/temp_ips.txt
    rm -f /data/data/com.termux/files/usr/tmp/sorted_ips.txt
    rm -f cloudflare_ips.txt
    rm -f domains.json
    rm -f "$0"  
    echo -e "${GREEN}Script and related files removed. Exiting...${RESET}"
    exit 0
}

show_menu() {
    clear
    echo -e "${GREEN}             ▄▀▄     ▄▀▄${RESET}"
    echo -e "${GREEN}            ▄█░░▀▀▀▀▀░░█▄${RESET}"
    echo -e "${GREEN}        ▄▄  █░░░░░░░░░░░█  ▄▄${RESET}"
    echo -e "${GREEN}       █▄▄█ █░░█░░┬░░█░░█ █▄▄█${RESET}"
    echo -e "${CYAN} ╔═══════════════════════════════════════╗${RESET}"
    echo -e "${GREEN} ║ ♚ Project: Clean IP Scanner           ║${RESET}"
    echo -e "${GREEN} ║ ♚ Author: Argh94                      ║${RESET}"
    echo -e "${GREEN} ║ ♚ GitHub: https://GitHub.com/Argh94   ║${RESET}"
    echo -e "${CYAN} ╚═══════════════════════════════════════╝${RESET}"
    echo -e "${RESET}"
    echo -e "${CYAN}Please select an option:${RESET}"
    echo -e "${GREEN}1. Check Cloudflare IPs${RESET}"
    echo -e "${GREEN}2. Check IRCF IPs${RESET}"
    echo -e "${GREEN}3. Check Gcore IPs${RESET}"
    echo -e "${GREEN}4. Check Fastly IPs${RESET}"
    echo -e "${RED}5. Exit${RESET}"
    echo -e "${RED}6. Delete Script${RESET}"
    echo -e "${CYAN}Enter option number (1-6): ${RESET}"
}

cleanup() {
    echo -e "${GREEN}Cleaning up temporary files...${RESET}"
    rm -f /data/data/com.termux/files/usr/tmp/temp_ips.txt
    rm -f /data/data/com.termux/files/usr/tmp/sorted_ips.txt
    rm -f cloudflare_ips.txt
    echo -e "${GREEN}All temporary files removed. Exiting...${RESET}"
    exit 0
}

trap cleanup SIGINT SIGTERM EXIT

setup_termux

while true; do
    show_menu
    read choice
    TEMP_FILE="/data/data/com.termux/files/usr/tmp/temp_ips.txt"
    rm -f "$TEMP_FILE"

    case $choice in
        1)
            echo -e "${GREEN}Fetching Cloudflare IPs...${RESET}"
            curl -s --connect-timeout 15 --retry 2 https://www.cloudflare.com/ips-v4 > cloudflare_ips.txt
            curl_status=$?
            if [ $curl_status -ne 0 ]; then
                echo -e "${RED}Error fetching Cloudflare IPs (Error code: $curl_status). Try enabling a VPN or checking your internet connection.${RESET}"
                read -p "Press Enter to return to menu..."
                continue
            fi
            if [ ! -s cloudflare_ips.txt ]; then
                echo -e "${RED}No Cloudflare IPs retrieved. Try enabling a VPN or checking your internet connection.${RESET}"
                read -p "Press Enter to return to menu..."
                continue
            fi
            while IFS= read -r cidr; do
                ip=$(get_first_ip "$cidr")
                check_ping "$ip" "Cloudflare" "$TEMP_FILE"
            done < cloudflare_ips.txt
            rm -f cloudflare_ips.txt
            SOURCE="cloudflare"
            ;;
        2)
            echo -e "${GREEN}Fetching IRCF IPs...${RESET}"
            if [ -f "domains.json" ]; then
                ircf_domains=$(jq -r '.addresses[]' domains.json 2>/dev/null)
                if [ $? -ne 0 ]; then
                    echo -e "${RED}Error reading domains.json. Please check the file structure.${RESET}"
                    read -p "Press Enter to return to menu..."
                    continue
                fi
                for domain in $ircf_domains; do
                    ip=$(dig +short @1.1.1.1 "$domain" | grep -E '^[0-9.]+$')
                    if [ -z "$ip" ]; then
                        echo -e "${RED}IRCF-$domain: Unable to resolve IP${RESET}"
                        echo "IRCF-$domain,$domain,Unreachable" >> "$TEMP_FILE"
                    else
                        for single_ip in $ip; do
                            check_ping "$single_ip" "IRCF-$domain" "$TEMP_FILE"
                        done
                    fi
                done
            else
                echo -e "${RED}domains.json file not found. Please ensure it exists in the current directory.${RESET}"
                read -p "Press Enter to return to menu..."
                continue
            fi
            SOURCE="ircf"
            ;;
        3)
            echo -e "${GREEN}Fetching Gcore IPs...${RESET}"
            gcore_response=$(curl -s --connect-timeout 15 --retry 2 https://api.gcore.com/cdn/public-ip-list)
            curl_status=$?
            if [ $curl_status -ne 0 ]; then
                echo -e "${RED}Error fetching Gcore IPs (Error code: $curl_status). Try enabling a VPN or checking your internet connection. If the issue persists, the Gcore API may be temporarily unavailable.${RESET}"
                read -p "Press Enter to return to menu..."
                continue
            fi
            gcore_ips=$(echo "$gcore_response" | jq -r '.addresses[]' 2>/dev/null)
            if [ -z "$gcore_ips" ]; then
                echo -e "${RED}Error parsing JSON from Gcore. Please check the API response structure or try again later.${RESET}"
                read -p "Press Enter to return to menu..."
                continue
            fi
            for cidr in $gcore_ips; do
                ip=$(echo "$cidr" | cut -d'/' -f1)  # حذف /32 و گرفتن IP خالص
                check_ping "$ip" "Gcore" "$TEMP_FILE"
            done
            SOURCE="gcore"
            ;;
        4)
            echo -e "${GREEN}Fetching Fastly IPs...${RESET}"
            fastly_response=$(curl -s --connect-timeout 15 --retry 2 -H "Accept: application/json" https://api.fastly.com/public-ip-list)
            curl_status=$?
            if [ $curl_status -ne 0 ]; then
                echo -e "${RED}Error fetching Fastly IPs (Error code: $curl_status). Try enabling a VPN or checking your internet connection.${RESET}"
                read -p "Press Enter to return to menu..."
                continue
            fi
            fastly_ips=$(echo "$fastly_response" | jq -r '.addresses[]' 2>/dev/null)
            if [ -z "$fastly_ips" ]; then
                echo -e "${RED}Error parsing JSON from Fastly. Please check the API response structure or try again later.${RESET}"
                read -p "Press Enter to return to menu..."
                continue
            fi
            for cidr in $fastly_ips; do
                ip=$(get_first_ip "$cidr")
                check_ping "$ip" "Fastly" "$TEMP_FILE"
            done
            SOURCE="fastly"
            ;;
        5)
            echo -e "${RED}Exiting script...${RESET}"
            cleanup
            ;;
        6)
            delete_script
            ;;
        *)
            echo -e "${RED}Invalid option! Please enter a number between 1 and 6.${RESET}"
            read -p "Press Enter to return to menu..."
            continue
            ;;
    esac

    echo -e "${GREEN}Sorting results...${RESET}"
    if [ -f "$TEMP_FILE" ]; then
        sort -t',' -k3 -n "$TEMP_FILE" > /data/data/com.termux/files/usr/tmp/sorted_ips.txt
        echo -e "${GREEN}Sorted IPs (by latency):${RESET}"
        echo -e "${CYAN}Source,IP,Ping${RESET}"
        reachable_found=false
        while IFS=',' read -r src ip ping; do
            if [ "$ping" == "Unreachable" ]; then
                echo -e "${RED}$src,$ip,$ping${RESET}"
            else
                echo -e "${GREEN}$src,$ip,$ping${RESET}"
                reachable_found=true
            fi
        done < /data/data/com.termux/files/usr/tmp/sorted_ips.txt
        if [ "$reachable_found" = false ]; then
            echo -e "${RED}No reachable IPs found. Try enabling a VPN or using a different ISP (e.g., MCI, MTN).${RESET}"
        fi
    else
        echo -e "${RED}No IPs found. Try enabling a VPN or checking your internet connection.${RESET}"
    fi
    read -p "${CYAN}Press Enter to return to menu...${RESET}"
done
