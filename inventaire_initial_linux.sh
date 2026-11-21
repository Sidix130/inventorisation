#!/usr/bin/env bash
# =============================================================================
# SYNOPSIS
#     Inventaire initial de l'infrastructure personnelle - Linux.
# DESCRIPTION
#     Produit un rapport technique en lecture seule, sans elevation (aucun sudo),
#     sans installation ni modification volontaire de la configuration.
#     Les identifiants materiels (numeros de serie, UUID, MAC/BSSID) et les secrets
#     ne sont pas demandes ni inscrits volontairement dans le rapport.
# NOTES
#     Compatible Bash 4+ (Debian, Ubuntu, Fedora, RHEL, Arch, Alpine, etc.).
#     Le rapport contient tout de meme des informations potentiellement sensibles
#     (nom de machine, adresses IP locales, DNS, SSID Wi-Fi, ports et services).
# =============================================================================

set -u

# Verification du shell
if [ -z "${BASH_VERSION:-}" ]; then
    echo "ERREUR : ce script necessite Bash." >&2
    exit 1
fi

OUTPUT_PATH="${1:-}"

# -----------------------------------------------------------------------------
# Preparation du rapport en memoire
# -----------------------------------------------------------------------------
REPORT=()

add_line() {
    REPORT+=("${1:-}")
}

add_section() {
    local title="$1"
    add_line ""
    add_line ""
    add_line "============================================================================"
    add_line "  $title"
    add_line "============================================================================"
}

add_subsection() {
    local title="$1"
    add_line ""
    add_line "--- $title ---"
}

add_result() {
    local label="$1"
    local cmd="$2"

    add_subsection "$label"
    local output
    if output=$(eval "$cmd" 2>&1); then
        if [ -z "$(printf '%s' "$output" | tr -d '[:space:]')" ]; then
            add_line "[Aucune donnee retournee]"
        else
            while IFS= read -r line || [ -n "$line" ]; do
                add_line "$line"
            done <<< "$output"
        fi
    else
        if [ -n "$output" ]; then
            while IFS= read -r line || [ -n "$line" ]; do
                add_line "$line"
            done <<< "$output"
        else
            add_line "[ERREUR DE COLLECTE ou commande non disponible]"
        fi
    fi
}

# -----------------------------------------------------------------------------
# 0. Identification et contexte
# -----------------------------------------------------------------------------
Add-Section() { add_section "$@"; }
add_section "0 - IDENTIFICATION ET CONTEXTE"
add_line "Date de collecte : $(date --iso-8601=seconds 2>/dev/null || date +"%Y-%m-%dT%H:%M:%S%z")"
add_line "Nom de la machine : $(uname -n)"
add_line "Utilisateur courant : non collecte"
add_line "Elevation administrateur : non demandee / non utilisee (uid=$(id -u))"
add_line "Version Bash : $BASH_VERSION"

add_result "Systeme d'exploitation" '
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        printf "%-20s : %s\n" "Distribution" "${PRETTY_NAME:-$NAME}"
        printf "%-20s : %s\n" "ID" "${ID:-Inconnu}"
        printf "%-20s : %s\n" "Version" "${VERSION:-$VERSION_ID}"
    else
        printf "%-20s : %s\n" "Distribution" "Fichier /etc/os-release introuvable"
    fi
    printf "%-20s : %s\n" "Noyau" "$(uname -srm)"
    printf "%-20s : %s\n" "Architecture" "$(uname -m)"
    install_date=$(stat -c "%w" / 2>/dev/null || stat -c "%y" / 2>/dev/null || echo "Indisponible")
    printf "%-20s : %s\n" "Date installation" "$install_date"
'

add_result "Contexte de session et demarrage" '
    printf "%-20s : %s\n" "Fuseau horaire" "$(date +"%Z (UTC%z)")"
    printf "%-20s : %s\n" "Langue locale" "${LANG:-Non definie}"
    boot_time=$(who -b 2>/dev/null | awk "{print \$3, \$4}" || uptime -s 2>/dev/null || echo "Indisponible")
    printf "%-20s : %s\n" "Dernier demarrage" "$boot_time"
    printf "%-20s : %s\n" "Duree de fonctionnement" "$(uptime -p 2>/dev/null || uptime)"
    printf "%-20s : %s\n" "Type systeme" "$(uname -o 2>/dev/null || echo "GNU/Linux")"
'

# -----------------------------------------------------------------------------
# 1. Identite materielle (sans numeros de serie ni UUID)
# -----------------------------------------------------------------------------
add_section "1 - IDENTITE MATERIELLE"

add_result "Ordinateur et carte mere" '
    sys_vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || echo "Non accessible")
    product_name=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "Non accessible")
    product_version=$(cat /sys/class/dmi/id/product_version 2>/dev/null || echo "Non accessible")
    board_vendor=$(cat /sys/class/dmi/id/board_vendor 2>/dev/null || echo "Non accessible")
    board_name=$(cat /sys/class/dmi/id/board_name 2>/dev/null || echo "Non accessible")
    board_version=$(cat /sys/class/dmi/id/board_version 2>/dev/null || echo "Non accessible")
    bios_vendor=$(cat /sys/class/dmi/id/bios_vendor 2>/dev/null || echo "Non accessible")
    bios_version=$(cat /sys/class/dmi/id/bios_version 2>/dev/null || echo "Non accessible")
    bios_date=$(cat /sys/class/dmi/id/bios_date 2>/dev/null || echo "Non accessible")

    printf "%-22s : %s\n" "Fabricant systeme" "$sys_vendor"
    printf "%-22s : %s\n" "Modele systeme" "$product_name"
    printf "%-22s : %s\n" "Version systeme" "$product_version"
    printf "%-22s : %s\n" "Fabricant carte mere" "$board_vendor"
    printf "%-22s : %s\n" "Modele carte mere" "$board_name"
    printf "%-22s : %s\n" "Version carte mere" "$board_version"
    printf "%-22s : %s\n" "Fabricant BIOS" "$bios_vendor"
    printf "%-22s : %s\n" "Version BIOS" "$bios_version"
    printf "%-22s : %s\n" "Date BIOS" "$bios_date"
'

add_result "Equipements principaux (Display, Net, Storage, USB, Audio)" '
    if command -v lspci >/dev/null 2>&1; then
        lspci 2>/dev/null | grep -E -v "Host bridge|PCI bridge" || echo "Aucun peripherique filtrant ou lspci silencieux."
    else
        echo "lspci indisponible."
    fi
'

add_result "Ponts et composants systeme (extrait)" '
    if command -v lspci >/dev/null 2>&1; then
        lspci 2>/dev/null | grep -E "Host bridge|PCI bridge" | head -n 40 || echo "Aucun pont PCI detecte."
    else
        echo "lspci indisponible."
    fi
'

add_result "Peripheriques USB presents" '
    if command -v lsusb >/dev/null 2>&1; then
        lsusb 2>/dev/null
    else
        echo "lsusb indisponible."
    fi
'

# -----------------------------------------------------------------------------
# 2. Processeur
# -----------------------------------------------------------------------------
add_section "2 - PROCESSEUR"

add_result "Caracteristiques CPU" '
    if command -v lscpu >/dev/null 2>&1; then
        lscpu 2>/dev/null | grep -E "Model name|Architecture|CPU\(s\):|Thread\(s\) per core|Core\(s\) per socket|Socket\(s\)|CPU max MHz|CPU min MHz|Virtualization|BogoMIPS"
    else
        grep -E "model name|cpu cores|siblings|cpu MHz" /proc/cpuinfo 2>/dev/null | head -n 20
    fi
'

add_result "Charge CPU au moment de la collecte" '
    if [ -f /proc/loadavg ]; then
        read -r l1 l5 l15 _ < /proc/loadavg
        printf "%-25s : %s (1 min), %s (5 min), %s (15 min)\n" "Charge moyenne (load)" "$l1" "$l5" "$l15"
    else
        uptime
    fi
'

add_line "Note : les extensions CPU detaillees (AVX, AVX2, AVX-512, AES-NI, etc.) ne sont pas certifiees par cet inventaire initial."

# -----------------------------------------------------------------------------
# 3. Memoire vive et memoire virtuelle
# -----------------------------------------------------------------------------
add_section "3 - MEMOIRE RAM ET SWAP"

add_result "Memoire reconnue par Linux" '
    if command -v free >/dev/null 2>&1; then
        free -h --wide 2>/dev/null || free -h 2>/dev/null || free -m
    else
        grep -E "MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapTotal|SwapFree" /proc/meminfo 2>/dev/null
    fi
'

add_result "Barrettes memoire (sans numero de serie)" '
    if command -v lshw >/dev/null 2>&1; then
        lshw -C memory -short 2>/dev/null || echo "lshw : acces restreint sans elevation."
    elif [ -r /sys/devices/system/edac/mc ] 2>/dev/null; then
        echo "Controleur memoire EDAC detecte."
    else
        echo "Information detaillee sur les barrettes non accessible sans privileges administrateur."
    fi
'

add_result "Fichiers et partitions de pagination (swap)" '
    if [ -f /proc/swaps ]; then
        cat /proc/swaps
    elif command -v swapon >/dev/null 2>&1; then
        swapon --show 2>/dev/null
    else
        echo "Information swap indisponible."
    fi
'

# -----------------------------------------------------------------------------
# 4. GPU et accelerateurs
# -----------------------------------------------------------------------------
add_section "4 - GPU ET ACCELERATEURS"

add_result "Cartes graphiques reconnues" '
    if command -v lspci >/dev/null 2>&1; then
        lspci -nnk 2>/dev/null | grep -A 3 -Ei "vga|3d|display" || echo "Aucune carte graphique detectee via lspci."
    else
        echo "lspci indisponible."
    fi
'

add_result "Pilotes graphiques charges" '
    if command -v lsmod >/dev/null 2>&1; then
        lsmod 2>/dev/null | grep -E "amdgpu|radeon|nouveau|nvidia|i915" || echo "Aucun module GPU dedie explicite charge dans le noyau."
    else
        echo "lsmod indisponible."
    fi
'

add_result "NVIDIA - informations fournies par le pilote (si disponible)" '
    if command -v nvidia-smi >/dev/null 2>&1; then
        # Ne pas utiliser -L ni de requetes exposant des UUID ou pci.bus_id
        nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader 2>&1
    else
        echo "nvidia-smi absent ou pilote NVIDIA non disponible."
    fi
'

add_line "Note : la valeur VRAM des GPU integres (iGPU AMD/Intel) partagee dynamiquement avec la RAM n'\''est pas consideree comme une mesure garantie."

# -----------------------------------------------------------------------------
# 5. Stockage
# -----------------------------------------------------------------------------
add_section "5 - STOCKAGE"

add_result "Disques physiques et partitions (sans numero de serie ni UUID)" '
    if command -v lsblk >/dev/null 2>&1; then
        lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL,TRAN,ROTA 2>/dev/null
    else
        df -h
    fi
'

add_result "Volumes et occupation" '
    df -h -T -x tmpfs -x devtmpfs -x squashfs 2>/dev/null || df -h
'

add_result "Chiffrement et volumes speciaux (LUKS / dm-crypt)" '
    if command -v lsblk >/dev/null 2>&1; then
        crypt_volumes=$(lsblk -o NAME,TYPE,FSTYPE 2>/dev/null | grep "crypt" || true)
        if [ -n "$crypt_volumes" ]; then
            echo "$crypt_volumes"
        else
            echo "Aucun volume chiffre LUKS/dm-crypt detecte."
        fi
    else
        echo "lsblk indisponible."
    fi
'

add_line "Note : l'\''etat de sante (SMART) detaille necessite smartctl et des privileges administrateur non requis par cet inventaire."

# -----------------------------------------------------------------------------
# 6. Reseau
# -----------------------------------------------------------------------------
add_section "6 - RESEAU"
add_line "Attention : cette section contient des adresses IP locales, DNS, SSID et ports en ecoute."

add_result "Interfaces reseau (adresses MAC exclues)" '
    if command -v ip >/dev/null 2>&1; then
        ip -br link 2>/dev/null | awk "{printf \"%-16s %-12s %s\n\", \$1, \$2, \$3}"
    else
        netstat -i 2>/dev/null || echo "ip/netstat indisponibles."
    fi
'

add_result "Adresses IP locales" '
    if command -v ip >/dev/null 2>&1; then
        ip -br addr 2>/dev/null
    else
        hostname -I 2>/dev/null || echo "ip indisponible."
    fi
'

add_result "Routes IPv4" '
    if command -v ip >/dev/null 2>&1; then
        ip -4 route 2>/dev/null
    else
        route -n 2>/dev/null || echo "ip route indisponible."
    fi
'

add_result "Routes IPv6" '
    if command -v ip >/dev/null 2>&1; then
        ip -6 route 2>/dev/null
    else
        echo "Route IPv6 non disponible."
    fi
'

add_result "Serveurs DNS" '
    if command -v resolvectl >/dev/null 2>&1; then
        resolvectl dns 2>/dev/null || resolvectl status 2>/dev/null | grep "DNS Servers"
    elif [ -f /etc/resolv.conf ]; then
        grep "^nameserver" /etc/resolv.conf 2>/dev/null
    else
        echo "Information DNS indisponible."
    fi
'

add_result "Connexion Wi-Fi (BSSID et adresse physique exclus)" '
    if command -v nmcli >/dev/null 2>&1; then
        nmcli -t -f active,ssid,chan,freq,signal dev wifi 2>/dev/null | grep -E "^oui:|^yes:" || echo "Aucun reseau Wi-Fi connecte detecte par nmcli."
    elif command -v iw >/dev/null 2>&1; then
        iw dev 2>/dev/null | grep -E "Interface|ssid|channel|txpower" || echo "iw : aucune connexion Wi-Fi active rapportee."
    else
        echo "Outils de gestion Wi-Fi (nmcli, iw) indisponibles."
    fi
'

add_result "Sockets TCP en ecoute (adresse, port et processus)" '
    if command -v ss >/dev/null 2>&1; then
        ss -tlnp 2>/dev/null || ss -tln 2>/dev/null
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tlnp 2>/dev/null || netstat -tln 2>/dev/null
    else
        echo "Outils socket (ss, netstat) indisponibles."
    fi
'

add_result "Sockets UDP en ecoute (adresse, port et processus)" '
    if command -v ss >/dev/null 2>&1; then
        ss -ulnp 2>/dev/null || ss -uln 2>/dev/null
    elif command -v netstat >/dev/null 2>&1; then
        netstat -ulnp 2>/dev/null || netstat -uln 2>/dev/null
    else
        echo "Outils socket (ss, netstat) indisponibles."
    fi
'

add_result "Profils et etat du pare-feu (si accessible sans root)" '
    if command -v ufw >/dev/null 2>&1; then
        ufw status 2>/dev/null || echo "ufw : acces restreint sans elevation."
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --state 2>/dev/null || echo "firewalld : acces restreint sans elevation."
    elif command -v iptables >/dev/null 2>&1; then
        iptables -L -n 2>/dev/null | head -n 10 || echo "iptables : acces restreint sans elevation."
    else
        echo "Outil pare-feu standard non detecte ou non accessible sans root."
    fi
'

# -----------------------------------------------------------------------------
# 7. Systeme et services
# -----------------------------------------------------------------------------
add_section "7 - SYSTEME ET SERVICES"

add_result "Services en cours d'execution" '
    if command -v systemctl >/dev/null 2>&1; then
        systemctl list-units --type=service --state=running --no-pager 2>/dev/null | head -n 50
    elif command -v service >/dev/null 2>&1; then
        service --status-all 2>/dev/null | grep "+"
    else
        echo "Gestionnaire de services systemctl/service indisponible."
    fi
'

add_result "Services en echec ou arretes" '
    if command -v systemctl >/dev/null 2>&1; then
        failed=$(systemctl --failed --no-pager 2>/dev/null || true)
        if [ -n "$failed" ]; then
            echo "$failed"
        else
            echo "Aucun service systemd en echec."
        fi
    else
        echo "systemctl indisponible."
    fi
'

add_result "Docker (conteneurs actifs uniquement)" '
    if command -v docker >/dev/null 2>&1; then
        docker --version 2>&1
        docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" 2>&1
    else
        echo "Docker absent du PATH."
    fi
'

add_result "Podman (conteneurs actifs uniquement)" '
    if command -v podman >/dev/null 2>&1; then
        podman --version 2>&1
        podman ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" 2>&1
    else
        echo "Podman absent du PATH."
    fi
'

add_result "Virtualisation detectee" '
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        virt=$(systemd-detect-virt 2>/dev/null || echo "none")
        printf "%-25s : %s\n" "Technologie virtuelle" "$virt"
    fi
    if [ -f /proc/sys/fs/binfmt_misc/WSLInterop ] || grep -qEi "(Microsoft|WSL)" /proc/version 2>/dev/null; then
        printf "%-25s : %s\n" "Environnement WSL" "Oui (Sous-systeme Windows pour Linux)"
    fi
    if command -v virsh >/dev/null 2>&1; then
        virsh list --all 2>/dev/null || echo "virsh : daemon libvirt inactif ou acces limite."
    fi
'

# -----------------------------------------------------------------------------
# 8. Outils et technologies disponibles
# -----------------------------------------------------------------------------
add_section "8 - OUTILS ET TECHNOLOGIES DISPONIBLES"

add_result "Presence des outils (chemins executables non collectes)" '
    tools=(
        "apt" "dnf" "pacman" "zypper" "apk" "flatpak" "snap" "nix"
        "docker" "podman" "vagrant" "vboxmanage" "virsh"
        "tailscale" "wg" "git" "python" "python3" "node" "npm"
        "gcc" "clang" "make" "ssh" "rsync" "borg" "restic" "curl" "wget" "jq"
    )
    printf "%-18s | %s\n" "Outil" "Disponible"
    printf "%s\n" "-------------------+------------"
    for tool in "${tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            printf "%-18s | Oui\n" "$tool"
        else
            printf "%-18s | Non\n" "$tool"
        fi
    done
'

add_result "Versions de quelques outils" '
    for tool in git python3 node docker podman curl; do
        if command -v "$tool" >/dev/null 2>&1; then
            echo "--- $tool ---"
            "$tool" --version 2>&1 | head -n 2
        fi
    done
'

# -----------------------------------------------------------------------------
# 9. Indicateurs generaux
# -----------------------------------------------------------------------------
add_section "9 - INDICATEURS GENERAUX"

add_result "Charge, processeurs logiques et uptime" '
    cpus=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || grep -c "^processor" /proc/cpuinfo 2>/dev/null || echo "Inconnu")
    printf "%-25s : %s\n" "Processeurs logiques" "$cpus"
    if [ -f /proc/loadavg ]; then
        read -r l1 l5 l15 _ < /proc/loadavg
        printf "%-25s : %s (1m), %s (5m), %s (15m)\n" "Charge moyenne (load)" "$l1" "$l5" "$l15"
    fi
    printf "%-25s : %s\n" "Uptime" "$(uptime -p 2>/dev/null || uptime)"
'

add_result "Occupation du volume racine (/)" '
    df -h / 2>/dev/null
'

# -----------------------------------------------------------------------------
# 10. Limites connues de cette collecte
# -----------------------------------------------------------------------------
add_section "10 - LIMITES ET INTERPRETATION"
add_line "- Inventaire en lecture seule : aucune installation ni modification volontaire de configuration."
add_line "- Aucune elevation administrateur n'est demandee (aucun appel a sudo ou su)."
add_line "- Numeros de serie, UUID materiels, cles de chiffrement, mots de passe et adresses MAC/BSSID ne sont pas collectes volontairement."
add_line "- Le rapport contient neanmoins le nom de la machine, des adresses IP locales, DNS, SSID Wi-Fi, ports, services et noms de conteneurs : traiter le fichier comme sensible."
add_line "- Certaines informations materielles (ex: barrettes physiques dmidecode, pare-feu bas niveau) peuvent etre absentes sans elevation."
add_line "- HealthStatus et les informations DMI sont des indications fournies par le noyau / le materiel, pas une certification independante."

add_section "FIN DE L INVENTAIRE"
add_line "Fin de collecte : $(date --iso-8601=seconds 2>/dev/null || date +"%Y-%m-%dT%H:%M:%S%z")"
add_line "Fin du rapport."

# -----------------------------------------------------------------------------
# Creation du fichier sans ecrasement, puis permissions 0600 avant ecriture
# -----------------------------------------------------------------------------
if [ -z "$OUTPUT_PATH" ]; then
    OUTPUT_PATH="$(pwd)/inventaire_initial_linux_$(date +%Y-%m-%d_%H-%M-%S).txt"
fi

PARENT_DIR="$(dirname "$OUTPUT_PATH")"
if [ ! -d "$PARENT_DIR" ]; then
    echo "ERREUR : le dossier parent n'existe pas : $PARENT_DIR" >&2
    exit 1
fi

if [ -e "$OUTPUT_PATH" ]; then
    echo "ERREUR : le fichier existe deja (ecrasement refuse) : $OUTPUT_PATH" >&2
    exit 1
fi

# Creation atomique avec permissions privees (0600)
OLD_UMASK=$(umask)
umask 077

set -o noclobber
if ! : > "$OUTPUT_PATH" 2>/dev/null; then
    umask "$OLD_UMASK"
    echo "ERREUR : impossible de creer le fichier $OUTPUT_PATH (deja existant ou refus d'acces)" >&2
    exit 2
fi
set +o noclobber

chmod 600 "$OUTPUT_PATH" 2>/dev/null || true

# Ecriture de l'integralite du rapport en memoire
printf "%s\n" "${REPORT[@]}" > "$OUTPUT_PATH"
umask "$OLD_UMASK"

echo ""
echo "Rapport cree : $OUTPUT_PATH"
echo "Permissions : acces complet restreint a l'utilisateur courant uniquement (0600)."
echo "Aucune modification systeme volontaire effectuee."
exit 0
