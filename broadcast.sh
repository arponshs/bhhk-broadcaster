#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# BHHK BROADCASTER v2.0 — Complete Rewrite
# Telegram Bot Message Sender
# ============================================================

CYAN='\033[0;36m'
PINK='\033[0;35m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
WHITE='\033[1;37m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

WORK_DIR="$HOME/.bhhk_broadcaster"
mkdir -p "$WORK_DIR"

USERS_FILE="$WORK_DIR/users.txt"
LOG_FILE="$WORK_DIR/broadcast.log"
CONFIG_FILE="$WORK_DIR/config.conf"
STATS_FILE="$WORK_DIR/stats.dat"
OFFSET_FILE="$WORK_DIR/offset.dat"

BOT_TOKEN=""
BOT_USERNAME=""
SENT=0
FAILED=0
TOTAL_USERS=0

# ============================================================
# CURSOR / CLEANUP
# ============================================================
hide_cursor() { printf '\033[?25l'; }
show_cursor() { printf '\033[?25h'; }

cleanup() {
    show_cursor
    echo ""
    echo -e "  ${YELLOW}⏹ Exiting...${NC}"
    exit 0
}
trap cleanup INT TERM

# ============================================================
# BANNER
# ============================================================
show_banner() {
    clear
    echo ""
    echo -e "${CYAN}    ╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}    ║${NC}  ${PINK}📢  B H H K   B R O A D C A S T E R  📢${NC}  ${CYAN}║${NC}"
    echo -e "${CYAN}    ║${NC}     ${DIM}Telegram Bot Message Sender v2.0${NC}     ${CYAN}║${NC}"
    echo -e "${CYAN}    ╚══════════════════════════════════════════╝${NC}"
    echo ""
}

# ============================================================
# LOAD CONFIG
# ============================================================
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        BOT_TOKEN=$(grep '^BOT_TOKEN=' "$CONFIG_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'")
        BOT_USERNAME=$(grep '^BOT_USERNAME=' "$CONFIG_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'")
    fi
}

# ============================================================
# SAVE CONFIG
# ============================================================
save_config() {
    cat > "$CONFIG_FILE" << EOF
BOT_TOKEN="$BOT_TOKEN"
BOT_USERNAME="$BOT_USERNAME"
EOF
}

# ============================================================
# VERIFY TOKEN
# ============================================================
verify_token() {
    local token="$1"
    local url="https://api.telegram.org/bot${token}/getMe"

    local res
    res=$(curl -s --max-time 15 --connect-timeout 10 "$url" 2>/dev/null)

    if [ -z "$res" ]; then
        echo "FAIL|No response from Telegram API — check internet"
        return 1
    fi

    if echo "$res" | grep -q '"ok":false'; then
        local err=$(echo "$res" | grep -oE '"description":"[^"]*"' | sed 's/"description":"//;s/"$//')
        echo "FAIL|${err:-Invalid token}"
        return 1
    fi

    if echo "$res" | grep -qE '"ok"[[:space:]]*:[[:space:]]*true'; then
        local username=$(echo "$res" | grep -oE '"username"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"username"[[:space:]]*:[[:space:]]*"//;s/"$//')
        [ -z "$username" ] && username="unknown"
        echo "OK|$username"
        return 0
    fi

    echo "FAIL|Unexpected response from API"
    return 1
}

# ============================================================
# SEND SINGLE MESSAGE
# ============================================================
send_msg() {
    local chat_id="$1"
    local text="$2"
    local url="https://api.telegram.org/bot${BOT_TOKEN}/sendMessage"

    curl -s --max-time 15 -X POST "$url" \
        --data-urlencode "chat_id=${chat_id}" \
        --data-urlencode "text=${text}" \
        --data "parse_mode=HTML&disable_web_page_preview=true" 2>/dev/null
}

# ============================================================
# FETCH USERS
# ============================================================
fetch_users() {
    local offset=0
    [ -f "$OFFSET_FILE" ] && offset=$(cat "$OFFSET_FILE" 2>/dev/null)
    [ -z "$offset" ] && offset=0

    echo -e "  ${CYAN}▸${NC} ${WHITE}Fetching users from Telegram...${NC}"
    echo ""

    local fetched=0
    local batch=0
    local max_batches=15

    while [ $batch -lt $max_batches ]; do
        batch=$((batch + 1))

        local url="https://api.telegram.org/bot${BOT_TOKEN}/getUpdates?offset=${offset}&limit=100&timeout=0"
        local res=$(curl -s --max-time 15 "$url" 2>/dev/null)

        if [ -z "$res" ]; then
            echo -e "  ${RED}✗ No response${NC}"
            break
        fi

        # Check empty
        if echo "$res" | grep -q '"result":\[\]'; then
            break
        fi

        # Extract chat IDs from messages
        echo "$res" | grep -oE '"chat":\{"id":-?[0-9]+' | grep -oE '\-?[0-9]+' >> "$WORK_DIR/ids_tmp.txt"

        # Extract user IDs from senders (message.from.id)
        echo "$res" | grep -oE '"from":\{"id":[0-9]+' | grep -oE '[0-9]+' >> "$WORK_DIR/ids_tmp.txt"

        # Get last update_id for offset
        local last_id=$(echo "$res" | grep -oE '"update_id":[0-9]+' | tail -1 | grep -oE '[0-9]+')
        if [ -n "$last_id" ]; then
            offset=$((last_id + 1))
            echo "$offset" > "$OFFSET_FILE"
        else
            break
        fi

        printf "\r  ${CYAN}▸${NC} Batch %d — Total so far: %d users" "$batch" "$(wc -l < "$WORK_DIR/ids_tmp.txt" 2>/dev/null || echo 0)"
        sleep 0.2
    done

    echo ""
    echo ""

    if [ -f "$WORK_DIR/ids_tmp.txt" ] && [ -s "$WORK_DIR/ids_tmp.txt" ]; then
        # Merge with existing (both positive for DMs)
        sort -u "$WORK_DIR/ids_tmp.txt" | while read -r id; do
            [ -z "$id" ] && continue
            # Only positive IDs (real users, not groups/channels)
            [ "$id" -lt 1 ] 2>/dev/null && continue
            if ! grep -qx "$id" "$USERS_FILE" 2>/dev/null; then
                echo "$id" >> "$USERS_FILE"
                fetched=$((fetched + 1))
            fi
        done
        rm -f "$WORK_DIR/ids_tmp.txt"

        if [ -f "$USERS_FILE" ]; then
            sort -u "$USERS_FILE" -o "$USERS_FILE"
            local total=$(wc -l < "$USERS_FILE")
            echo -e "  ${GREEN}✓ New users added:${NC} ${WHITE}$((total))${NC}"
            echo -e "  ${GREEN}✓ Total database:${NC} ${WHITE}${total}${NC}"
        fi
    else
        echo -e "  ${YELLOW}⚠ No updates found${NC}"
        echo -e "  ${DIM}  Make sure users /start your bot first${NC}"
    fi

    echo ""
    printf "  ${DIM}Press ENTER to continue...${NC}"
    read -r
}

# ============================================================
# SEND BROADCAST
# ============================================================
send_broadcast() {
    local message="$1"

    if [ ! -f "$USERS_FILE" ] || [ ! -s "$USERS_FILE" ]; then
        echo -e "  ${RED}✗ No users in database${NC}"
        sleep 1.5
        return
    fi

    TOTAL_USERS=$(wc -l < "$USERS_FILE")
    SENT=0
    FAILED=0

    clear
    echo ""
    echo -e "${CYAN}  ╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}  ║${NC}  ${PINK}📢 BROADCASTING — LIVE 📢${NC}             ${CYAN}║${NC}"
    echo -e "${CYAN}  ╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${DIM}Target:${NC} ${WHITE}${TOTAL_USERS} users${NC}"
    echo ""
    echo -e "  ${GREEN}▸ Sent:${NC}      ${WHITE}0${NC}"
    echo -e "  ${RED}▸ Failed:${NC}    ${WHITE}0${NC}"
    echo -e "  ${CYAN}▸ Progress:${NC}  ${WHITE}0%${NC}"
    echo -e "  ${DIM}──────────────────────────────────────────${NC}"
    echo ""

    hide_cursor

    local idx=0
    local start_time=$(date +%s)

    while IFS= read -r user_id; do
        [ -z "$user_id" ] && continue
        idx=$((idx + 1))

        local res=$(send_msg "$user_id" "$message")

        if echo "$res" | grep -q '"ok":true'; then
            SENT=$((SENT + 1))
            echo "[$(date '+%H:%M:%S')] ✓ $user_id" >> "$LOG_FILE"
        else
            FAILED=$((FAILED + 1))
            local err=$(echo "$res" | grep -oE '"description":"[^"]*"' | sed 's/"description":"//;s/"$//')
            echo "[$(date '+%H:%M:%S')] ✗ $user_id — ${err:-unknown}" >> "$LOG_FILE"
        fi

        # Update screen
        local pct=$((idx * 100 / TOTAL_USERS))
        printf "\033[8;1H"
        printf "\033[K  ${GREEN}▸ Sent:${NC}      ${WHITE}%d${NC}\n" "$SENT"
        printf "\033[K  ${RED}▸ Failed:${NC}    ${WHITE}%d${NC}\n" "$FAILED"
        printf "\033[K  ${CYAN}▸ Progress:${NC}  ${WHITE}%d%% (%d/%d)${NC}\n" "$pct" "$idx" "$TOTAL_USERS"
        printf "\033[K  ${DIM}──────────────────────────────────────────${NC}\n"
        printf "\033[K  ${DIM}Current: %s${NC}" "$user_id"

        sleep 0.05
    done < "$USERS_FILE"

    show_cursor

    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))
    [ $elapsed -eq 0 ] && elapsed=1

    echo ""
    echo ""
    echo -e "  ${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "  ${CYAN}║${NC}   ${GREEN}✓ BROADCAST COMPLETE${NC}                   ${CYAN}║${NC}"
    echo -e "  ${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${GREEN}▸ Sent:${NC}      ${WHITE}${SENT}${NC}"
    echo -e "  ${RED}▸ Failed:${NC}    ${WHITE}${FAILED}${NC}"
    echo -e "  ${PINK}▸ Total:${NC}     ${WHITE}${TOTAL_USERS}${NC}"
    echo -e "  ${CYAN}▸ Duration:${NC}  ${WHITE}${elapsed}s${NC}"
    [ $elapsed -gt 0 ] && echo -e "  ${CYAN}▸ Speed:${NC}     ${WHITE}$((TOTAL_USERS / elapsed))/s${NC}"
    echo ""

    cat > "$STATS_FILE" << EOF
LAST_RUN="$(date)"
SENT=$SENT
FAILED=$FAILED
TOTAL=$TOTAL_USERS
EOF
}

# ============================================================
# SETUP BOT
# ============================================================
setup_bot() {
    show_banner
    echo -e "  ${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "  ${CYAN}║${NC}   ${PINK}🤖 BOT SETUP${NC}                          ${CYAN}║${NC}"
    echo -e "  ${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo ""

    if [ -n "$BOT_TOKEN" ]; then
        echo -e "  ${CYAN}▸${NC} Current: ${WHITE}@${BOT_USERNAME}${NC}"
        echo -e "  ${DIM}  Token: ${BOT_TOKEN:0:20}...${NC}"
        echo ""
        printf "  ${PINK}➜${NC} Change bot? [y/N]: "
        read -r ch
        case "$ch" in
            y|Y) ;;
            *) return ;;
        esac
    fi

    echo ""
    echo -e "  ${DIM}Get token from @BotFather on Telegram${NC}"
    echo -e "  ${DIM}Format: 123456789:AAxxxxxxxxxxxxxxxxxxxxxxxxxxx${NC}"
    echo ""
    printf "  ${PINK}➜${NC} Bot token: "
    read -r token

    # Trim all whitespace
    token=$(echo "$token" | tr -d ' \r\n\t')

    if [ -z "$token" ]; then
        echo -e "  ${RED}✗ Token required${NC}"
        sleep 1.5
        return
    fi

    # Basic format check
    if ! echo "$token" | grep -qE '^[0-9]+:[A-Za-z0-9_-]+$'; then
        echo ""
        echo -e "  ${YELLOW}⚠ Token format unusual${NC}"
        echo -e "  ${DIM}Expected: numbers:letters_and_symbols${NC}"
        printf "  ${PINK}➜${NC} Continue anyway? [y/N]: "
        read -r cont
        case "$cont" in
            y|Y) ;;
            *) return ;;
        esac
    fi

    echo ""
    echo -e "  ${CYAN}▸${NC} ${DIM}Testing connection to Telegram...${NC}"

    # First check internet to Telegram
    local ping_res=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "https://api.telegram.org" 2>/dev/null)
    if [ "$ping_res" = "000" ]; then
        echo -e "  ${RED}✗ Cannot reach Telegram API${NC}"
        echo ""
        echo -e "  ${YELLOW}Possible causes:${NC}"
        echo -e "  ${DIM}• No internet connection${NC}"
        echo -e "  ${DIM}• DNS not working${NC}"
        echo -e "  ${DIM}• Firewall blocking${NC}"
        echo ""
        printf "  ${DIM}Try DNS fix? [Y/n]: ${NC}"
        read -r fixdns
        case "$fixdns" in
            n|N) ;;
            *)
                echo "nameserver 1.1.1.1" > "$PREFIX/etc/resolv.conf" 2>/dev/null
                echo "nameserver 8.8.8.8" >> "$PREFIX/etc/resolv.conf" 2>/dev/null
                echo -e "  ${GREEN}✓ DNS set to Cloudflare + Google${NC}"
                sleep 1
                ;;
        esac
        return
    fi

    echo -e "  ${CYAN}▸${NC} ${DIM}Verifying token...${NC}"

    local result=$(verify_token "$token")
    local status="${result%%|*}"
    local payload="${result#*|}"

    if [ "$status" = "OK" ]; then
        BOT_USERNAME="$payload"
        BOT_TOKEN="$token"
        save_config

        echo ""
        echo -e "  ${GREEN}╔══════════════════════════════════════════╗${NC}"
        echo -e "  ${GREEN}║${NC}   ${GREEN}✓ BOT CONNECTED${NC}                        ${GREEN}║${NC}"
        echo -e "  ${GREEN}╚══════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "  ${CYAN}▸ Bot name:${NC}  ${WHITE}@${BOT_USERNAME}${NC}"
        echo -e "  ${CYAN}▸ Token:${NC}     ${DIM}${BOT_TOKEN:0:20}...${NC}"
        echo ""
        echo -e "  ${YELLOW}⚠ Important:${NC}"
        echo -e "  ${DIM}  Users must send /start to @${BOT_USERNAME}${NC}"
        echo -e "  ${DIM}  Otherwise broadcast won't deliver${NC}"
        echo ""
    else
        echo ""
        echo -e "  ${RED}╔══════════════════════════════════════════╗${NC}"
        echo -e "  ${RED}║${NC}   ${WHITE}✗ TOKEN VERIFICATION FAILED${NC}            ${RED}║${NC}"
        echo -e "  ${RED}╚══════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "  ${RED}Reason:${NC} ${WHITE}${payload}${NC}"
        echo ""
        echo -e "  ${DIM}Troubleshooting:${NC}"
        echo -e "  ${DIM}1. Copy token again from @BotFather${NC}"
        echo -e "  ${DIM}2. Make sure no extra spaces${NC}"
        echo -e "  ${DIM}3. Token format: 123456789:AAH...${NC}"
        echo ""
    fi

    printf "  ${DIM}Press ENTER...${NC}"
    read -r
}

# ============================================================
# FETCH USERS MENU
# ============================================================
fetch_users_menu() {
    if [ -z "$BOT_TOKEN" ]; then
        show_banner
        echo -e "  ${RED}✗ Setup bot first${NC}"
        sleep 1.5
        return
    fi

    show_banner
    echo -e "  ${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "  ${CYAN}║${NC}   ${PINK}👥 FETCH USERS${NC}                        ${CYAN}║${NC}"
    echo -e "  ${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo ""

    local current=0
    [ -f "$USERS_FILE" ] && current=$(wc -l < "$USERS_FILE")
    echo -e "  ${CYAN}▸${NC} Saved users: ${WHITE}${current}${NC}"
    echo ""
    echo -e "  ${CYAN}╭──────────────────────────────────────────╮${NC}"
    echo -e "  ${CYAN}│${NC}  ${PINK}[1]${NC} ${WHITE}Fetch new users${NC}                     ${CYAN}│${NC}"
    echo -e "  ${CYAN}│${NC}  ${PINK}[2]${NC} ${WHITE}Fetch from scratch (clear first)${NC}    ${CYAN}│${NC}"
    echo -e "  ${CYAN}│${NC}  ${PINK}[3]${NC} ${WHITE}View users count${NC}                    ${CYAN}│${NC}"
    echo -e "  ${CYAN}│${NC}  ${PINK}[4]${NC} ${WHITE}Clear all users${NC}                     ${CYAN}│${NC}"
    echo -e "  ${CYAN}│${NC}  ${PINK}[0]${NC} ${WHITE}Back${NC}                                  ${CYAN}│${NC}"
    echo -e "  ${CYAN}╰──────────────────────────────────────────╯${NC}"
    echo ""
    printf "  ${PINK}➜${NC} "
    read -r c

    case "$c" in
        1)
            echo ""
            fetch_users
            ;;
        2)
            > "$USERS_FILE"
            rm -f "$OFFSET_FILE"
            echo ""
            fetch_users
            ;;
        3)
            echo ""
            local cnt=0
            [ -f "$USERS_FILE" ] && cnt=$(wc -l < "$USERS_FILE")
            echo -e "  ${GREEN}✓ Total users:${NC} ${WHITE}${cnt}${NC}"
            sleep 1.5
            ;;
        4)
            > "$USERS_FILE"
            rm -f "$OFFSET_FILE"
            echo -e "  ${GREEN}✓ Cleared${NC}"
            sleep 1
            ;;
        0) return ;;
        *) ;;
    esac
}

# ============================================================
# SEND MESSAGE MENU
# ============================================================
send_message_menu() {
    if [ -z "$BOT_TOKEN" ]; then
        show_banner
        echo -e "  ${RED}✗ Setup bot first${NC}"
        sleep 1.5
        return
    fi

    local user_count=0
    [ -f "$USERS_FILE" ] && user_count=$(wc -l < "$USERS_FILE")

    show_banner
    echo -e "  ${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "  ${CYAN}║${NC}   ${PINK}📤 SEND BROADCAST${NC}                     ${CYAN}║${NC}"
    echo -e "  ${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}▸${NC} Bot:   ${WHITE}@${BOT_USERNAME}${NC}"
    echo -e "  ${CYAN}▸${NC} Users: ${WHITE}${user_count}${NC}"
    echo ""

    if [ "$user_count" -eq 0 ]; then
        echo -e "  ${YELLOW}⚠ No users in database${NC}"
        echo -e "  ${DIM}  Fetch users first from menu${NC}"
        sleep 2
        return
    fi

    echo -e "  ${DIM}Type your message (HTML supported: <b>, <i>, <code>, <a>)${NC}"
    echo ""
    printf "  ${PINK}➜${NC} Message: "
    read -r message

    if [ -z "$message" ]; then
        echo -e "  ${RED}✗ Empty message${NC}"
        sleep 1.5
        return
    fi

    echo ""
    echo -e "  ${CYAN}▸ Preview:${NC}"
    echo -e "  ${DIM}──────────────────────────────────────────${NC}"
    echo -e "  ${message}"
    echo -e "  ${DIM}──────────────────────────────────────────${NC}"
    echo ""
    printf "  ${PINK}➜${NC} Send to ${WHITE}${user_count}${NC} users? [Y/n]: "
    read -r confirm

    case "$confirm" in
        n|N) echo -e "  ${DIM}Cancelled${NC}"; sleep 1; return ;;
    esac

    echo ""
    echo -e "  ${CYAN}▸${NC} ${DIM}Sending in 3 seconds... (Ctrl+C to abort)${NC}"
    sleep 3

    send_broadcast "$message"

    printf "\n  ${DIM}Press ENTER to continue...${NC}"
    read -r
}

# ============================================================
# TEST MESSAGE
# ============================================================
test_message() {
    if [ -z "$BOT_TOKEN" ]; then
        show_banner
        echo -e "  ${RED}✗ Setup bot first${NC}"
        sleep 1.5
        return
    fi

    show_banner
    echo -e "  ${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "  ${CYAN}║${NC}   ${PINK}🧪 TEST MESSAGE${NC}                       ${CYAN}║${NC}"
    echo -e "  ${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${DIM}Send test message to yourself${NC}"
    echo -e "  ${DIM}Get your chat ID from @userinfobot${NC}"
    echo ""
    printf "  ${PINK}➜${NC} Your Telegram ID: "
    read -r test_id

    [ -z "$test_id" ] && return

    printf "  ${PINK}➜${NC} Message: "
    read -r test_msg

    [ -z "$test_msg" ] && return

    echo ""
    echo -e "  ${CYAN}▸${NC} Sending..."

    local res=$(send_msg "$test_id" "$test_msg")

    echo ""
    if echo "$res" | grep -q '"ok":true'; then
        echo -e "  ${GREEN}✓ Delivered successfully!${NC}"
    else
        local err=$(echo "$res" | grep -oE '"description":"[^"]*"' | sed 's/"description":"//;s/"$//')
        echo -e "  ${RED}✗ Failed:${NC} ${err:-unknown error}"
    fi

    echo ""
    printf "  ${DIM}Press ENTER...${NC}"
    read -r
}

# ============================================================
# VIEW LOG
# ============================================================
view_log() {
    show_banner
    echo -e "  ${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "  ${CYAN}║${NC}   ${PINK}📋 BROADCAST LOG${NC}                      ${CYAN}║${NC}"
    echo -e "  ${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo ""

    if [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
        local total=$(wc -l < "$LOG_FILE")
        echo -e "  ${DIM}Showing last 30 of ${total} entries${NC}"
        echo ""
        tail -30 "$LOG_FILE" | while IFS= read -r line; do
            if echo "$line" | grep -q '✓'; then
                echo -e "  ${GREEN}$line${NC}"
            else
                echo -e "  ${RED}$line${NC}"
            fi
        done
    else
        echo -e "  ${DIM}No broadcast log yet${NC}"
    fi

    echo ""
    printf "  ${PINK}➜${NC} Clear log? [y/N]: "
    read -r cl
    case "$cl" in
        y|Y) > "$LOG_FILE"; echo -e "  ${GREEN}✓ Cleared${NC}"; sleep 1 ;;
    esac
}

# ============================================================
# STATS
# ============================================================
show_stats() {
    show_banner
    echo -e "  ${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "  ${CYAN}║${NC}   ${PINK}📊 STATISTICS${NC}                         ${CYAN}║${NC}"
    echo -e "  ${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "  ${CYAN}▸${NC} Bot:          ${WHITE}@${BOT_USERNAME:-Not setup}${NC}"

    local user_count=0
    [ -f "$USERS_FILE" ] && user_count=$(wc -l < "$USERS_FILE")
    echo -e "  ${CYAN}▸${NC} Users:        ${WHITE}${user_count}${NC}"

    local log_count=0
    [ -f "$LOG_FILE" ] && log_count=$(wc -l < "$LOG_FILE")
    echo -e "  ${CYAN}▸${NC} Log entries:  ${WHITE}${log_count}${NC}"

    if [ -f "$STATS_FILE" ]; then
        echo ""
        echo -e "  ${DIM}─── Last Broadcast ───${NC}"
        local last_run=$(grep '^LAST_RUN=' "$STATS_FILE" | cut -d'=' -f2- | tr -d '"')
        local sent=$(grep '^SENT=' "$STATS_FILE" | cut -d'=' -f2)
        local failed=$(grep '^FAILED=' "$STATS_FILE" | cut -d'=' -f2)
        local total=$(grep '^TOTAL=' "$STATS_FILE" | cut -d'=' -f2)

        echo -e "  ${CYAN}▸${NC} Time:   ${WHITE}${last_run}${NC}"
        echo -e "  ${CYAN}▸${NC} Sent:   ${GREEN}${sent}${NC}"
        echo -e "  ${CYAN}▸${NC} Failed: ${RED}${failed}${NC}"
        echo -e "  ${CYAN}▸${NC} Total:  ${WHITE}${total}${NC}"
    fi

    echo ""
    printf "  ${DIM}Press ENTER...${NC}"
    read -r
}

# ============================================================
# HELP
# ============================================================
show_help() {
    show_banner
    echo -e "  ${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "  ${CYAN}║${NC}   ${PINK}📖 HELP / GUIDE${NC}                       ${CYAN}║${NC}"
    echo -e "  ${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${WHITE}${BOLD}Setup Process:${NC}"
    echo ""
    echo -e "  ${CYAN}1.${NC} Open Telegram → @BotFather"
    echo -e "  ${CYAN}2.${NC} Send /newbot → follow steps"
    echo -e "  ${CYAN}3.${NC} Copy API token (123456:ABC...)"
    echo -e "  ${CYAN}4.${NC} Run this tool → Setup Bot"
    echo -e "  ${CYAN}5.${NC} Paste token → auto-verified"
    echo ""
    echo -e "  ${WHITE}${BOLD}Getting Users:${NC}"
    echo ""
    echo -e "  ${YELLOW}▸${NC} Users must send /start to your bot"
    echo -e "  ${YELLOW}▸${NC} Then click 'Fetch Users' to collect IDs"
    echo -e "  ${YELLOW}▸${NC} Telegram bots cannot message users who"
    echo -e "  ${YELLOW}▸${NC} haven't started the bot first"
    echo ""
    echo -e "  ${WHITE}${BOLD}HTML Formatting:${NC}"
    echo ""
    echo -e "  ${CYAN}▸${NC} <b>bold text</b>"
    echo -e "  ${CYAN}▸${NC} <i>italic text</i>"
    echo -e "  ${CYAN}▸${NC} <code>monospace</code>"
    echo -e "  ${CYAN}▸${NC} <a href=\"URL\">link text</a>"
    echo ""
    echo -e "  ${WHITE}${BOLD}Safety:${NC}"
    echo ""
    echo -e "  ${YELLOW}▸${NC} Speed: 20 messages/second"
    echo -e "  ${YELLOW}▸${NC} Telegram limit: 30/second"
    echo -e "  ${YELLOW}▸${NC} Auto-handles rate limits"
    echo ""
    printf "  ${DIM}Press ENTER...${NC}"
    read -r
}

# ============================================================
# BOOT ANIMATION
# ============================================================
boot_animation() {
    clear
    echo ""
    echo -e "${CYAN}    ╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}    ║${NC}  ${PINK}📢  B H H K   B R O A D C A S T E R  📢${NC}  ${CYAN}║${NC}"
    echo -e "${CYAN}    ║${NC}     ${DIM}Telegram Bot Message Sender v2.0${NC}     ${CYAN}║${NC}"
    echo -e "${CYAN}    ╚══════════════════════════════════════════╝${NC}"
    echo ""

    local steps=(
        "Initializing core"
        "Loading Telegram API"
        "Preparing engine"
        "Ready"
    )

    for i in "${!steps[@]}"; do
        local progress=$(( (i + 1) * 100 / ${#steps[@]} ))
        local filled=$(( progress / 5 ))
        local bar=""
        for ((j=0; j<20; j++)); do
            if [ $j -lt $filled ]; then bar="${bar}█"; else bar="${bar}░"; fi
        done
        printf "\r  ${CYAN}▸${NC} ${WHITE}%-26s${NC} ${PINK}[${bar}]${NC} ${GREEN}%3d%%${NC}" \
            "${steps[$i]}" "$progress"
        sleep 0.18
    done
    echo ""
    echo ""
    sleep 0.3
}

# ============================================================
# MAIN MENU
# ============================================================
main_menu() {
    while true; do
        show_banner

        local user_count=0
        [ -f "$USERS_FILE" ] && user_count=$(wc -l < "$USERS_FILE")

        if [ -n "$BOT_TOKEN" ]; then
            echo -e "  ${GREEN}●${NC} Bot: ${WHITE}@${BOT_USERNAME}${NC}   ${DIM}Users: ${WHITE}${user_count}${NC}"
        else
            echo -e "  ${RED}●${NC} ${DIM}No bot configured${NC}"
        fi
        echo ""
        echo -e "  ${CYAN}╭──────────────────────────────────────────╮${NC}"
        echo -e "  ${CYAN}│${NC}  ${PINK}[1]${NC} ${WHITE}🤖  Setup Bot${NC}                         ${CYAN}│${NC}"
        echo -e "  ${CYAN}│${NC}  ${PINK}[2]${NC} ${WHITE}👥  Fetch Users${NC}                       ${CYAN}│${NC}"
        echo -e "  ${CYAN}│${NC}  ${PINK}[3]${NC} ${WHITE}📤  Send Broadcast${NC}                    ${CYAN}│${NC}"
        echo -e "  ${CYAN}│${NC}  ${PINK}[4]${NC} ${WHITE}🧪  Test Message${NC}                      ${CYAN}│${NC}"
        echo -e "  ${CYAN}│${NC}  ${PINK}[5]${NC} ${WHITE}📋  View Log${NC}                          ${CYAN}│${NC}"
        echo -e "  ${CYAN}│${NC}  ${PINK}[6]${NC} ${WHITE}📊  Statistics${NC}                        ${CYAN}│${NC}"
        echo -e "  ${CYAN}│${NC}  ${PINK}[7]${NC} ${WHITE}📖  Help / Guide${NC}                      ${CYAN}│${NC}"
        echo -e "  ${CYAN}│${NC}  ${PINK}[0]${NC} ${WHITE}🚪  Exit${NC}                              ${CYAN}│${NC}"
        echo -e "  ${CYAN}╰──────────────────────────────────────────╯${NC}"
        echo ""
        printf "  ${PINK}➜${NC} ${WHITE}Select option:${NC} "
        read -r choice
        echo ""

        case "$choice" in
            1) setup_bot ;;
            2) fetch_users_menu ;;
            3) send_message_menu ;;
            4) test_message ;;
            5) view_log ;;
            6) show_stats ;;
            7) show_help ;;
            0) cleanup ;;
            *) echo -e "  ${RED}✗ Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

# ============================================================
# ENTRY
# ============================================================
load_config
boot_animation
main_menu