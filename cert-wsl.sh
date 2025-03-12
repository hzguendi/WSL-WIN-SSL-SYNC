#!/bin/bash

# ============================
# WSL Windows Certificate Sync
# ============================

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Variables
POWERSHELL="/mnt/c/WINDOWS/System32/WindowsPowerShell/v1.0/powershell.exe"
WIN_CERT_EXPORT_DIR="C:\\Windows\\Temp\\WSL_Certs"
WSL_CERT_IMPORT_DIR="/usr/local/share/ca-certificates/windows/"
WSL_CERT_EXPORT_DIR=$(wslpath -u "$WIN_CERT_EXPORT_DIR") # Convert Windows path to Linux format
ACTION=""
DOMAIN=""
DEBUG=false
VERBOSE=false
DRY_RUN=false

# ============================
# Helper Functions
# ============================

print_help() {
    echo -e "${BLUE}Usage:${NC} sudo $0 [OPTIONS]"
    echo -e "\nOptions:"
    echo -e "  -u        Update certificates from Windows to WSL"
    echo -e "  -r        Reset default WSL root certificates before importing new ones"
    echo -e "  -t URL    Test a domain against the updated certificates"
    echo -e "  -n        Dry-run (list affected certificates, no changes)"
    echo -e "  -d        Debug mode (detailed logs)"
    echo -e "  -v        Verbose mode (even more detailed logs)"
    echo -e "  -h        Show this help message"

    echo -e "\n${YELLOW}Flag Compatibility:${NC}"
    echo -e "  - Cannot use both ${RED}-u${NC} (update) and ${RED}-t${NC} (test) together."
    echo -e "  - Cannot use both ${RED}-d${NC} (debug) and ${RED}-v${NC} (verbose) together."
    echo -e "  - Cannot use ${RED}-n${NC} (dry-run) with ${RED}-u${NC} (update), as it prevents changes."

    echo -e "\n${BLUE}Usage Examples:${NC}"
    echo -e "  sudo $0 -u"
    echo -e "    → Updates Windows certificates and syncs them to WSL."
    echo -e "  sudo $0 -t example.com"
    echo -e "    → Tests if 'example.com' validates with the updated certificates."
    echo -e "  sudo $0 -n"
    echo -e "    → Lists certificates that would be modified, without making changes."
    echo -e "  sudo $0 -u -d"
    echo -e "    → Updates certificates with debug logs enabled."
}

log() {
    local level=$1
    local message=$2
    case $level in
        INFO) echo -e "${BLUE}[INFO]${NC} $message" ;;
        SUCCESS) echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
        WARN) echo -e "${YELLOW}[WARNING]${NC} $message" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" ;;
    esac
}

# ============================
# Dry-Run: List Certificates Only
# ============================

dry_run_list_certs() {
    log INFO "Performing dry-run: Listing Windows certificates without exporting or modifying anything."

    $POWERSHELL -NoProfile -ExecutionPolicy Bypass -Command "
        Write-Host 'Root Certificates:';
        Get-ChildItem -Path Cert:\LocalMachine\Root | ForEach-Object {
            Write-Host ('CN=' + \$_.Subject + ' | Issuer: ' + \$_.Issuer + ' | Expiry: ' + \$_.NotAfter);
        }
        Write-Host '';
    "

    log SUCCESS "Dry-run completed: No files were modified."
}

# ============================
# Extract Windows Certificates
# ============================

extract_windows_certs() {
    log INFO "Clearing existing Windows certificate export directory..."

    # Run PowerShell to clean and extract new certificates
    $POWERSHELL -NoProfile -ExecutionPolicy Bypass -Command "
        if (Test-Path '$WIN_CERT_EXPORT_DIR') {
            Remove-Item -Path '$WIN_CERT_EXPORT_DIR\\*' -Force -ErrorAction SilentlyContinue;
            Write-Host 'Cleared previous certificate files from $WIN_CERT_EXPORT_DIR';
        }

        if (!(Test-Path '$WIN_CERT_EXPORT_DIR')) {
            New-Item -ItemType Directory -Path '$WIN_CERT_EXPORT_DIR' -Force | Out-Null;
        }

        if ([bool]([System.Convert]::ToBoolean('$DEBUG') -or [System.Convert]::ToBoolean('$VERBOSE'))) {
            Write-Host 'Exporting Root certificates...';
        }
        Get-ChildItem -Path Cert:\LocalMachine\Root | ForEach-Object {
            \$certPath = '$WIN_CERT_EXPORT_DIR\\' + \$_.Thumbprint + '.crt';
            Export-Certificate -Cert \$_.PSPath -FilePath \$certPath -Type CERT -ErrorAction Continue;

            if (Test-Path \$certPath) {
                if ([bool]([System.Convert]::ToBoolean('$DEBUG') -or [System.Convert]::ToBoolean('$VERBOSE'))) {
                    Write-Host ('Exported: CN=' + \$_.Subject + ' | Issuer: ' + \$_.Issuer + ' | Expiry: ' + \$_.NotAfter);
                }
            } else {
                if ([bool]([System.Convert]::ToBoolean('$DEBUG') -or [System.Convert]::ToBoolean('$VERBOSE'))) {
                    Write-Host 'Failed to export:' \$certPath;
                }
            }
        }"

    # Verify Windows certificate export
    if [ ! -d "$WSL_CERT_EXPORT_DIR" ]; then
        log ERROR "Windows certificate export directory does not exist. Extraction may have failed."
        exit 1
    fi
}

# ============================
# Import Certificates into WSL
# ============================

import_certs_to_wsl() {
    log INFO "Syncing certificates from Windows to WSL..."

    sudo mkdir -p "$WSL_CERT_IMPORT_DIR"

    # Ensure exported certificates are in PEM format before copying
    for cert in "$WSL_CERT_EXPORT_DIR"/*.{crt,cer}; do
        # Skip if the glob didn't match any files
        [ -e "$cert" ] || continue

        # Ensure it's a file and not a directory
        [ -f "$cert" ] || continue

        if openssl x509 -in "$cert" -noout -text > /dev/null 2>&1; then
            log SUCCESS "Certificate is already in PEM format: $(basename "$cert")"
        else
            log INFO "Converting $(basename "$cert") from DER to PEM..."
            openssl x509 -inform DER -in "$cert" -out "$cert.pem"
            mv "$cert.pem" "$cert"  # Replace original with PEM version
        fi
    done

    dos2unix "$WSL_CERT_EXPORT_DIR"/*.crt 2>/dev/null || sed -i 's/\r$//' "$WSL_CERT_EXPORT_DIR"/*.crt

    sudo cp "$WSL_CERT_EXPORT_DIR"/*.crt "$WSL_CERT_IMPORT_DIR" 2>/dev/null

    CERT_COUNT=$(ls -1 "$WSL_CERT_IMPORT_DIR" | wc -l)
    log SUCCESS "Copied: $CERT_COUNT certificates."

    if [ "$CERT_COUNT" -gt 0 ]; then
        sudo update-ca-certificates --fresh
        log SUCCESS "Updated WSL certificate store."
    else
        log WARN "No new certificates found."
    fi
}

# ============================
# Test a Domain with cURL
# ============================

test_certificate() {
    # Remove "https://" or "http://" from the domain if present
    DOMAIN=${DOMAIN#https://}
    DOMAIN=${DOMAIN#http://}

    # Validate domain format
    if [[ ! $DOMAIN =~ ^([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})$ ]]; then
        log ERROR "Invalid domain format: $DOMAIN"
        exit 1
    fi

    log INFO "Testing SSL connection to https://$DOMAIN..."

    if [ "$VERBOSE" = true ]; then
        curl -v --cacert /etc/ssl/certs/ca-certificates.crt "https://$DOMAIN" && log SUCCESS "Certificate is working!" || log ERROR "Certificate verification failed!"
    elif [ "$DEBUG" = true ]; then
        curl --cacert /etc/ssl/certs/ca-certificates.crt "https://$DOMAIN" -s -o /dev/null -w "%{http_code}\n" && log SUCCESS "Certificate is working!" || log ERROR "Certificate verification failed!"
    else
        curl --cacert /etc/ssl/certs/ca-certificates.crt "https://$DOMAIN" -s -o /dev/null && log SUCCESS "Certificate is working!" || log ERROR "Certificate verification failed!"
    fi
}


# ============================
# Reset default CA certificates in WSL
# ============================

reset_wsl_certs() {
    log INFO "Resetting WSL root certificates..."
    sudo rm -rf /usr/local/share/ca-certificates/windows
    if [ $? -ne 0 ]; then
        log ERROR "Failed to remove existing certificates."
        exit 1
    fi
    sudo apt install --reinstall ca-certificates
    if [ $? -ne 0 ]; then
        log ERROR "Failed to reinstall ca-certificates."
        exit 1
    fi
    sudo update-ca-certificates --fresh
    if [ $? -ne 0 ]; then
        log ERROR "Failed to update CA certificates."
        exit 1
    fi
    log INFO "WSL root certificates reset successfully."
}


# ============================
# Argument Parsing
# ============================

while getopts "ut:n:dvhr" opt; do
    case "$opt" in
        u) ACTION="update" ;;
        t) ACTION="test"; DOMAIN="$OPTARG" ;;
        n) ACTION="dry-run" ;;
        r) RESET_CERTS=true ;;
        d) DEBUG=true ;;
        v) VERBOSE=true ;;
        h) print_help; exit 0 ;;
        *) log ERROR "Invalid option"; print_help; exit 1 ;;
    esac
done

# ============================
# Main Execution Logic
# ============================

if [ -z "$ACTION" ]; then
    log ERROR "No action specified."
    print_help
    exit 1
fi

if [ "$ACTION" = "update" ]; then
    if [ "$RESET_CERTS" = true ]; then
        reset_wsl_certs
    fi
    extract_windows_certs
    import_certs_to_wsl
elif [ "$ACTION" = "test" ]; then
    if [ -z "$DOMAIN" ]; then
        log ERROR "You must specify a domain with -t."
        exit 1
    fi
    test_certificate
elif [ "$ACTION" = "dry-run" ]; then
    dry_run_list_certs
elif [ "$RESET_CERTS" = true ]; then
    reset_wsl_certs
else
    log ERROR "Invalid action specified."
    print_help
    exit 1
fi