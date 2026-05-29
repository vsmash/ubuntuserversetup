#!/bin/bash
#
# Interactive apt upgrade with devlog integration
# Allows upgrading all packages or selecting individually
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Error: This script must be run as root${NC}"
    exit 1
fi

echo -e "${BLUE}=== Interactive APT Upgrade ===${NC}\n"

# Update package lists
echo -e "${YELLOW}Updating package lists...${NC}"
apt-get update -qq

# Get list of upgradable packages
upgradable=$(apt list --upgradable 2>/dev/null | grep -v "Listing" | wc -l)

if [ "$upgradable" -eq 0 ]; then
    echo -e "${GREEN}✓ System is up to date. No packages to upgrade.${NC}"
    if command -v devlog >/dev/null 2>&1; then
        devlog -s "System update check: No packages to upgrade"
    fi
    exit 0
fi

echo -e "${YELLOW}Found $upgradable package(s) available for upgrade${NC}\n"

# Show upgradable packages
echo -e "${BLUE}Upgradable packages:${NC}"
apt list --upgradable 2>/dev/null | grep -v "Listing" | while IFS= read -r line; do
    pkg_name=$(echo "$line" | cut -d'/' -f1)
    pkg_version=$(echo "$line" | grep -oP '\[upgradable from: \K[^\]]+')
    pkg_new=$(echo "$line" | grep -oP '^\S+/\S+ \K\S+')
    echo -e "  • ${GREEN}$pkg_name${NC}: $pkg_version → $pkg_new"
done

echo ""

# Check for security updates
security_count=$(apt list --upgradable 2>/dev/null | grep -i security | wc -l)
if [ "$security_count" -gt 0 ]; then
    echo -e "${RED}⚠ $security_count security update(s) available${NC}\n"
fi

# Prompt for action
echo -e "${BLUE}Choose an option:${NC}"
echo "  1) Upgrade all packages"
echo "  2) Select packages individually"
echo "  3) Show detailed package information"
echo "  0) Exit without upgrading"
echo ""
read -p "Enter choice [0-3]: " choice

case $choice in
    1)
        echo -e "\n${YELLOW}Upgrading all packages...${NC}\n"
        
        # Capture upgrade output
        upgrade_output=$(apt-get upgrade -y 2>&1)
        exit_code=$?
        
        if [ $exit_code -eq 0 ]; then
            # Parse output for summary
            upgraded=$(echo "$upgrade_output" | grep -oP '^\d+(?= upgraded)' || echo "0")
            newly_installed=$(echo "$upgrade_output" | grep -oP '^\d+(?= newly installed)' || echo "0")
            
            echo -e "\n${GREEN}✓ Upgrade complete${NC}"
            echo -e "  Upgraded: $upgraded package(s)"
            [ "$newly_installed" != "0" ] && echo -e "  Newly installed: $newly_installed package(s)"
            
            # Log to devlog
            if command -v devlog >/dev/null 2>&1; then
                summary="System update: $upgraded package(s) upgraded"
                [ "$newly_installed" != "0" ] && summary="$summary, $newly_installed newly installed"
                [ "$security_count" -gt 0 ] && summary="$summary ($security_count security updates)"
                devlog -s "$summary"
            fi
        else
            echo -e "\n${RED}✗ Upgrade failed${NC}"
            exit 1
        fi
        ;;
        
    2)
        echo -e "\n${YELLOW}Select packages to upgrade (space-separated numbers, or 'all'):${NC}\n"
        
        # Build array of packages
        mapfile -t packages < <(apt list --upgradable 2>/dev/null | grep -v "Listing" | cut -d'/' -f1)
        
        # Display numbered list
        for i in "${!packages[@]}"; do
            echo "  $((i+1))) ${packages[$i]}"
        done
        
        echo ""
        read -p "Enter package numbers (e.g., 1 3 5) or 'all': " selection
        
        if [ "$selection" = "all" ]; then
            selected_packages=("${packages[@]}")
        else
            selected_packages=()
            for num in $selection; do
                idx=$((num-1))
                if [ $idx -ge 0 ] && [ $idx -lt ${#packages[@]} ]; then
                    selected_packages+=("${packages[$idx]}")
                fi
            done
        fi
        
        if [ ${#selected_packages[@]} -eq 0 ]; then
            echo -e "${RED}No valid packages selected${NC}"
            exit 0
        fi
        
        echo -e "\n${YELLOW}Upgrading ${#selected_packages[@]} package(s)...${NC}\n"
        
        # Upgrade selected packages
        apt-get install --only-upgrade -y "${selected_packages[@]}"
        
        if [ $? -eq 0 ]; then
            echo -e "\n${GREEN}✓ Selected packages upgraded${NC}"
            
            # Log to devlog
            if command -v devlog >/dev/null 2>&1; then
                pkg_list=$(IFS=', '; echo "${selected_packages[*]}")
                devlog -s "System update: Upgraded ${#selected_packages[@]} package(s): $pkg_list"
            fi
        else
            echo -e "\n${RED}✗ Upgrade failed${NC}"
            exit 1
        fi
        ;;
        
    3)
        echo -e "\n${YELLOW}Detailed package information:${NC}\n"
        apt list --upgradable 2>/dev/null | grep -v "Listing"
        echo ""
        
        read -p "Enter package name for details (or press Enter to skip): " pkg_name
        if [ -n "$pkg_name" ]; then
            apt-cache show "$pkg_name" 2>/dev/null || echo -e "${RED}Package not found${NC}"
        fi
        
        # Re-run script to show menu again
        exec "$0"
        ;;
        
    0)
        echo -e "${YELLOW}Exiting without changes${NC}"
        exit 0
        ;;
        
    *)
        echo -e "${RED}Invalid option${NC}"
        exit 1
        ;;
esac

echo ""
