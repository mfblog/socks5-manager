#!/usr/bin/env bash
# =================================================================================
# Multi-IP SOCKS5 Proxy Management Matrix (3proxy - Ingress/Egress IP Binding)
# =================================================================================
# 项目地址: https://github.com/mfblog/socks5-manager
# 核心架构: 基于 3proxy 实现多 IP 服务器 SOCKS5 代理严格「源进源出」
# 核心功能:
#   1. 自动扫描服务器所有有效公网 IPv4 地址
#   2. 自动配置 Linux 策略路由 (ip rule) 与宽松反向路径过滤 (rp_filter=2)
#   3. 为每个 IP 单独绑定 internal (入站监听) 与 external (出站发起)
#   4. 随机高强度密码/账号生成，支持统一端口或独立端口
#   5. 极低资源消耗 (C语言原生长驻，内存仅约 5MB)
# =================================================================================

export TERM=${TERM:-xterm-256color}
export DEBIAN_FRONTEND=noninteractive
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

CONFIG_FILE="/etc/3proxy/3proxy.cfg"
CONFIG_META="/etc/3proxy/3proxy_meta.conf"
INSTALLED_SCRIPT="/usr/local/share/socks5_multi_ip.sh"
SHORTCUT_BIN="/usr/local/bin/S5M"
SHORTCUT_LOWER_BIN="/usr/local/bin/s5m"
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
SELECTED_IPS=()
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
    echo "  ║   ███████╗ ██████╗  ██████╗ ██╗  ██╗██╗   ██╗   ██╗██████╗ ║"
    echo "  ║   ██╔════╝██╔════╝ ██╔════╝ ██║ ██╔╝██║   ██║   ██║██╔══██╗║"
    echo "  ║   ███████╗███████╗ ██║      █████╔╝ ██║   ██║   ██║██████╔╝║"
    echo "  ║   ╚════██║╚════██║ ██║      ██╔═██╗ ██║   ██║   ██║██╔═══╝ ║"
    echo "  ║   ███████║███████║ ╚██████╗ ██║  ██╗███████╗███████║██║    ║"
    echo "  ╚════════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
    draw_line "$COLOR_MAIN"
    print_center "MULTI-IP INGRESS / EGRESS SOCKS5 MATRIX (3PROXY)" "$COLOR_INF"
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
# 本地快捷指令安装与持久化配置 (支持大小写 S5M / s5m 自动识别)
# =================================================================================
install_shortcut() {
    mkdir -p /usr/local/bin /usr/local/share 2>/dev/null
    local current_script
    current_script=$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")
    
    if [ -f "$current_script" ] && [ "$current_script" != "$INSTALLED_SCRIPT" ]; then
        cp -f "$current_script" "$INSTALLED_SCRIPT" 2>/dev/null
        chmod 700 "$INSTALLED_SCRIPT" 2>/dev/null
    fi

    cat << 'EOF_S5M' > "$SHORTCUT_BIN"
#!/usr/bin/env bash
if [ -f /usr/local/share/socks5_multi_ip.sh ]; then
    exec bash /usr/local/share/socks5_multi_ip.sh "$@"
else
    echo -e "\033[31m[✖] 未找到多 IP SOCKS5 控制台程序，请重新安装。\033[0m"
    exit 1
fi
EOF_S5M
    chmod 755 "$SHORTCUT_BIN" 2>/dev/null

    # 兼容小写指令 s5m
    cp -f "$SHORTCUT_BIN" "$SHORTCUT_LOWER_BIN" 2>/dev/null
    chmod 755 "$SHORTCUT_LOWER_BIN" 2>/dev/null
}

save_meta() {
    mkdir -p /etc/3proxy 2>/dev/null
    cat << EOF > "$CONFIG_META"
SOCKS_PORT="${SOCKS_PORT}"
SOCKS_USER="${SOCKS_USER}"
SOCKS_PASS="${SOCKS_PASS}"
SELECTED_IPS=(${SELECTED_IPS[*]})
EOF
    chmod 600 "$CONFIG_META"
}

load_meta() {
    if [ -f "$CONFIG_META" ]; then
        # shellcheck disable=SC1090
        source "$CONFIG_META"
        return 0
    fi
    return 1
}

# =================================================================================
# 环境检测与依赖安装模块
# =================================================================================
check_environment_and_deps() {
    print_banner
    print_step "[1/5] 正在初始化系统环境与网络组件"
    
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
    for cmd in curl wget iptables ip gzip openssl sha256sum; do
        if ! command -v "$cmd" >/dev/null 2>&1; then 
            NEED_INSTALL+=("$cmd")
        fi
    done

    if [ ${#NEED_INSTALL[@]} -ne 0 ]; then
        print_note "正在安装缺失的系统组件与依赖：[ ${NEED_INSTALL[*]} ]..."
        case "$OS_TYPE" in
            alpine) 
                apk add --no-cache "${NEED_INSTALL[@]}" iproute2 iputils openssl coreutils gzip >/dev/null 2>&1 ;;
            debian) 
                apt-get update -qq >/dev/null 2>&1
                apt-get install -yqq --no-install-recommends "${NEED_INSTALL[@]}" iproute2 iputils-ping openssl coreutils gzip >/dev/null 2>&1 ;;
            rhel) 
                if command -v dnf >/dev/null 2>&1; then
                    dnf install -y -q "${NEED_INSTALL[@]}" iproute iputils openssl coreutils gzip >/dev/null 2>&1
                else
                    yum install -y -q "${NEED_INSTALL[@]}" iproute iputils openssl coreutils gzip >/dev/null 2>&1
                fi ;;
        esac
    fi
    print_ok "系统依赖环境就绪！"
}

# =================================================================================
# 多 IP 智能扫描与参数配置模块
# =================================================================================
is_valid_ipv4() {
    local ip="$1"
    local rx='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    if [[ "$ip" =~ $rx ]]; then
        local IFS='.'
        local -a octets=($ip)
        for oct in "${octets[@]}"; do
            if [ "$oct" -lt 0 ] || [ "$oct" -gt 255 ]; then
                return 1
            fi
        done
        # 排除回环地址 (127.x.x.x)
        if [ "${octets[0]}" -eq 127 ]; then
            return 1
        fi
        return 0
    fi
    return 1
}

detect_all_ips() {
    local detected=()
    # 精准提取所有 inet 后的 IPv4 地址，过滤掉接口名称与其它文本
    while IFS= read -r line; do
        local candidate
        candidate=$(echo "$line" | grep -oE 'inet [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | awk '{print $2}')
        if [ -n "$candidate" ] && is_valid_ipv4 "$candidate"; then
            detected+=("$candidate")
        fi
    done < <(ip -4 -o addr show scope global 2>/dev/null || ip -4 addr show 2>/dev/null)

    # 兜底：如果 ip 命令未能解析，尝试通过 hostname -I / ifconfig 提取
    if [ ${#detected[@]} -eq 0 ]; then
        if command -v hostname >/dev/null 2>&1; then
            for cand in $(hostname -I 2>/dev/null); do
                if is_valid_ipv4 "$cand"; then
                    detected+=("$cand")
                fi
            done
        fi
    fi

    # 严格去重并输出纯 IP 列表
    if [ ${#detected[@]} -gt 0 ]; then
        printf "%s\n" "${detected[@]}" | sort -u | tr '\n' ' '
    fi
}

collect_parameters() {
    print_banner
    print_step "[2/5] 正在配置多 IP 绑定与运行时凭据"
    draw_dash "$COLOR_SEC"

    print_info "正在扫描本地网卡的所有可用 IPv4 地址..."
    local detected_raw
    detected_raw=$(detect_all_ips)
    read -r -a ALL_IPS <<< "$detected_raw"

    if [ ${#ALL_IPS[@]} -eq 0 ]; then
        print_err "未在服务器上检测到任何可用的 IPv4 地址，请检查网络配置。"
        exit 1
    fi

    echo ""
    echo -e "   ${COLOR_INF}📡 检测到本机分配的 IPv4 地址列表 (${#ALL_IPS[@]} 个):${RESET}"
    for i in "${!ALL_IPS[@]}"; do
        echo -e "      ${COLOR_MAIN}[$((i+1))]${RESET} ${COLOR_TXT}${ALL_IPS[$i]}${RESET}"
    done
    echo ""

    SELECTED_IPS=("${ALL_IPS[@]}")
    print_note "默认将对以上所有检测到的 IP (${#SELECTED_IPS[@]} 个) 启用【源进源出】独立代理通道。"
    printf "   ${COLOR_INF}是否直接使用上述所有 IP? [Y/n]: ${RESET}"
    read -r use_all_input < /dev/tty 2>/dev/null || read -r use_all_input
    if [[ "${use_all_input,,}" == "n" ]]; then
        echo ""
        printf "   ${COLOR_INF}请输入要启用的 IP (多个用空格隔开): ${RESET}"
        read -r custom_ips_input < /dev/tty 2>/dev/null || read -r custom_ips_input
        if [ -n "$custom_ips_input" ]; then
            read -r -a SELECTED_IPS <<< "$custom_ips_input"
        fi
    fi

    echo ""
    print_info "已选定参与源进源出的 IP 列表: ${COLOR_SUC}${SELECTED_IPS[*]}${RESET}"

    RANDOM_PORT=$((RANDOM % 50000 + 10000))
    RANDOM_USER=$(generate_random_user)
    RANDOM_PASS=$(generate_random_pass)

    echo ""
    while true; do
        printf "   ${COLOR_INF}🔌 设置统一代理监听端口 [回车默认随机: ${COLOR_SUC}%s${RESET}${COLOR_INF}]: ${RESET}" "$RANDOM_PORT"
        read -r INPUT_PORT < /dev/tty 2>/dev/null || read -r INPUT_PORT
        SOCKS_PORT=${INPUT_PORT:-$RANDOM_PORT}
        SOCKS_PORT=$(echo "$SOCKS_PORT" | tr -d ' \t\r\n')

        case "$SOCKS_PORT" in
            ''|*[!0-9]*) print_warn "格式无效：端口必须仅由纯数字组成。" ;;
            *)
                if [ "$SOCKS_PORT" -ge 1024 ] && [ "$SOCKS_PORT" -le 65535 ]; then
                    break
                else
                    print_warn "范围错误：端口必须在 1024 到 65535 之间。"
                fi
                ;;
        esac
    done
    print_info "已锁定代理端口：${COLOR_TXT}${SOCKS_PORT}${RESET}"

    echo ""
    while true; do
        printf "   ${COLOR_INF}👤 设置代理认证用户名 [回车默认高强度随机: ${COLOR_SUC}%s${RESET}${COLOR_INF}]: ${RESET}" "$RANDOM_USER"
        read -r INPUT_USER < /dev/tty 2>/dev/null || read -r INPUT_USER
        SOCKS_USER=${INPUT_USER:-$RANDOM_USER}
        SOCKS_USER=$(echo "$SOCKS_USER" | tr -d ' \t\r\n')
        [ -n "$SOCKS_USER" ] && break || print_warn "用户名不能为空。"
    done
    print_info "已锁定代理用户名：${COLOR_TXT}${SOCKS_USER}${RESET}"

    echo ""
    while true; do
        printf "   ${COLOR_INF}🔑 设置代理认证密码 [回车默认高强度随机: ${COLOR_SUC}%s${RESET}${COLOR_INF}]: ${RESET}" "$RANDOM_PASS"
        read -r INPUT_PASS < /dev/tty 2>/dev/null || read -r INPUT_PASS
        SOCKS_PASS=${INPUT_PASS:-$RANDOM_PASS}
        SOCKS_PASS=$(echo "$SOCKS_PASS" | tr -d ' \t\r\n')
        [ -n "$SOCKS_PASS" ] && break || print_warn "密码不能为空。"
    done
    print_info "已锁定代理密码：${COLOR_TXT}${SOCKS_PASS}${RESET}"
    echo ""
    save_meta
}

# =================================================================================
# Linux 内核策略路由与网络加固 (确保跨网卡/跨子网源路返回)
# =================================================================================
configure_kernel_routing() {
    print_step "[3/5] 正在配置 Linux 内核策略路由与反向路径过滤"

    # 1. 开启宽松反向路径过滤 rp_filter=2 (避免多网卡/多IP回包被丢弃)
    sysctl -w net.ipv4.conf.all.rp_filter=2 >/dev/null 2>&1 || true
    sysctl -w net.ipv4.conf.default.rp_filter=2 >/dev/null 2>&1 || true
    
    mkdir -p /etc/sysctl.d 2>/dev/null
    cat << 'EOF_SYS' > /etc/sysctl.d/99-3proxy-network.conf
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
net.ipv4.ip_forward = 1
EOF_SYS
    sysctl --system >/dev/null 2>&1 || true

    # 2. 为跨网卡/独立网关的 IP 配置源路由策略 (ip rule)
    local table_idx=100
    for target_ip in "${SELECTED_IPS[@]}"; do
        ((table_idx++))
        # 查找该 IP 所在的网卡接口
        local iface
        iface=$(ip -4 route get "$target_ip" 2>/dev/null | awk '{for(i=1;i<=NF;i++)if($i=="dev")print $(i+1)}' | head -n 1)
        if [ -n "$iface" ]; then
            # 开启该网卡的 rp_filter
            sysctl -w "net.ipv4.conf.${iface}.rp_filter=2" >/dev/null 2>&1 || true
            
            # 添加策略路由规则 (保证回包按源 IP 策略走)
            ip rule del from "$target_ip"/32 2>/dev/null || true
            ip rule add from "$target_ip"/32 table "$table_idx" priority "$table_idx" 2>/dev/null || true
            
            # 查找默认网关
            local gw
            gw=$(ip route show dev "$iface" | grep "default" | awk '{print $3}' | head -n 1)
            [ -z "$gw" ] && gw=$(ip route | grep "default" | awk '{print $3}' | head -n 1)
            
            if [ -n "$gw" ]; then
                ip route flush table "$table_idx" 2>/dev/null || true
                ip route add default via "$gw" dev "$iface" table "$table_idx" 2>/dev/null || true
            fi
        fi
    done
    print_ok "内核策略路由规则已就绪！[多 IP 源进源出保障]"
}

# =================================================================================
# 3proxy 预编译包下载与部署模块 (直接从 Git 仓库拉取 + SHA256 完整性校验)
# =================================================================================
install_3proxy() {
    print_step "[4/5] 部署 3proxy 核心代理服务 (免编译极速安装)"

    if ! command -v 3proxy >/dev/null 2>&1 || [ ! -f /usr/local/bin/3proxy ]; then
        local ARCH
        ARCH=$(uname -m)
        local DL_NAME=""
        local EXPECTED_HASH=""

        case "$ARCH" in
            x86_64|amd64)
                DL_NAME="3proxy-linux-amd64.gz"
                EXPECTED_HASH="08beb02c4ab0c0c715f5f701250d249dcff8a4b1889ae089a921cc38e1bdb484"
                ;;
            aarch64|arm64)
                DL_NAME="3proxy-linux-arm64.gz"
                EXPECTED_HASH="494cb64f7609e9c250cc31bc20057e7a4569cb225a3da40b9461e3ebc50850c4"
                ;;
            armv7l|armv7|armhf)
                DL_NAME="3proxy-linux-armv7.gz"
                EXPECTED_HASH="4a7f66e8284caa5e9a5224003c6b11c7af3a38e4d7587235d22f070718427d06"
                ;;
            *)
                print_err "未匹配到预编译二进制架构：${ARCH}，正在尝试本地源码编译作为备用方案..."
                ;;
        esac

        local dl_success=0
        if [ -n "$DL_NAME" ]; then
            local RAW_URL="https://raw.githubusercontent.com/4kercc/socks5-manager/main/bin/${DL_NAME}"
            print_info "正在从 GitHub 官方仓库直接下载预编译核心包: ${COLOR_INF}${DL_NAME}${RESET}"

            local max_retries=3
            local retry_count=0

            while [ $retry_count -lt $max_retries ]; do
                ((retry_count++))
                if curl -fL --progress-bar --connect-timeout 10 --max-time 60 "$RAW_URL" -o /tmp/3proxy.gz; then
                    if [ -s /tmp/3proxy.gz ]; then
                        dl_success=1
                        break
                    fi
                fi
                print_warn "下载第 ${retry_count}/${max_retries} 次失败，2 秒后重试..."
                sleep 2
            done

            if [ "$dl_success" -eq 1 ]; then
                # SHA256 完整性哈希校验
                print_info "正在进行二进制包 SHA256 完整性哈希校验..."
                local ACTUAL_HASH
                ACTUAL_HASH=$(sha256sum /tmp/3proxy.gz | awk '{print $1}')

                if [ "$ACTUAL_HASH" != "$EXPECTED_HASH" ]; then
                    print_err "安全拦截：SHA256 哈希校验失败！预期: ${EXPECTED_HASH}, 实际: ${ACTUAL_HASH}"
                    rm -f /tmp/3proxy.gz
                    dl_success=0
                else
                    print_ok "SHA256 校验通过！[官方二进制包完整无篡改]"
                    gzip -d -f /tmp/3proxy.gz
                    chmod 755 /tmp/3proxy
                    mv -f /tmp/3proxy /usr/local/bin/3proxy
                    print_ok "3proxy 官方预编译核心部署成功 [/usr/local/bin/3proxy]"
                fi
            fi
        fi

        # 备用容灾方案：如果预编译下载或校验失败，自动降级为本地源码编译
        if [ "$dl_success" -ne 1 ] && [ ! -f /usr/local/bin/3proxy ]; then
            print_warn "预编译包不可用，正在自动切换为源码编译备用安装..."
            local build_dir="/tmp/3proxy_build"
            rm -rf "$build_dir" && mkdir -p "$build_dir"
            local tar_url="https://github.com/3proxy/3proxy/archive/refs/tags/0.9.4.tar.gz"
            if curl -fL --connect-timeout 10 --max-time 60 "$tar_url" -o "$build_dir/3proxy.tar.gz" && [ -s "$build_dir/3proxy.tar.gz" ]; then
                tar -xzf "$build_dir/3proxy.tar.gz" -C "$build_dir"
                local src_dir
                src_dir=$(find "$build_dir" -maxdepth 1 -type d -name "3proxy-*" | head -n 1)
                if [ -d "$src_dir" ]; then
                    cd "$src_dir" || exit 1
                    make -f Makefile.Linux >/dev/null 2>&1
                    make -f Makefile.Linux install >/dev/null 2>&1
                    cp -f bin/3proxy /usr/local/bin/3proxy 2>/dev/null || true
                    chmod 755 /usr/local/bin/3proxy
                fi
            fi
            rm -rf "$build_dir"
        fi
    fi

    if ! command -v 3proxy >/dev/null 2>&1 && [ ! -f /usr/local/bin/3proxy ]; then
        print_err "3proxy 核心安装失败，请检查网络设置或系统权限。"
        exit 1
    fi
    print_ok "3proxy 核心代理引擎部署就绪 [/usr/local/bin/3proxy]"

    # 生成 3proxy 核心配置文件 (启用流量统计日志)
    mkdir -p /etc/3proxy /var/log/3proxy
    cat << EOF > "$CONFIG_FILE"
# =============================================================================
# 3proxy SOCKS5 Multi-IP Configuration Matrix (Traffic Stat Supported)
# =============================================================================
daemon
maxconn 4000
nscache 65536
timeouts 1 5 30 60 180 1800 15 60

# -----------------------------------------------------------------------------
# 流量日志记录模块 (精确记录每个客户端的 Ingress/Egress 字节数与 IP)
# -----------------------------------------------------------------------------
log /var/log/3proxy/access.log D
logformat "L%Y-%m-%d %H:%M:%S\t%u\t%e\t%I\t%O\t%E"

auth strong
users ${SOCKS_USER}:CL:${SOCKS_PASS}

EOF

    for ip in "${SELECTED_IPS[@]}"; do
        cat << EOF >> "$CONFIG_FILE"
# -----------------------------------------------------------------------------
# 节点 IP: ${ip} (源进源出专属通道)
# -----------------------------------------------------------------------------
internal ${ip}
external ${ip}
socks -p${SOCKS_PORT} -a

EOF
    done

    chmod 600 "$CONFIG_FILE"
    print_ok "3proxy 多 IP 绑定配置文件生成完毕 [/etc/3proxy/3proxy.cfg]"

    # 配置 systemd 服务
    if command -v systemctl >/dev/null 2>&1 && systemctl list-units >/dev/null 2>&1; then
        cat << 'EOF_SVC' > /etc/systemd/system/3proxy.service
[Unit]
Description=3proxy Multi-IP Ingress/Egress SOCKS5 Daemon
After=network.target
Wants=network.target

[Service]
Type=forking
LimitNOFILE=1048576
ExecStart=/usr/local/bin/3proxy /etc/3proxy/3proxy.cfg
Restart=always
RestartSec=3s

[Install]
WantedBy=multi-user.target
EOF_SVC
        systemctl daemon-reload
        systemctl enable 3proxy >/dev/null 2>&1
        systemctl restart 3proxy
        print_ok "3proxy 守护进程加载并启动！"
    else
        killall -9 3proxy >/dev/null 2>&1 || true
        /usr/local/bin/3proxy "$CONFIG_FILE"
        print_warn "后台常驻模式已启动。"
    fi
    echo ""
}

# =================================================================================
# 防火墙端口放行模块
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
    print_ok "防火墙端口放行完成 [端口: ${SOCKS_PORT}]"
    echo ""
    draw_line "$COLOR_MAIN"
    print_ok "多 IP 源进源出 SOCKS5 代理系统已成功部署！"
    sleep 1.5
}

# =================================================================================
# 状态查询与交互面板模块
# =================================================================================
get_service_status() {
    if pgrep -x "3proxy" >/dev/null 2>&1; then
        echo -e "${COLOR_SUC}🟢 运行中 (在线)${RESET}"
    else
        echo -e "${COLOR_ERR}🔴 已停止 (离线)${RESET}"
    fi
}

get_autostart_status() {
    if command -v systemctl >/dev/null 2>&1 && systemctl list-units >/dev/null 2>&1; then
        if systemctl is-enabled 3proxy >/dev/null 2>&1; then
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
    print_center "===== 🔄 重启 3proxy 代理服务 =====" "$COLOR_SEC"
    echo ""
    if command -v systemctl >/dev/null 2>&1 && systemctl list-units >/dev/null 2>&1; then
        systemctl restart 3proxy
    else
        killall -9 3proxy >/dev/null 2>&1 || true
        /usr/local/bin/3proxy "$CONFIG_FILE"
    fi
    sleep 1
    print_ok "3proxy 服务已完成平滑重启！"
    sleep 1.2
}

stop_service() {
    print_banner
    print_center "===== ⏹️ 停止 3proxy 代理服务 =====" "$COLOR_ERR"
    echo ""
    if command -v systemctl >/dev/null 2>&1 && systemctl list-units >/dev/null 2>&1; then
        systemctl stop 3proxy
    else
        killall -9 3proxy >/dev/null 2>&1 || true
    fi
    sleep 1
    print_ok "3proxy 服务已停止。"
    sleep 1.2
}

# 配置中保存的是 3proxy 监听地址；NAT 环境下可通过该节点查询对应的公网出口。
get_node_public_ip() {
    local ingress_ip="$1" public_ip
    public_ip=$(curl -fsS --noproxy '' --socks5 "${ingress_ip}:${SOCKS_PORT}" \
        --proxy-user "${SOCKS_USER}:${SOCKS_PASS}" \
        --connect-timeout 4 --max-time 8 https://api.ipify.org 2>/dev/null) || return 1
    is_valid_ipv4 "$public_ip" || return 1
    printf '%s' "$public_ip"
}

show_credentials() {
    print_banner
    load_meta
    print_center "===== 📋 多 IP 源进源出代理节点清单 =====" "$COLOR_SEC"
    echo ""
    echo -e "   ${COLOR_INF}🔌 统一监听端口 :${RESET} ${COLOR_SUC}${SOCKS_PORT}${RESET}"
    echo -e "   ${COLOR_INF}👤 统一认证账号 :${RESET} ${COLOR_TXT}${SOCKS_USER}${RESET}"
    echo -e "   ${COLOR_INF}🔑 统一认证密码 :${RESET} ${COLOR_TXT}${SOCKS_PASS}${RESET}"
    echo ""
    draw_dash "$COLOR_SEC"
    echo -e "   ${COLOR_WAR}【各个独立 IP 专属代理连接信息】（内网入站地址自动转换为公网出口地址）：${RESET}"
    echo ""
    for idx in "${!SELECTED_IPS[@]}"; do
        local ip="${SELECTED_IPS[$idx]}"
        local link_ip=""
        printf "   🔹 节点 %s [入站: %s] 正在查询公网 IP（最多 8 秒）...\n" "$((idx+1))" "$ip"
        link_ip=$(get_node_public_ip "$ip") || link_ip=""
        if [ -n "$link_ip" ]; then
            echo -e "      ${COLOR_INF}SOCKS5 链接:${RESET} ${COLOR_TXT}socks5://${SOCKS_USER}:${SOCKS_PASS}@${link_ip}:${SOCKS_PORT}${RESET}"
            echo -e "      ${COLOR_DIM}客户端参数: IP=${link_ip} | 端口=${SOCKS_PORT} | 账号=${SOCKS_USER} | 密码=${SOCKS_PASS}${RESET}"
        else
            print_warn "无法查询 ${ip} 的公网出口 IP，暂不生成链接；请检查该节点连接。"
        fi
        echo ""
    done
    draw_dash "$COLOR_SEC"
    if [ -t 0 ] && [ -t 1 ]; then
        printf "\n   ${COLOR_SEC}👉 按任意键返回主控制面板...${RESET}"
        read -n 1 -s -r < /dev/tty
    else
        echo ""
        print_info "非交互终端：已保留节点结果，可在交互终端输入 s5m 查看。"
    fi
}

test_all_ips() {
    print_banner
    load_meta
    print_note "先经各节点本地入站查询公网 IP，再经该公网地址测试连接及出口..."
    echo ""
    for idx in "${!SELECTED_IPS[@]}"; do
        local ip="${SELECTED_IPS[$idx]}" public_ip="" exit_ip=""
        public_ip=$(get_node_public_ip "$ip") || public_ip=""
        if [ -z "$public_ip" ]; then
            echo -e "   🌐 测试节点 $((idx+1)) [内网入站: ${ip}] ... ${COLOR_ERR}✖ 无法查询公网 IP${RESET}"
            continue
        fi
        printf "   🌐 测试节点 $((idx+1)) [公网入站: %s] ... " "$public_ip"
        # 第二次请求走公网入口；不能仅将第一次查询到的出口 IP 与自身比较。
        exit_ip=$(get_node_public_ip "$public_ip") || exit_ip=""
        if [ -z "$exit_ip" ]; then
            echo -e "${COLOR_ERR}✖ 公网入口连接失败${RESET}"
        elif [ "$exit_ip" = "$public_ip" ]; then
            echo -e "${COLOR_SUC}✔ 成功！出口 IP: ${exit_ip} [公网入口与出口一致]${RESET}"
        else
            echo -e "${COLOR_WAR}⚠ 公网入口可连，但出口不一致 (当前出口: ${exit_ip})${RESET}"
        fi
    done
    echo ""
    draw_dash "$COLOR_SEC"
    printf "\n   ${COLOR_SEC}👉 按任意键返回主控制面板...${RESET}"
    read -n 1 -s -r < /dev/tty 2>/dev/null || read -n 1 -s -r
}

format_bytes() {
    local bytes="$1"
    if [ -z "$bytes" ] || [ "$bytes" -le 0 ] 2>/dev/null; then
        echo "0.00 B"
        return
    fi
    if [ "$bytes" -ge 1073741824 ]; then
        awk -v b="$bytes" 'BEGIN {printf "%.2f GB", b/1073741824}'
    elif [ "$bytes" -ge 1048576 ]; then
        awk -v b="$bytes" 'BEGIN {printf "%.2f MB", b/1048576}'
    elif [ "$bytes" -ge 1024 ]; then
        awk -v b="$bytes" 'BEGIN {printf "%.2f KB", b/1024}'
    else
        echo "${bytes} B"
    fi
}

view_traffic_stats() {
    print_banner
    load_meta
    print_center "===== 📊 各节点与全局流量实时消耗统计 =====" "$COLOR_SEC"
    echo ""
    local log_dir="/var/log/3proxy"
    
    if [ ! -d "$log_dir" ] || [ -z "$(ls -A "$log_dir" 2>/dev/null)" ]; then
        print_warn "暂无流量日志记录（服务刚启动或尚未产生网络连接）。"
        echo ""
        draw_dash "$COLOR_SEC"
        printf "\n   ${COLOR_SEC}👉 按任意键返回主控制面板...${RESET}"
        read -n 1 -s -r < /dev/tty 2>/dev/null || read -n 1 -s -r
        return
    fi

    # 计算今日日志文件
    local today_log
    today_log="${log_dir}/access.log.$(date +%Y.%m.%d)"
    [ ! -f "$today_log" ] && today_log="${log_dir}/access.log"

    print_info "统计周期: 【今日实时】与【历史累计】"
    echo ""
    draw_dash "$COLOR_SEC"

    local total_all_in=0
    local total_all_out=0

    for idx in "${!SELECTED_IPS[@]}"; do
        local ip="${SELECTED_IPS[$idx]}"
        
        # 日志字段为 日期 时间 用户名 出站绑定IP 入站字节 出站字节 错误码；
        # NAT 后公网 IP 不在日志里，按绑定的内网 IP 汇总再显示其公网映射。
        local stats
        stats=$(awk -v target="$ip" '
            $4 == target {
                in_b += $5
                out_b += $6
            }
            END {
                printf "%s %s", in_b+0, out_b+0
            }
        ' "${log_dir}"/access.log* 2>/dev/null)

        local ip_in ip_out ip_total
        ip_in=$(echo "$stats" | awk '{print $1}')
        ip_out=$(echo "$stats" | awk '{print $2}')
        ip_total=$((ip_in + ip_out))

        total_all_in=$((total_all_in + ip_in))
        total_all_out=$((total_all_out + ip_out))

        local public_ip=""
        public_ip=$(get_node_public_ip "$ip") || public_ip=""
        if [ -n "$public_ip" ]; then
            echo -e "   🔹 ${COLOR_MAIN}节点 $((idx+1)) [公网 IP: ${public_ip}]${RESET}"
        else
            echo -e "   🔹 ${COLOR_MAIN}节点 $((idx+1)) [公网 IP: 查询失败，内网入站 ${ip}]${RESET}"
        fi
        echo -e "      ${COLOR_INF}⬇️ 下载 (In) :${RESET} ${COLOR_TXT}$(format_bytes "$ip_in")${RESET}  |  ${COLOR_INF}⬆️ 上传 (Out):${RESET} ${COLOR_TXT}$(format_bytes "$ip_out")${RESET}"
        echo -e "      ${COLOR_SUC}📦 总吞吐量  :${RESET} ${COLOR_WAR}$(format_bytes "$ip_total")${RESET}"
        echo ""
    done

    local grand_total=$((total_all_in + total_all_out))
    draw_line "$COLOR_MAIN"
    echo -e "   ${COLOR_SUC}📈 全局汇总统计 :${RESET}"
    echo -e "   • 全节点总下行: ${COLOR_TXT}$(format_bytes "$total_all_in")${RESET}  |  全节点总上行: ${COLOR_TXT}$(format_bytes "$total_all_out")${RESET}"
    echo -e "   • ${COLOR_WAR}🔥 全服总消耗流量 : $(format_bytes "$grand_total")${RESET}"
    draw_dash "$COLOR_SEC"
    echo ""
    echo -e "   ${COLOR_DIM}[提示] 流量数据基于 3proxy 高性能原生日志实时统计，已自动计入双向吞吐。${RESET}"
    printf "\n   ${COLOR_SEC}👉 按任意键返回主控制面板...${RESET}"
    read -n 1 -s -r < /dev/tty 2>/dev/null || read -n 1 -s -r
}

uninstall_all() {
    print_banner
    print_center "===== 🗑️ 彻底卸载 3proxy 服务 =====" "$COLOR_ERR"
    echo ""
    print_warn "警告：此操作将终止 3proxy 并彻底清理所有配置文件与服务定义！"
    echo ""
    read -p "   ${ICON_STEP} 确认执行彻底卸载? [y/N]: " confirm_rm </dev/tty
    if [[ "${confirm_rm,,}" == "y" ]]; then
        print_step "正在清理系统服务与配置文件..."
        load_meta
        stop_service
        if command -v iptables >/dev/null 2>&1 && [ -n "$SOCKS_PORT" ]; then
            iptables -D INPUT -p tcp --dport "$SOCKS_PORT" -j ACCEPT 2>/dev/null
            iptables -D INPUT -p udp --dport "$SOCKS_PORT" -j ACCEPT 2>/dev/null
        fi
        command -v systemctl >/dev/null 2>&1 && systemctl list-units >/dev/null 2>&1 && { 
            systemctl disable 3proxy >/dev/null 2>&1
            rm -f /etc/systemd/system/3proxy.service
            systemctl daemon-reload
        }
        rm -rf /etc/3proxy /usr/local/bin/3proxy "$SHORTCUT_BIN" "$SHORTCUT_LOWER_BIN" "$INSTALLED_SCRIPT" /etc/sysctl.d/99-3proxy-network.conf
        print_ok "3proxy 多 IP 代理系统已彻底清理复原！"
        exit 0
    else
        print_info "已取消卸载，返回主菜单。"
        sleep 1.2
    fi
}

menu_ui() {
    while true; do
        load_meta
        print_banner
        echo -e "  ${COLOR_SEC}┌────────────────────────────────────────────────────────────┐${RESET}"
        echo -e "  ${COLOR_SEC}│${RESET}  ${ICON_NOTE} ${COLOR_TXT}快捷提示:${RESET} 在终端输入 ${COLOR_SUC}s5m${RESET} 或 ${COLOR_SUC}S5M${RESET} 即可随时打开控制台      ${COLOR_SEC}│${RESET}"
        echo -e "  ${COLOR_SEC}└────────────────────────────────────────────────────────────┘${RESET}"
        echo ""
        echo -e "   📡 服务运行状态  : $(get_service_status)"
        echo -e "   🚀 开机自启策略  : $(get_autostart_status)"
        echo -e "   🌐 托管 IP 数量  : ${COLOR_SUC}${#SELECTED_IPS[@]} 个 IP${RESET}"
        draw_dash "$COLOR_SEC"
        echo -e "  ${COLOR_MAIN} [1]${RESET} ${COLOR_TXT} 查看多 IP 节点连接凭证 ${COLOR_DIM}(展示各IP对应的SOCKS5链接)${RESET}"
        echo -e "  ${COLOR_MAIN} [2]${RESET} ${COLOR_TXT} 一键全节点「源进源出」出口测试 ${COLOR_DIM}(验证出口IP是否与入口一致)${RESET}"
        echo -e "  ${COLOR_MAIN} [3]${RESET} ${COLOR_TXT} 查看各节点与全局流量消耗统计 ${COLOR_DIM}(实时汇总各IP上传/下载流量)${RESET}"
        echo -e "  ${COLOR_MAIN} [4]${RESET} ${COLOR_TXT} 启动 / 重启 3proxy 代理服务  ${COLOR_DIM}(平滑重载配置文件)${RESET}"
        echo -e "  ${COLOR_MAIN} [5]${RESET} ${COLOR_TXT} 停止 3proxy 代理服务        ${COLOR_DIM}(安全终止代理守护进程)${RESET}"
        echo -e "  ${COLOR_MAIN} [6]${RESET} ${COLOR_TXT} 重新配置参数与多 IP 列表    ${COLOR_DIM}(修改端口/密码/重新扫描IP)${RESET}"
        echo -e "  ${COLOR_MAIN} [7]${RESET} ${COLOR_TXT} 彻底卸载并清理系统环境      ${COLOR_DIM}(删除3proxy及所有配置文件)${RESET}"
        echo -e "  ${COLOR_ERR} [8]${RESET}  ${COLOR_ERR} 退出控制面板并返回 Shell    ${COLOR_DIM}(保持后台代理服务正常运行)${RESET}"
        draw_line "$COLOR_MAIN"
        echo ""
        printf "  ${COLOR_INF}⚡ 请输入你的选择 [1-8]: ${RESET}"
        read -r CHOICE < /dev/tty 2>/dev/null || read -r CHOICE
        case "$CHOICE" in
            1) show_credentials ;;
            2) test_all_ips ;;
            3) view_traffic_stats ;;
            4) restart_service ;;
            5) stop_service ;;
            6) collect_parameters; configure_kernel_routing; install_3proxy; configure_firewall; show_credentials ;;
            7) uninstall_all ;;
            8) 
                print_ok "感谢使用 SOCKS5 Multi-IP Matrix，再会！"
                exit 0 
                ;;
            *)
                print_err "无效的选项，请重新输入数字 [1-8]。"
                sleep 1.2
                ;;
        esac
    done
}

main() {
    install_shortcut
    check_environment_and_deps
    if [ -f "$CONFIG_FILE" ] && [ -f "/usr/local/bin/3proxy" ]; then
        if [ -t 0 ] && [ -t 1 ]; then
            menu_ui
        else
            show_credentials
        fi
    else
        collect_parameters
        configure_kernel_routing
        install_3proxy
        configure_firewall
        show_credentials
        if [ -t 0 ] && [ -t 1 ]; then
            menu_ui
        fi
    fi
}

main "$@"
