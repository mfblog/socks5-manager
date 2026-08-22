#!/usr/bin/env bash
# =================================================================================
# High-Performance SOCKS5 Proxy Management Matrix (Hardened & Secured Edition)
# =================================================================================
# 项目地址: https://github.com/4kercc/socks5-manager
# 架构规范: 生产级安全加固版，具备极高稳定性、全系统兼容性与极致视觉体验
# 功能说明: 基于 Gost 官方原版构建高性能、高并发、安全可控的 SOCKS5 代理运维管理系统
# =================================================================================

export TERM=${TERM:-xterm-256color}
export DEBIAN_FRONTEND=noninteractive
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

REPO_RAW_URL="https://raw.githubusercontent.com/4kercc/socks5-manager/main/s5_secured.sh"
CONFIG_FILE="/etc/socks5_gost.conf"
INSTALLED_SCRIPT="/usr/local/share/socks5_matrix.sh"
SHORTCUT_BIN="/usr/local/bin/S5"
SHORTCUT_LOWER_BIN="/usr/local/bin/s5"
UI_WIDTH=68

ESC=$(printf '\033')
BOLD="${ESC}[1m"
FAINT="${ESC}[2m"
RESET="${ESC}[0m"

COLOR_MAIN="${ESC}[1;38;5;51m"   # 亮青色
COLOR_SEC="${ESC}[1;38;5;141m"  # 亮紫色
COLOR_SUC="${ESC}[1;38;5;46m"   # 亮绿色
COLOR_ERR="${ESC}[1;38;5;196m"  # 亮红色
COLOR_WAR="${ESC}[1;38;5;226m"  # 亮黄色
COLOR_TXT="${ESC}[1;38;5;231m"  # 纯白色
COLOR_DIM="${ESC}[1;38;5;250m"  # 亮灰色
COLOR_INF="${ESC}[1;38;5;39m"   # 亮蓝色

ICON_OK="${COLOR_SUC}✔${RESET}"
ICON_ERR="${COLOR_ERR}✖${RESET}"
ICON_WARN="${COLOR_WAR}⚠${RESET}"
ICON_INFO="${COLOR_INF}ℹ${RESET}"
ICON_STEP="${COLOR_MAIN}⚡${RESET}"
ICON_NOTE="${COLOR_SEC}💡${RESET}"

OS_TYPE=""
SERVER_IP=""
SOCKS_PORT=""
SOCKS_USER=""
SOCKS_PASS=""

# =================================================================================
# 界面渲染与辅助计算模块
# =================================================================================
get_visual_len() {
    local clean_str
    clean_str=$(echo -e "$1" | sed 's/\x1b\[[0-9;]*m//g')
    local char_len=${#clean_str}
    local byte_len=$(printf "%s" "$clean_str" | wc -c)
    echo $(( (char_len + byte_len) / 2 ))
}

draw_line() {
    local color="${1:-$COLOR_MAIN}"
    echo -e "${color}════════════════════════════════════════════════════════════════════${RESET}"
}

draw_dash() {
    local color="${1:-$COLOR_SEC}"
    echo -e "${color}────────────────────────────────────────────────────────────────────${RESET}"
}

print_center() {
    local text="$1"
    local color="${2:-$COLOR_TXT}"
    local text_len
    text_len=$(get_visual_len "$text")
    local pad=$(( (UI_WIDTH - text_len) / 2 ))
    [ $pad -lt 0 ] && pad=0
    printf "%${pad}s" ""
    echo -e "${color}${text}${RESET}"
}

print_banner() {
    clear
    echo -e "${COLOR_MAIN}${BOLD}"
    echo "  ╔════════════════════════════════════════════════════════════╗"
    echo "  ║                                                           ︎ ║"
    echo "  ║   ███████╗  ██████╗   ██████╗  ██╗  ██╗  ███████╗  ███████ ║"
    echo "  ║   ██╔════╝ ██╔═══██╗ ██╔════╝  ██║ ██╔╝  ██╔════╝  ██╔════ ║"
    echo "  ║   ███████╗ ██║   ██║ ██║       █████╔╝   ███████╗  ███████ ║"
    echo "  ║   ╚════██║ ██║   ██║ ██║       ██╔═██╗   ╚════██║       ██ ║"
    echo "  ║   ███████║ ╚██████╔╝ ╚██████╗  ██║  ██╗  ███████║  ███████ ║"
    echo "  ║                                                          ︎  ║"
    echo "  ╚════════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
    draw_line "$COLOR_MAIN"
    print_center "PRODUCTION GRADE PROXY MANAGEMENT MATRIX (SECURED)" "$COLOR_INF"
    draw_line "$COLOR_MAIN"
    echo ""
}

print_step() { echo -e "${ICON_STEP} ${COLOR_TXT}$1${RESET}"; }
print_info() { echo -e "   ${ICON_INFO} ${COLOR_TXT}$1${RESET}"; }
print_warn() { echo -e "   ${ICON_WARN} ${COLOR_WAR}$1${RESET}"; }
print_ok()   { echo -e "   ${ICON_OK} ${COLOR_SUC}$1${RESET}"; }
print_err()  { echo -e "   ${ICON_ERR} ${COLOR_ERR}$1${RESET}"; }
print_note() { echo -e "   ${ICON_NOTE} ${COLOR_SEC}[提示]: ${COLOR_TXT}$1${RESET}"; }

# =================================================================================
# 随机安全凭据生成模块
# =================================================================================
generate_random_user() {
    local prefix="usr"
    local rand_suffix
    if command -v openssl >/dev/null 2>&1; then
        rand_suffix=$(openssl rand -hex 3 2>/dev/null)
    elif [ -r /dev/urandom ]; then
        rand_suffix=$(tr -dc 'a-z0-9' < /dev/urandom | head -c 6 2>/dev/null)
    else
        rand_suffix=$((RANDOM % 900000 + 100000))
    fi
    echo "${prefix}_${rand_suffix}"
}

generate_random_pass() {
    local pass=""
    if command -v openssl >/dev/null 2>&1; then
        pass=$(openssl rand -base64 12 2>/dev/null | tr -dc 'A-Za-z0-9' | head -c 16)
    fi
    if [ -z "$pass" ] || [ ${#pass} -lt 12 ]; then
        if [ -r /dev/urandom ]; then
            pass=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16 2>/dev/null)
        else
            pass="P@ss_$(date +%s%N | sha256sum | head -c 12)"
        fi
    fi
    echo "$pass"
}

# =================================================================================
# 安全本地快捷方式持久化管理 (支持大小写 S5 / s5 自动识别)
# =================================================================================
install_shortcut() {
    mkdir -p /usr/local/bin /usr/local/share 2>/dev/null
    local current_script
    current_script=$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")
    
    # 将脚本固化到 /usr/local/share/socks5_matrix.sh
    if [ -f "$current_script" ] && [ "$current_script" != "$INSTALLED_SCRIPT" ]; then
        cp -f "$current_script" "$INSTALLED_SCRIPT" 2>/dev/null
        chmod 700 "$INSTALLED_SCRIPT" 2>/dev/null
    fi

    cat << 'EOF_S5' > "$SHORTCUT_BIN"
#!/usr/bin/env bash
if [ -f /usr/local/share/socks5_matrix.sh ]; then
    exec bash /usr/local/share/socks5_matrix.sh "$@"
else
    echo -e "\033[31m[✖] 未找到本地控制台程序，请重新安装。\033[0m"
    exit 1
fi
EOF_S5
    chmod 755 "$SHORTCUT_BIN" 2>/dev/null

    # 兼容小写指令 s5
    cp -f "$SHORTCUT_BIN" "$SHORTCUT_LOWER_BIN" 2>/dev/null
    chmod 755 "$SHORTCUT_LOWER_BIN" 2>/dev/null
}

save_config() {
    print_note "正在持久化保存配置参数到本地存储..."
    cat << EOF > "$CONFIG_FILE"
SERVER_IP="${SERVER_IP}"
SOCKS_PORT="${SOCKS_PORT}"
SOCKS_USER="${SOCKS_USER}"
SOCKS_PASS="${SOCKS_PASS}"
EOF
    chmod 600 "$CONFIG_FILE"
    print_ok "配置已通过严格权限控制持久化保存 [/etc/socks5_gost.conf]"
}

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"
        return 0
    fi
    return 1
}

# =================================================================================
# 环境检测与依赖组件初始化
# =================================================================================
check_environment_and_deps() {
    print_banner
    print_step "[1/5] 正在初始化系统环境与依赖组件"
    
    [ "$(id -u)" -ne 0 ] && { print_err "权限拒绝：必须使用 Root 权限，请通过 sudo -i 运行。"; exit 1; }

    if grep -qi "alpine" /etc/os-release 2>/dev/null; then 
        OS_TYPE="alpine"
    elif grep -qiE "debian|ubuntu" /etc/os-release 2>/dev/null; then 
        OS_TYPE="debian"
    elif grep -qiE "centos|rhel|fedora|rocky|almalinux" /etc/os-release 2>/dev/null; then 
        OS_TYPE="rhel"
    else 
        OS_TYPE="generic"
    fi
    
    print_info "检测到操作系统发行版：${COLOR_TXT}${OS_TYPE}${RESET}"

    local NEED_INSTALL=()
    for cmd in curl wget bash iptables gzip tar ping ip sha256sum openssl; do
        if ! command -v "$cmd" >/dev/null 2>&1; then 
            NEED_INSTALL+=("$cmd")
        fi
    done

    if [ ${#NEED_INSTALL[@]} -ne 0 ]; then
        print_note "正在安装缺失的必要软件包：[ ${NEED_INSTALL[*]} ]..."
        case "$OS_TYPE" in
            alpine) 
                apk add --no-cache "${NEED_INSTALL[@]}" iproute2 iputils openssl coreutils >/dev/null 2>&1 ;;
            debian) 
                apt-get update -qq >/dev/null 2>&1
                apt-get install -yqq --no-install-recommends "${NEED_INSTALL[@]}" iproute2 iputils-ping openssl coreutils >/dev/null 2>&1 ;;
            rhel) 
                if command -v dnf >/dev/null 2>&1; then
                    dnf install -y -q "${NEED_INSTALL[@]}" iproute iputils openssl coreutils >/dev/null 2>&1
                else
                    yum install -y -q "${NEED_INSTALL[@]}" iproute iputils openssl coreutils >/dev/null 2>&1
                fi ;;
        esac
    fi

    if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 || curl -s4m 2 https://8.8.8.8 >/dev/null 2>&1; then
        print_ok "主网络路由检查通过 [8.8.8.8]"
    elif ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1 || curl -s4m 2 https://1.1.1.1 >/dev/null 2>&1; then
        print_warn "主路由响应稍慢，备用网络路由连通 [1.1.1.1]"
    else
        print_err "致命错误：外网连通性检查失败，请检查 VPS 网络设置。"
        exit 1
    fi
}

# =================================================================================
# 公网 IP 智能探测与参数交互配置模块
# =================================================================================
collect_parameters() {
    print_banner
    print_step "[2/5] 正在配置运行时参数与网络绑定"
    draw_dash "$COLOR_SEC"

    print_info "正在通过官方多源 API 探测公网 IPv4 地址..."
    AUTO_IP=""
    for api in "https://api.ipify.org" "https://ifconfig.me" "https://ip.sb" "https://icanhazip.com" "https://ipinfo.io/ip"; do
        AUTO_IP=$(curl -4sSL --connect-timeout 2 --max-time 3 "$api" 2>/dev/null | tr -d ' \t\r\n')
        if [[ -n "$AUTO_IP" && "$AUTO_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            break
        fi
    done

    RANDOM_PORT=$((RANDOM % 50000 + 10000))
    RANDOM_USER=$(generate_random_user)
    RANDOM_PASS=$(generate_random_pass)

    echo ""
    while true; do
        if [ -n "$AUTO_IP" ]; then
            printf "   ${COLOR_INF}🌐 确认公网 IP [默认: ${COLOR_SUC}%s${RESET}${COLOR_INF}]: ${RESET}" "$AUTO_IP"
            read -r INPUT_IP < /dev/tty 2>/dev/null || read -r INPUT_IP
            SERVER_IP=${INPUT_IP:-$AUTO_IP}
        else
            printf "   ${COLOR_INF}🌐 自动探测失败，请输入服务器公网 IP: ${RESET}"
            read -r SERVER_IP < /dev/tty 2>/dev/null || read -r SERVER_IP
        fi
        SERVER_IP=$(echo "$SERVER_IP" | tr -d ' \t\r\n')
        [ -n "$SERVER_IP" ] && break || print_warn "公网 IP 不能为空。"
    done
    print_info "已绑定服务器 IP：${COLOR_TXT}${SERVER_IP}${RESET}"

    echo ""
    while true; do
        printf "   ${COLOR_INF}🔌 设置监听端口 [回车默认随机: ${COLOR_SUC}%s${RESET}${COLOR_INF}]: ${RESET}" "$RANDOM_PORT"
        read -r INPUT_PORT < /dev/tty 2>/dev/null || read -r INPUT_PORT
        SOCKS_PORT=${INPUT_PORT:-$RANDOM_PORT}
        SOCKS_PORT=$(echo "$SOCKS_PORT" | tr -d ' \t\r\n')

        case "$SOCKS_PORT" in
            ''|*[!0-9]*) print_warn "格式无效：端口必须仅由纯数字组成。" ;;
            *)
                if [ "$SOCKS_PORT" -ge 1024 ] && [ "$SOCKS_PORT" -le 65535 ]; then
                    local port_busy=0
                    command -v ss >/dev/null 2>&1 && ss -tuln 2>/dev/null | grep -qE "[:.]$SOCKS_PORT([[:space:]]|$)" && port_busy=1
                    command -v netstat >/dev/null 2>&1 && netstat -tuln 2>/dev/null | grep -qE "[:.]$SOCKS_PORT([[:space:]]|$)" && port_busy=1
                    [ "$port_busy" -eq 1 ] && print_warn "端口冲突：指定端口已被占用，请更换。" || break
                else
                    print_warn "范围错误：端口必须在 1024 到 65535 之间。"
                fi
                ;;
        esac
    done
    print_info "已锁定监听端口：${COLOR_TXT}${SOCKS_PORT}${RESET}"

    echo ""
    while true; do
        printf "   ${COLOR_INF}👤 设置代理用户名 [回车默认高强度随机: ${COLOR_SUC}%s${RESET}${COLOR_INF}]: ${RESET}" "$RANDOM_USER"
        read -r INPUT_USER < /dev/tty 2>/dev/null || read -r INPUT_USER
        SOCKS_USER=${INPUT_USER:-$RANDOM_USER}
        SOCKS_USER=$(echo "$SOCKS_USER" | tr -d ' \t\r\n')
        [ -n "$SOCKS_USER" ] && break || print_warn "用户名不能为空。"
    done
    print_info "已锁定代理用户名：${COLOR_TXT}${SOCKS_USER}${RESET}"

    echo ""
    while true; do
        printf "   ${COLOR_INF}🔑 设置代理密码 [回车默认高强度随机: ${COLOR_SUC}%s${RESET}${COLOR_INF}]: ${RESET}" "$RANDOM_PASS"
        read -r INPUT_PASS < /dev/tty 2>/dev/null || read -r INPUT_PASS
        SOCKS_PASS=${INPUT_PASS:-$RANDOM_PASS}
        SOCKS_PASS=$(echo "$SOCKS_PASS" | tr -d ' \t\r\n')
        [ -n "$SOCKS_PASS" ] && break || print_warn "密码不能为空。"
    done
    print_info "已锁定代理密码：${COLOR_TXT}${SOCKS_PASS}${RESET}"
    echo ""
    save_config
}

# =================================================================================
# 官方原版直连下载与 SHA256 完整性哈希校验模块
# =================================================================================
download_core() {
    print_step "[3/5] 直连 GitHub 官方仓库下载核心并校验完整性"
    
    ARCH=$(uname -m)
    local DL_FILE=""
    local EXPECTED_HASH=""

    case "$ARCH" in
        x86_64|amd64)
            DL_FILE="gost-linux-amd64-2.11.5.gz"
            EXPECTED_HASH="3417fd178ef9f86a5bda4e56d90739411df9d9ff3657724abc5614bb32e50f4b"
            ;;
        aarch64|arm64)
            DL_FILE="gost-linux-armv8-2.11.5.gz"
            EXPECTED_HASH="9b606482837e1796009e1647994e7d6e2747c10ea577dd9a13e37b9b43a3fc40"
            ;;
        armv7l|armv7)
            DL_FILE="gost-linux-armv7-2.11.5.gz"
            EXPECTED_HASH="3ac582afa4db4af5ff8686e7be34a46989757b6651cdaecb07dbce028f3a489c"
            ;;
        i386|i686)
            DL_FILE="gost-linux-386-2.11.5.gz"
            EXPECTED_HASH="39962047d348380a665473336f042162350de7eb396f6c1bf460e75debd4a29e"
            ;;
        *)
            print_err "不支持的 CPU 架构：${ARCH}"
            exit 1
            ;;
    esac

    local OFFICIAL_URL="https://github.com/ginuerzh/gost/releases/download/v2.11.5/${DL_FILE}"
    print_info "正在从 GitHub 官方直连下载: ${COLOR_INF}${OFFICIAL_URL}${RESET}"

    local max_retries=3
    local retry_count=0
    local dl_success=0

    while [ $retry_count -lt $max_retries ]; do
        ((retry_count++))
        if curl -fL --progress-bar --connect-timeout 10 --max-time 120 "$OFFICIAL_URL" -o /tmp/gost.gz; then
            if [ -s /tmp/gost.gz ]; then
                dl_success=1
                break
            fi
        fi
        print_warn "GitHub 直连下载第 ${retry_count}/${max_retries} 次失败，2 秒后重试..."
        sleep 2
    done

    if [ "$dl_success" -ne 1 ]; then
        print_err "致命错误：无法连接到 GitHub 官方服务器，请检查服务器网络。"
        exit 1
    fi

    # SHA256 完整性哈希校验
    print_info "正在进行二进制包 SHA256 完整性哈希校验..."
    local ACTUAL_HASH
    ACTUAL_HASH=$(sha256sum /tmp/gost.gz | awk '{print $1}')

    if [ "$ACTUAL_HASH" != "$EXPECTED_HASH" ]; then
        print_err "安全拦截：SHA256 哈希校验失败！"
        print_err "预期哈希: ${EXPECTED_HASH}"
        print_err "实际哈希: ${ACTUAL_HASH}"
        rm -f /tmp/gost.gz
        exit 1
    fi
    print_ok "SHA256 校验通过！[完整性与安全性验证无误]"

    print_info "正在解压并部署 Gost 二进制文件..."
    gzip -d -f /tmp/gost.gz
    chmod 755 /tmp/gost
    mv -f /tmp/gost /usr/local/bin/gost
    print_ok "Gost 官方核心代理引擎部署成功 [/usr/local/bin/gost]"
    echo ""
}

# =================================================================================
# 系统服务守护进程配置模块 (Systemd / OpenRC)
# =================================================================================
setup_daemon() {
    print_step "[4/5] 正在配置系统服务守护进程与开机自启策略"

    if command -v systemctl >/dev/null 2>&1 && systemctl list-units >/dev/null 2>&1; then
        cat << EOF > /etc/systemd/system/socks5.service
[Unit]
Description=Gost Socks5 Proxy Service (Secured Matrix)
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
LimitNOFILE=1048576
ExecStart=/usr/local/bin/gost -L socks5://${SOCKS_USER}:${SOCKS_PASS}@:${SOCKS_PORT}
Restart=always
RestartSec=3s

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable socks5 >/dev/null 2>&1
        systemctl restart socks5
        print_ok "Systemd 服务守护进程成功加载并启动！"

    elif command -v openrc-run >/dev/null 2>&1 || command -v rc-service >/dev/null 2>&1; then
        cat << EOF > /etc/init.d/socks5
#!/sbin/openrc-run
name="socks5"
description="Gost Socks5 Proxy Service"
command="/usr/local/bin/gost"
command_args="-L socks5://${SOCKS_USER}:${SOCKS_PASS}@:${SOCKS_PORT}"
command_background="yes"
pidfile="/run/socks5.pid"
depend() {
    need net
}
EOF
        chmod 755 /etc/init.d/socks5
        rc-update add socks5 default >/dev/null 2>&1 || true
        rc-service socks5 restart >/dev/null 2>&1
        print_ok "OpenRC 原生服务守护进程部署成功！"
    else
        killall -9 gost >/dev/null 2>&1 || true
        nohup /usr/local/bin/gost -L socks5://${SOCKS_USER}:${SOCKS_PASS}@:${SOCKS_PORT} >/dev/null 2>&1 &
        print_warn "后台常驻模式已启动。"
    fi
    echo ""
}

# =================================================================================
# 防火墙端口放行与配置模块
# =================================================================================
configure_firewall() {
    print_step "[5/5] 正在配置系统防火墙规则与端口放行"
    if command -v iptables >/dev/null 2>&1; then
        iptables -I INPUT -p tcp --dport "$SOCKS_PORT" -j ACCEPT 2>/dev/null || true
        iptables -I INPUT -p udp --dport "$SOCKS_PORT" -j ACCEPT 2>/dev/null || true
    fi
    if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "active"; then
        ufw allow "$SOCKS_PORT"/tcp >/dev/null 2>&1 || true
        ufw allow "$SOCKS_PORT"/udp >/dev/null 2>&1 || true
    fi
    if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
        firewall-cmd --zone=public --add-port="${SOCKS_PORT}"/tcp --permanent >/dev/null 2>&1 || true
        firewall-cmd --zone=public --add-port="${SOCKS_PORT}"/udp --permanent >/dev/null 2>&1 || true
        firewall-cmd --reload >/dev/null 2>&1 || true
    fi
    print_ok "防火墙端口规则配置成功 [端口: ${SOCKS_PORT}]"
    echo ""
    draw_line "$COLOR_MAIN"
    print_ok "全套 SOCKS5 代理服务已成功部署并加固！"
    sleep 1.5
}

# =================================================================================
# 状态查询与控制模块
# =================================================================================
get_service_status() {
    load_config >/dev/null 2>&1
    local is_running=0
    
    if [ -n "$SOCKS_PORT" ]; then
        if command -v ss >/dev/null 2>&1 && ss -tuln 2>/dev/null | grep -qE "[:.]$SOCKS_PORT([[:space:]]|$)"; then
            is_running=1
        elif command -v netstat >/dev/null 2>&1 && netstat -tuln 2>/dev/null | grep -qE "[:.]$SOCKS_PORT([[:space:]]|$)"; then
            is_running=1
        fi
    fi
    
    if [ "$is_running" -eq 0 ]; then
        if pgrep -f "gost.*$SOCKS_PORT" >/dev/null 2>&1 || pgrep -x "gost" >/dev/null 2>&1; then
            is_running=1
        fi
    fi

    if [ "$is_running" -eq 1 ]; then
        echo -e "${COLOR_SUC}🟢 运行中 (在线)${RESET}"
    else
        echo -e "${COLOR_ERR}🔴 已停止 (离线)${RESET}"
    fi
}

get_autostart_status() {
    if command -v systemctl >/dev/null 2>&1 && systemctl list-units >/dev/null 2>&1; then
        if systemctl is-enabled socks5 >/dev/null 2>&1; then
            echo -e "${COLOR_SUC}已启用 (Enabled)${RESET}"
        else
            echo -e "${COLOR_ERR}已禁用 (Disabled)${RESET}"
        fi
    elif command -v rc-status >/dev/null 2>&1; then
        if rc-update show default 2>/dev/null | grep -q "socks5"; then
            echo -e "${COLOR_SUC}已启用 (Enabled)${RESET}"
        else
            echo -e "${COLOR_ERR}已禁用 (Disabled)${RESET}"
        fi
    else
        echo -e "${COLOR_WAR}未托管 (Manual)${RESET}"
    fi
}

restart_service() {
    print_banner
    print_center "===== 🔄 重启 SOCKS5 代理服务 =====" "$COLOR_SEC"
    echo ""
    load_config
    if command -v systemctl >/dev/null 2>&1 && systemctl list-units >/dev/null 2>&1; then
        systemctl restart socks5
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service socks5 restart
    else
        killall -9 gost >/dev/null 2>&1 || true
        nohup /usr/local/bin/gost -L socks5://${SOCKS_USER}:${SOCKS_PASS}@:${SOCKS_PORT} >/dev/null 2>&1 &
    fi
    sleep 1
    print_ok "SOCKS5 服务已完成平滑重启！"
    sleep 1.2
}

stop_service() {
    print_banner
    print_center "===== ⏹️ 停止 SOCKS5 代理服务 =====" "$COLOR_ERR"
    echo ""
    if command -v systemctl >/dev/null 2>&1 && systemctl list-units >/dev/null 2>&1; then
        systemctl stop socks5
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service socks5 stop
    else
        killall -9 gost >/dev/null 2>&1 || true
    fi
    sleep 1
    print_ok "SOCKS5 服务已停止。"
    sleep 1.2
}

toggle_autostart() {
    print_banner
    print_center "===== ⚙️ 切换开机自启动策略 =====" "$COLOR_SEC"
    echo ""
    if command -v systemctl >/dev/null 2>&1 && systemctl list-units >/dev/null 2>&1; then
        if systemctl is-enabled socks5 >/dev/null 2>&1; then
            systemctl disable socks5
            print_warn "开机自启已禁用。"
        else
            systemctl enable socks5
            print_ok "开机自启已启用。"
        fi
    elif command -v rc-update >/dev/null 2>&1; then
        if rc-update show default 2>/dev/null | grep -q "socks5"; then
            rc-update del socks5 default
            print_warn "开机自启已禁用。"
        else
            rc-update add socks5 default
            print_ok "开机自启已启用。"
        fi
    else
        print_warn "当前环境不支持自动化服务注册管理器。"
    fi
    sleep 1.5
}

show_credentials() {
    print_banner
    load_config
    print_center "===== 📋 SOCKS5 代理连接凭证与配置信息 =====" "$COLOR_SEC"
    echo ""
    echo -e "   ${COLOR_INF}🌐 服务器公网 IP :${RESET} ${COLOR_TXT}${SERVER_IP}${RESET}"
    echo -e "   ${COLOR_INF}🔌 代理监听端口 :${RESET} ${COLOR_SUC}${SOCKS_PORT}${RESET}"
    echo -e "   ${COLOR_INF}👤 代理认证账号 :${RESET} ${COLOR_TXT}${SOCKS_USER}${RESET}"
    echo -e "   ${COLOR_INF}🔑 代理认证密码 :${RESET} ${COLOR_TXT}${SOCKS_PASS}${RESET}"
    echo ""
    draw_dash "$COLOR_SEC"
    echo -e "   ${COLOR_INF}🔗 标准 SOCKS5 链接 :${RESET}"
    echo -e "   ${COLOR_WAR}socks5://${SOCKS_USER}:${SOCKS_PASS}@${SERVER_IP}:${SOCKS_PORT}${RESET}"
    echo ""
    echo -e "   ${COLOR_INF}💻 TG / 客户端快速代理格式 :${RESET}"
    echo -e "   ${COLOR_TXT}IP: ${SERVER_IP} | 端口: ${SOCKS_PORT} | 用户: ${SOCKS_USER} | 密码: ${SOCKS_PASS}${RESET}"
    draw_dash "$COLOR_SEC"
    printf "\n   ${COLOR_SEC}👉 按任意键返回主控制面板...${RESET}"
    read -n 1 -s -r < /dev/tty 2>/dev/null || read -n 1 -s -r
}

view_logs() {
    print_banner
    print_center "===== 📜 SOCKS5 运行日志查看 =====" "$COLOR_SEC"
    echo ""
    if command -v journalctl >/dev/null 2>&1 && systemctl list-units >/dev/null 2>&1; then
        journalctl -u socks5 -n 25 --no-pager 2>/dev/null || echo "暂无可用的 systemd 日志记录。"
    else
        echo "当前活跃的 gost 进程："
        ps aux | grep gost | grep -v grep || echo "未检测到活跃的 gost 进程。"
    fi
    echo ""
    draw_dash "$COLOR_SEC"
    printf "\n   ${COLOR_SEC}👉 按任意键返回主控制面板...${RESET}"
    read -n 1 -s -r < /dev/tty 2>/dev/null || read -n 1 -s -r
}

test_port() {
    print_banner
    load_config
    print_note "正在执行本地端口连通性与代理隧道诊断..."
    echo ""
    if command -v nc >/dev/null 2>&1; then
        nc -zv 127.0.0.1 "$SOCKS_PORT" 2>&1 && print_ok "本地环回端口检查通过。" || print_err "本地环回端口检查失败。"
    elif command -v curl >/dev/null 2>&1; then
        curl -s --socks5 "${SOCKS_USER}:${SOCKS_PASS}@127.0.0.1:${SOCKS_PORT}" https://api.ipify.org -m 5 && print_ok "SOCKS5 代理隧道通信测试成功！" || print_err "代理隧道通信测试失败。"
    else
        print_warn "未检测到诊断工具 (nc/curl)，已跳过测试。"
    fi
    echo ""
    draw_dash "$COLOR_SEC"
    printf "\n   ${COLOR_SEC}👉 按任意键返回主控制面板...${RESET}"
    read -n 1 -s -r < /dev/tty 2>/dev/null || read -n 1 -s -r
}

update_script() {
    print_banner
    print_center "===== 🔄 在线更新控制面板 =====" "$COLOR_SEC"
    echo ""
    print_info "正在从官方仓库拉取最新版本: ${COLOR_INF}${REPO_RAW_URL}${RESET}"
    local temp_script="/tmp/s5_update.sh"
    if curl -fsSL "$REPO_RAW_URL" -o "$temp_script" && [ -s "$temp_script" ]; then
        cp -f "$temp_script" "$INSTALLED_SCRIPT" 2>/dev/null
        chmod 700 "$INSTALLED_SCRIPT" 2>/dev/null
        rm -f "$temp_script"
        print_ok "控制面板已成功更新到最新版本！正在刷新..."
        sleep 1.2
        exec bash "$INSTALLED_SCRIPT"
    else
        print_err "更新失败：无法从官方仓库获取更新包。"
        sleep 2
    fi
}

uninstall_socks5() {
    print_banner
    print_center "===== 🗑️ 彻底卸载 SOCKS5 服务 =====" "$COLOR_ERR"
    echo ""
    print_warn "警告：此操作将终止代理服务并彻底清理相关配置与二进制程序！"
    echo ""
    read -p "   ${ICON_STEP} 确认执行彻底卸载? [y/N]: " confirm_rm </dev/tty
    if [[ "${confirm_rm,,}" == "y" ]]; then
        print_step "正在清理系统服务与配置文件..."
        load_config
        stop_service
        if command -v iptables >/dev/null 2>&1 && [ -n "$SOCKS_PORT" ]; then
            iptables -D INPUT -p tcp --dport "$SOCKS_PORT" -j ACCEPT 2>/dev/null
            iptables -D INPUT -p udp --dport "$SOCKS_PORT" -j ACCEPT 2>/dev/null
        fi
        command -v systemctl >/dev/null 2>&1 && systemctl list-units >/dev/null 2>&1 && { 
            systemctl disable socks5 >/dev/null 2>&1
            rm -f /etc/systemd/system/socks5.service
            systemctl daemon-reload
        }
        command -v rc-service >/dev/null 2>&1 && { 
            rc-update del socks5 default >/dev/null 2>&1
            rm -f /etc/init.d/socks5
        }
        rm -f /usr/local/bin/gost "$SHORTCUT_BIN" "$SHORTCUT_LOWER_BIN" "$INSTALLED_SCRIPT" "$CONFIG_FILE"
        print_ok "SOCKS5 代理系统已彻底清理并恢复！"
        exit 0
    else
        print_info "已取消卸载，返回主菜单。"
        sleep 1.2
    fi
}

# =================================================================================
# 主控制面板 UI 交互循环引擎
# =================================================================================
menu_ui() {
    while true; do
        load_config
        print_banner
        echo -e "  ${COLOR_SEC}┌────────────────────────────────────────────────────────────┐${RESET}"
        echo -e "  ${COLOR_SEC}│${RESET}  ${ICON_NOTE} ${COLOR_TXT}快捷提示:${RESET} 在终端输入 ${COLOR_SUC}s5${RESET} 或 ${COLOR_SUC}S5${RESET} 即可随时打开控制台        ${COLOR_SEC}│${RESET}"
        echo -e "  ${COLOR_SEC}└────────────────────────────────────────────────────────────┘${RESET}"
        echo ""
        echo -e "   📡 服务运行状态  : $(get_service_status)"
        echo -e "   🚀 开机自启策略  : $(get_autostart_status)"
        draw_dash "$COLOR_SEC"
        echo -e "  ${COLOR_MAIN} [1]${RESET} ${COLOR_TXT} 查看连接凭证与链接信息 ${COLOR_DIM}(展示IP/端口/密码/Socks5链接)${RESET}"
        echo -e "  ${COLOR_MAIN} [2]${RESET} ${COLOR_TXT} 启动 / 平滑重启代理服务 ${COLOR_DIM}(平滑重载配置并刷新守护进程)${RESET}"
        echo -e "  ${COLOR_MAIN} [3]${RESET} ${COLOR_TXT} 停止 / 安全终止代理服务 ${COLOR_DIM}(安全停止后台常驻代理守护进程)${RESET}"
        echo -e "  ${COLOR_MAIN} [4]${RESET} ${COLOR_TXT} 切换系统开机自启策略   ${COLOR_DIM}(开启或关闭系统开机自动运行)${RESET}"
        echo -e "  ${COLOR_MAIN} [5]${RESET} ${COLOR_TXT} 重新配置参数并重新部署 ${COLOR_DIM}(修改端口/账号密码并重新启动)${RESET}"
        echo -e "  ${COLOR_MAIN} [6]${RESET} ${COLOR_TXT} 查看系统运行日志与诊断 ${COLOR_DIM}(调取Systemd/进程运行日志)${RESET}"
        echo -e "  ${COLOR_MAIN} [7]${RESET} ${COLOR_TXT} 执行本地端口与隧道测试 ${COLOR_DIM}(测试Socks5代理通道连通性)${RESET}"
        echo -e "  ${COLOR_MAIN} [8]${RESET} ${COLOR_TXT} 检查官方仓库更新与热刷 ${COLOR_DIM}(从4kercc/socks5-manager拉取更新)${RESET}"
        echo -e "  ${COLOR_MAIN} [9]${RESET} ${COLOR_TXT} 完全卸载并清理系统环境 ${COLOR_DIM}(删除二进制文件与服务配置)${RESET}"
        echo -e "  ${COLOR_ERR} [10]${RESET}${COLOR_ERR} 退出控制面板并返回 Shell ${COLOR_DIM}(保持后台代理服务正常运行)${RESET}"
        draw_line "$COLOR_MAIN"
        echo ""
        printf "  ${COLOR_INF}⚡ 请输入你的选择 [1-10]: ${RESET}"
        read -r CHOICE < /dev/tty 2>/dev/null || read -r CHOICE
        case "$CHOICE" in
            1) show_credentials ;;
            2) restart_service ;;
            3) stop_service ;;
            4) toggle_autostart ;;
            5) collect_parameters; download_core; setup_daemon; configure_firewall; restart_service; show_credentials ;;
            6) view_logs ;;
            7) test_port ;;
            8) update_script ;;
            9) uninstall_socks5 ;;
            10) 
                print_ok "感谢使用 SOCKS5 Matrix 安全控制面板，再会！"
                exit 0 
                ;;
            *)
                print_err "无效的选项，请重新输入数字 [1-10]。"
                sleep 1.2
                ;;
        esac
    done
}

# =================================================================================
# 程序全局执行入口
# =================================================================================
main() {
    install_shortcut
    check_environment_and_deps
    if [ -f "$CONFIG_FILE" ] && [ -f "/usr/local/bin/gost" ]; then
        menu_ui
    else
        collect_parameters
        download_core
        setup_daemon
        configure_firewall
        show_credentials
        menu_ui
    fi
}

main "$@"
