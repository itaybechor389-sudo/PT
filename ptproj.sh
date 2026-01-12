#!/bin/bash


NETWORK=""
BASE_DIR=""
MODE=""           # basic / full
LOG_FILE=""
TOOLS_LOG=""
HOSTS=()


# ---------- Utility functions ----------



    banner() {
    clear
    if [ -x /usr/games/lolcat ]; then
       
        cat << "EOF" | /usr/games/lolcat
+==============================================================================+
|                                                                              |
|                          ████████ █████████████                              |
|                          ██    ██       ██                                   |
|                          ███████        ██                                   |
|                          ██             ██                                   |
|                          ██             ██                                   |
|                                                                              |
|                        PENETRATION TESTING PROJECT                           |
|                             by Itay Bechor                                   |
|                                                                              |
+==============================================================================+


EOF
fi   
}



log_stage() {
    local msg="$1"
    echo -e "\n[*] $msg"
    [[ -n "$LOG_FILE" ]] && \
        echo "[*] $(date '+%Y-%m-%d %H:%M:%S')  $msg" >> "$LOG_FILE"
}


log_tools_summary() {
    # Summary log of all tools used in this PT project run
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"

    {
        printf '[%s] nmap executed (network=%s, output_dir=%s)\n' "$ts" "$NETWORK" "$BASE_DIR"
        printf '[%s] hydra executed (targets=%s, users=./users.txt, passwords=./passwords.lst)\n' "$ts" "${HOSTS[*]}"
        printf '[%s] medusa executed (targets=%s, users=./users.txt, passwords=./passwords.lst)\n' "$ts" "${HOSTS[*]}"
        printf '[%s] searchsploit executed (services_file=%s)\n' "$ts" "$BASE_DIR/services.txt"
    } >> "$TOOLS_LOG"
}






validate_network() {
    # Very simple validation
    if [[ -z "$NETWORK" ]]; then
        return 1
    fi
    if [[ "$NETWORK" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]]; then
        return 0
    else
        return 1
    fi
}

# ---------- 1. Get user input ----------

get_user_input() {
    banner

    read -rp "Enter network to scan (e.g. 192.168.56.0/24): " NETWORK
    while ! validate_network; do
        echo "Invalid network format. Try again."
        read -rp "Enter network to scan (e.g. 192.168.56.0/24): " NETWORK
    done

    read -rp "Enter base output directory name (will be created): " BASE_DIR
mkdir -p "$BASE_DIR" || { echo "Could not create directory."; exit 1; }

LOG_FILE="$BASE_DIR/run.log"
TOOLS_LOG="$BASE_DIR/tools.log"
: > "$TOOLS_LOG"

    echo "Choose scan mode:"
    echo " 1) Basic"
    echo " 2) Full"
    read -rp "Enter 1 or 2: " choice
    case "$choice" in
        1) MODE="basic" ;;
        2) MODE="full" ;;
        *) MODE="basic" ;;
    esac

    log_stage "User input collected. Network=$NETWORK, Mode=$MODE, BaseDir=$BASE_DIR"
}

# ---------- 1.x Host discovery ----------

discover_hosts() {
    log_stage "Starting host discovery (nmap -sn) on $NETWORK"

    nmap -sn -oG "$BASE_DIR/host_discovery.gnmap" "$NETWORK" >/dev/null 2>&1

    # Grep IPs that are up
    mapfile -t HOSTS < <(grep "Up$" "$BASE_DIR/host_discovery.gnmap" | awk '{print $2}')

    if [[ ${#HOSTS[@]} -eq 0 ]]; then
        log_stage "No live hosts found. Exiting."
        echo "No live hosts found in $NETWORK"
        exit 0
    fi

    log_stage "Host discovery finished. Found ${#HOSTS[@]} live hosts."
    echo "Live hosts:"
    printf '  %s\n' "${HOSTS[@]}"
}

# ---------- 2. Basic scan per host (TCP/UDP + service version) ----------

# Run fast TCP scan with Nmap + UDP scan with Masscan for a single host
# --------- 2. Basic scan per host (TCP + UDP full) ---------

# Run fast TCP scan with Nmap + full UDP discovery with Masscan + targeted Nmap UDP
# --------- 1. Basic scan per host (TCP + UDP) ----------
# --------- 2. Basic scan per host (TCP + UDP) ---------
# 1.3.1 Basic: scans the network for TCP and UDP, including the service version

# -------- 2. Basic scan per host (TCP + UDP full) --------
basic_scan_host() {
    local host="$1"
    local host_dir="$2"

    mkdir -p "$host_dir"

    
    log_stage "Running BASIC TCP scan on $host (Nmap)"
    nmap -sS -sV -T4 -F -oA "$host_dir/nmap_basic_tcp" "$host" >/dev/null 2>&1
    log_stage "BASIC TCP scan for $host completed."

   
    log_stage "Running BASIC UDP scan on $host (top 50 ports)"
    nmap -sU -sV --top-ports 50 -T4 -oA "$host_dir/nmap_basic_udp" "$host" >/dev/null 2>&1
    log_stage "BASIC UDP scan for $host completed."

   
    local udp_nmap="$host_dir/nmap_basic_udp.nmap"
    local udp_summary=""
    local masscan_udp_file="$host_dir/masscan_udp_full.txt"

   
    : > "$masscan_udp_file"

    if [[ -f "$udp_nmap" ]]; then
       
        udp_summary=$(grep -E '^[0-9]+/udp[[:space:]]+open' "$udp_nmap" \
            | awk '{print $1}' | paste -sd, -)

        
        # open udp <port> <host> <timestamp>
        grep -E '^[0-9]+/udp[[:space:]]+open' "$udp_nmap" \
            | awk -v host="$host" '{split($1,p,"/"); printf "open udp %s %s %d\n", p[1], host, systime()}' \
            >> "$masscan_udp_file"
    fi

    if [[ -n "$udp_summary" ]]; then
        log_stage "UDP open ports on $host (top 50): $udp_summary"
    else
        log_stage "No UDP open ports found on $host (top 50)."
    fi

    log_stage "Basic scan for $host completed."
}




# ---------- 2. Weak Credentials per host ----------

# Run automated weak-credential checks with Hydra / Medusa
# --- 2. Weak Credentials per host --- #
# ---------------------------------------------------------
# Section 2: Weak Credentials Function
# ---------------------------------------------------------
weak_credentials_attack() {
    echo -e "\n[+] --- Starting Phase 2: Weak Credentials (Friend's Logic) ---"

   
    read -e -p "Enter path to USERS list [default: ./users.txt]: " user_list
    user_list=${user_list:-./users.txt}
    
    read -e -p "Enter path to PASSWORDS list [default: ./passwords.txt]: " pass_list
    pass_list=${pass_list:-./passwords.txt}

    if [[ ! -f "$user_list" || ! -f "$pass_list" ]]; then
        echo "[-] Error: Wordlists not found!"
        return
    fi

    
    target_ports="21 22 23 3389 445"
    
   
    if [ ${#HOSTS[@]} -eq 0 ]; then
        echo "[-] No hosts defined. Running logic on network range..."
        
        nmap -n -Pn -p $target_ports -oG "$BASE_DIR/active_ips.txt" "$NETWORK" > /dev/null
        mapfile -t HOSTS < <(grep "Up" "$BASE_DIR/active_ips.txt" | awk '{print $2}')
    fi

    echo -e "[*] Target Hosts: ${HOSTS[@]}"

   
    for ip in "${HOSTS[@]}"; do
        echo -e "\n[*] Checking open ports on $ip..."
        
        
        host_dir="$BASE_DIR/$ip"
        mkdir -p "$host_dir"
        
        
        port_info="$host_dir/port_info.txt"
        nmap -n -Pn -p 21,22,23,3389,445 "$ip" -oG "$port_info" > /dev/null

        
        for port in $target_ports; do
            
            
            if grep -q "$port/open" "$port_info"; then
                
                
                service=""
                case $port in
                    21) service="ftp" ;;
                    22) service="ssh" ;;
                    23) service="telnet" ;;
                    445) service="smb" ;;
                    3389) service="rdp" ;;
                esac

                if [ -n "$service" ]; then
                    echo -e "\033[1;33m[+] Found open port $port -> Starting Hydra on $service...\033[0m"
                    
                    
                
                    hydra_output="$host_dir/hydra_${service}.txt"
                    
                    hydra -L "$user_list" -P "$pass_list" "$service://$ip" -t 4 -f -I -o "$hydra_output" > /dev/null 2>&1
                    
                    
                    if [ -s "$hydra_output" ]; then
                        echo -e "\033[1;32m[V] SUCCESS: Password found for $service on $ip!\033[0m"
                        grep "login:" "$hydra_output"
                       
                        grep "login:" "$hydra_output" >> "$BASE_DIR/final_weak_creds.txt"
                    else
                        echo "[-] No password found for $service."
                    fi
                fi
            fi
        done
    done
    
    echo -e "\n[+] Finished. All found credentials are in $BASE_DIR/final_weak_creds.txt"
}

# -------- 3. Mapping Vulnerabilities (Full mode) per host --------
vuln_mapping_host() {
    local host="$1"
    local host_dir="$2"

    
    if [[ "$MODE" != "full" ]]; then
        return
    fi

   
    log_stage "Running vulnerability NSE scripts on $host"
   nmap -sS -sV -p- \
     --script=vuln,vulners,auth \
     -T4 -oA "$host_dir/nmap_vuln" "$host" >/dev/null 2>&1
    log_stage "NSE vuln scan for $host completed. Running Searchsploit mapping."

    
    local nmap_vuln_map="$host_dir/nmap_vuln.nmap"
    if [[ ! -f "$nmap_vuln_map" ]]; then
        echo "[!] $nmap_vuln_map not found for $host - skipping Searchsploit mapping."
        return
    fi

    local services_file="$host_dir/services.txt"
    grep -E '^[0-9]+/(tcp|udp)[[:space:]]+open' "$nmap_vuln_map" \
        | awk '{print $3, $4}' \
        | sort -u >"$services_file" 2>/dev/null

    if [[ ! -s "$services_file" ]]; then
        log_stage "No services extracted from NSE output for $host (nothing to run Searchsploit on)."
        return
    fi

    
    local ss_file="$host_dir/searchsploit.txt"
    : >"$ss_file"

    while read -r svc ver; do
        [[ -z "$svc" ]] && continue
        {
            echo "==== $svc $ver ===="
            searchsploit "$svc $ver"
            echo
        } >>"$ss_file"
    done <"$services_file"

    log_stage "Searchsploit mapping for $host finished (results in $ss_file)."
}



# ---------- 4. Summary / Search / Zip ----------

show_summary() {
    log_stage "Summary stage"

    echo
    echo "Base results directory: $BASE_DIR"
    echo "Hosts scanned: ${#HOSTS[@]}"
    printf '  %s\n' "${HOSTS[@]}"
    echo
    echo "Files in base directory:"
    ls -1 "$BASE_DIR"
}

search_in_results() {
    echo
    read -rp "Enter keyword to search in all results (or empty to skip): " keyword
    if [[ -z "$keyword" ]]; then
        log_stage "User skipped search."
        return
    fi

    log_stage "Searching for '$keyword' in $BASE_DIR"
    grep -Rni --color=always "$keyword" "$BASE_DIR" || echo "No matches found."
}

zip_results() {
    echo
    read -rp "Do you want to compress all results into a zip file? (y/n): " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        local zip_name="${BASE_DIR}.zip"
        log_stage "Creating zip archive $zip_name"
        zip -r "$zip_name" "$BASE_DIR" >/dev/null
        echo "Zip created: $zip_name"
    else
        log_stage "User chose not to zip results."
    fi
}

# ---------- main ----------

main() {
    get_user_input
    discover_hosts

    
    for host in "${HOSTS[@]}"; do
        host_dir="$BASE_DIR/$host"
        mkdir -p "$host_dir"

        basic_scan_host "$host" "$host_dir"
        vuln_mapping_host "$host" "$host_dir"   
    done

  weak_credentials_attack

show_summary
search_in_results
zip_results
log_tools_summary

log_stage "Script finished."
echo "Done."
}

main
