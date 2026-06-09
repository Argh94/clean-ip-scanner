#!/data/data/com.termux/files/usr/bin/bash

RED='\e[31m'
GREEN='\e[32m'
CYAN='\e[36m'
RESET='\e[0m'

# ==================== تنظیمات ====================
TEMP_DIR="/data/data/com.termux/files/usr/tmp"
mkdir -p "$TEMP_DIR"

setup_termux() {
    echo -e "${GREEN}Updating system and installing required packages...${RESET}"
    pkg update && pkg upgrade -y
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error updating system. Try changing the Termux repository.${RESET}"
        exit 1
    fi

    for pkg in curl jq dnsutils; do
        command -v $pkg >/dev/null 2>&1 || {
            echo -e "${GREEN}Installing $pkg...${RESET}"
            pkg install $pkg -y
            if [ $? -ne 0 ]; then
                echo -e "${RED}Error installing $pkg.${RESET}"
                exit 1
            fi
        }
    done
    echo -e "${GREEN}Packages successfully installed.${RESET}"
}

get_first_ip() {
    local cidr=$1
    echo "$cidr" | cut -d'/' -f1
}

check_ping() {
    local ip=$1
    local source=$2
    local temp_file=$3

    # Ping بهتر: ۳ پکت، timeout ۵ ثانیه
    local ping_result
    ping_result=$(ping -c 3 -W 5 "$ip" 2>/dev/null | 
                  grep -o 'time=[0-9.]*' | 
                  cut -d= -f2 | 
                  sort -n | head -n1)

    if [ -n "$ping_result" ]; then
        echo "$source,$ip,$ping_result" >> "$temp_file"
        echo -e "${CYAN}[$source] $ip → ${ping_result} ms${RESET}"
    else
        echo "$source,$ip,Unreachable" >> "$temp_file"
        echo -e "${RED}[$source] $ip → Unreachable${RESET}"
    fi
}

cleanup() {
    echo -e "${GREEN}Cleaning up temporary files...${RESET}"
    rm -f "$TEMP_DIR/temp_ips_"*.txt
    rm -f cloudflare_ips.txt
    echo -e "${GREEN}Cleanup completed.${RESET}"
}

delete_script() {
    echo -e "${GREEN}Deleting script and all related files...${RESET}"
    rm -f "$TEMP_DIR/temp_ips_"*.txt
    rm -f cloudflare_ips.txt domains.json sorted_ips.txt
    rm -f "$0"
    echo -e "${GREEN}Script and files removed successfully. Goodbye.${RESET}"
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
    echo -e ""
    echo -e "${CYAN}Please select an option:${RESET}"
    echo -e "${GREEN}1. Check Cloudflare IPs${RESET}"
    echo -e "${GREEN}2. Check IRCF IPs${RESET}"
    echo -e "${GREEN}3. Check Gcore IPs${RESET}"
    echo -e "${GREEN}4. Check Fastly IPs${RESET}"
    echo -e "${RED}5. Exit${RESET}"
    echo -e "${RED}6. Delete Script${RESET}"
    echo -e "${CYAN}Enter option number (1-6): ${RESET}"
}

# ==================== تله سیگنال ====================
trap 'cleanup; exit 0' SIGINT SIGTERM
# تله EXIT حذف شد تا وقتی با exit 0 خارج می‌شویم فایل‌ها پاک نشوند

setup_termux

while true; do
    show_menu
    read -r choice
    TEMP_FILE="$TEMP_DIR/temp_ips_$$.txt"
    rm -f "$TEMP_FILE"

    case $choice in
        1)
            echo -e "${GREEN}Fetching Cloudflare IPs...${RESET}"
            curl -s --connect-timeout 15 --retry 3 https://www.cloudflare.com/ips-v4 -o cloudflare_ips.txt
            if [ ! -s cloudflare_ips.txt ]; then
                echo -e "${RED}Failed to fetch Cloudflare IPs. Check your connection/VPN.${RESET}"
                read -p "Press Enter to continue..."
                continue
            fi
            while IFS= read -r cidr || [ -n "$cidr" ]; do
                [ -z "$cidr" ] && continue
                ip=$(get_first_ip "$cidr")
                check_ping "$ip" "Cloudflare" "$TEMP_FILE"
            done < cloudflare_ips.txt
            rm -f cloudflare_ips.txt
            ;;

        2)
            echo -e "${GREEN}Fetching IRCF IPs...${RESET}"
            if [ ! -f "domains.json" ]; then
                echo -e "${RED}domains.json not found in current directory!${RESET}"
                read -p "Press Enter to continue..."
                continue
            fi

            while IFS= read -r domain || [ -n "$domain" ]; do
                [ -z "$domain" ] && continue
                echo -e "${GREEN}Resolving $domain ...${RESET}"
                ips=$(dig +short @1.1.1.1 "$domain" | grep -E '^[0-9.]+$')
                if [ -z "$ips" ]; then
                    echo -e "${RED}IRCF-$domain: Unable to resolve${RESET}"
                    echo "IRCF-$domain,$domain,Unreachable" >> "$TEMP_FILE"
                else
                    for ip in $ips; do
                        check_ping "$ip" "IRCF-$domain" "$TEMP_FILE"
                    done
                fi
            done < <(jq -r '.addresses[]' domains.json 2>/dev/null)
            ;;

        3)
            echo -e "${GREEN}Fetching Gcore IPs...${RESET}"
            response=$(curl -s --connect-timeout 15 --retry 3 https://api.gcore.com/cdn/public-ip-list)
            if [ $? -ne 0 ] || [ -z "$response" ]; then
                echo -e "${RED}Failed to fetch Gcore IPs.${RESET}"
                read -p "Press Enter to continue..."
                continue
            fi
            while IFS= read -r cidr || [ -n "$cidr" ]; do
                [ -z "$cidr" ] && continue
                ip=$(echo "$cidr" | cut -d'/' -f1)
                check_ping "$ip" "Gcore" "$TEMP_FILE"
            done < <(echo "$response" | jq -r '.addresses[]' 2>/dev/null)
            ;;

        4)
            echo -e "${GREEN}Fetching Fastly IPs...${RESET}"
            response=$(curl -s --connect-timeout 15 --retry 3 -H "Accept: application/json" https://api.fastly.com/public-ip-list)
            if [ $? -ne 0 ] || [ -z "$response" ]; then
                echo -e "${RED}Failed to fetch Fastly IPs.${RESET}"
                read -p "Press Enter to continue..."
                continue
            fi
            while IFS= read -r cidr || [ -n "$cidr" ]; do
                [ -z "$cidr" ] && continue
                ip=$(get_first_ip "$cidr")
                check_ping "$ip" "Fastly" "$TEMP_FILE"
            done < <(echo "$response" | jq -r '.addresses[]' 2>/dev/null)
            ;;

        5)
            echo -e "${RED}Exiting...${RESET}"
            cleanup
            exit 0
            ;;

        6)
            delete_script
            ;;

        *)
            echo -e "${RED}Invalid option! Please choose 1-6.${RESET}"
            read -p "Press Enter to continue..."
            continue
            ;;
    esac

    # ==================== مرتب‌سازی هوشمند ====================
    if [ -f "$TEMP_FILE" ] && [ -s "$TEMP_FILE" ]; then
        echo -e "\n${GREEN}Sorting results by latency...${RESET}"
        
        # تبدیل Unreachable به عدد بالا برای مرتب‌سازی درست
        awk -F',' '
        {
            if ($3 == "Unreachable") 
                print $1 "," $2 ",999999"
            else 
                print $0
        }' "$TEMP_FILE" | sort -t',' -k3 -n > "$TEMP_DIR/sorted_ips.txt"

        echo -e "${CYAN}Source, IP, Ping (ms)${RESET}"
        echo -e "${CYAN}────────────────────────────────────${RESET}"

        reachable_found=false
        while IFS=',' read -r src ip ping; do
            if [ "$ping" = "999999" ]; then
                echo -e "${RED}$src,$ip,Unreachable${RESET}"
            else
                echo -e "${GREEN}$src,$ip,${ping} ms${RESET}"
                reachable_found=true
            fi
        done < "$TEMP_DIR/sorted_ips.txt"

        if [ "$reachable_found" = false ]; then
            echo -e "\n${RED}No reachable IPs found. Try VPN or different ISP.${RESET}"
        fi
    else
        echo -e "${RED}No results found.${RESET}"
    fi

    read -p "${CYAN}Press Enter to return to menu...${RESET}"
done
