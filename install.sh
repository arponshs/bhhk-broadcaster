#!/data/data/com.termux/files/usr/bin/bash
# BHHK BROADCASTER — Installer

CYAN='\033[0;36m'
PINK='\033[0;35m'
GREEN='\033[0;32m'
WHITE='\033[1;37m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
DIM='\033[2m'
NC='\033[0m'

clear
echo ""
echo -e "${CYAN}  ╔══════════════════════════════════════╗${NC}"
echo -e "${CYAN}  ║${NC}  ${PINK}📢 BHHK BROADCASTER v2.0 📢${NC}       ${CYAN}║${NC}"
echo -e "${CYAN}  ╚══════════════════════════════════════╝${NC}"
echo ""

echo -e "${CYAN}▸${NC} ${WHITE}Installing dependencies...${NC}"
for pkg in bash curl coreutils; do
    if dpkg -l "$pkg" > /dev/null 2>&1; then
        echo -e "  ${DIM}✓ ${pkg}${NC}"
    else
        pkg install -y "$pkg" > /dev/null 2>&1
        echo -e "  ${GREEN}✓${NC} ${WHITE}${pkg}${NC}"
    fi
done
echo ""

echo -e "${CYAN}▸${NC} ${WHITE}Checking Telegram API connectivity...${NC}"
TEST=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "https://api.telegram.org" 2>/dev/null)
if [ "$TEST" = "000" ]; then
    echo -e "  ${YELLOW}⚠ Cannot reach Telegram — fixing DNS...${NC}"
    if [ -n "$PREFIX" ]; then
        echo "nameserver 1.1.1.1" > "$PREFIX/etc/resolv.conf"
        echo "nameserver 8.8.8.8" >> "$PREFIX/etc/resolv.conf"
        echo -e "  ${GREEN}✓ DNS set to Cloudflare + Google${NC}"
    fi
else
    echo -e "  ${GREEN}✓ Telegram API reachable${NC}"
fi
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MAIN="$SCRIPT_DIR/broadcast.sh"

if [ ! -f "$MAIN" ]; then
    echo -e "${RED}✗ broadcast.sh not found${NC}"
    exit 1
fi

chmod +x "$MAIN"

if [ -z "$PREFIX" ]; then
    echo -e "${RED}✗ Termux not detected${NC}"
    exit 1
fi

cat > "$PREFIX/bin/bhhk-broadcast" << EOF
#!/data/data/com.termux/files/usr/bin/bash
exec bash "$MAIN" "\$@"
EOF

chmod +x "$PREFIX/bin/bhhk-broadcast"
echo -e "${GREEN}✓${NC} ${WHITE}Command:${NC} ${PINK}bhhk-broadcast${NC}"
echo ""

echo -e "${CYAN}  ╔══════════════════════════════════════╗${NC}"
echo -e "${CYAN}  ║${NC}  ${GREEN}✓ INSTALLED${NC}                          ${CYAN}║${NC}"
echo -e "${CYAN}  ║${NC}                                      ${CYAN}║${NC}"
echo -e "${CYAN}  ║${NC}  ${WHITE}Run:${NC} ${PINK}bhhk-broadcast${NC}                  ${CYAN}║${NC}"
echo -e "${CYAN}  ╚══════════════════════════════════════╝${NC}"
echo ""

printf "  ${DIM}Launch now? [Y/n]: ${NC}"
read -r ans
case "$ans" in
    n|N) echo -e "\n  ${DIM}Run 'bhhk-broadcast' anytime.${NC}\n";;
    *) bash "$MAIN";;
esac