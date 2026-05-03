#!/bin/bash

# --- 基础配置 ---
sh_path=$(readlink -f "$0")
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- 快捷指令安装 ---
install_mc() {
    if [[ "$sh_path" != "/usr/bin/mc" ]]; then
        cp "$sh_path" /usr/bin/mc >/dev/null 2>&1
        chmod +x /usr/bin/mc >/dev/null 2>&1
    fi
}
install_mc

# --- 核心状态检测 ---
check_virt() {
    VTYPE=$(systemd-detect-virt 2>/dev/null || echo "Unknown")
    [[ -f /proc/user_beancounters || -d /proc/vz ]] && VTYPE="openvz"
    grep -qa container=lxc /proc/1/environ 2>/dev/null && VTYPE="lxc"
    echo "$VTYPE"
}

check_status() {
    local type=$1
    case $type in
        bbr) [[ $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null) == "bbr" ]] && echo "ON" || echo "OFF" ;;
        ipv6) [[ $(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null) == "1" ]] && echo "OFF" || echo "ON" ;;
        ecn) [[ $(sysctl -n net.ipv4.tcp_ecn 2>/dev/null) == "1" ]] && echo "ON" || echo "OFF" ;;
    esac
}

# --- 基础信息显示 ---
get_info() {
    clear
    V_INFO=$(check_virt)
    echo -e "${CYAN}================ 服务器工具箱 (指令: mc) ==================${NC}"
    echo -e "操作系统: $([[ -f /etc/os-release ]] && source /etc/os-release && echo $PRETTY_NAME || uname -s)"
    echo -e "内核版本: $(uname -r) ($V_INFO)"
    
    IP4=$(curl -s4 --connect-timeout 2 ifconfig.me || echo "获取失败")
    GEO=$(curl -s --connect-timeout 2 "https://ipapi.co/$IP4/country_name/" 2>/dev/null || echo "未知地区")
    echo -e "IPv4地址: $IP4 ($GEO)"
    
    IP6=$(curl -s6 --connect-timeout 2 ifconfig.me 2>/dev/null)
    [[ -n "$IP6" ]] && echo -e "IPv6地址: $IP6"

    MEM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
    MEM_USED=$(free -m | awk '/Mem:/ {print $3}')
    SWAP_TOTAL=$(free -m | awk '/Swap:/ {print $2}')
    echo -e "内存占用: ${MEM_USED}MB / ${MEM_TOTAL}MB (Swap: ${SWAP_TOTAL}MB)"
    echo -e "系统负载: $(cat /proc/loadavg | awk '{print $1" "$2" "$3}')"
    echo -e "${CYAN}===========================================================${NC}"
}

# --- 一键优化功能入口 ---
one_click_optimize() {
    V_TYPE=$(check_virt)
    TOTAL_MEM=$(free -m | awk '/Mem:/ {print $2}')
    
    echo -e "\n${YELLOW}[ 1. 网络与协议栈开关 ]${NC}"

    # BBR 开关
    if [[ $(check_status bbr) == "OFF" ]]; then
        read -p "检测到 BBR 未开启，是否开启? [y/n]: " op; [[ "$op" == "y" ]] && (echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf; echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf; sysctl -p >/dev/null 2>&1)
    else
        read -p "检测到 BBR 已开启，是否关闭还原? [y/n]: " op; [[ "$op" == "y" ]] && (sed -i '/bbr/d' /etc/sysctl.conf; sed -i '/fq/d' /etc/sysctl.conf; sysctl -p >/dev/null 2>&1)
    fi

    # ECN 开关
    if [[ $(check_status ecn) == "ON" ]]; then
        read -p "检测到 ECN 已开启(某些地区可能丢包)，是否关闭? [y/n]: " op; [[ "$op" == "y" ]] && (echo "net.ipv4.tcp_ecn=0" >> /etc/sysctl.conf; sysctl -p >/dev/null 2>&1)
    else
        read -p "检测到 ECN 已关闭，是否开启? [y/n]: " op; [[ "$op" == "y" ]] && (echo "net.ipv4.tcp_ecn=1" >> /etc/sysctl.conf; sysctl -p >/dev/null 2>&1)
    fi

    # IPv6 开关
    if [[ $(check_status ipv6) == "ON" ]]; then
        read -p "检测到 IPv6 已开启，是否禁用? [y/n]: " op; [[ "$op" == "y" ]] && (sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1)
    else
        read -p "检测到 IPv6 已禁用，是否启用? [y/n]: " op; [[ "$op" == "y" ]] && (sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null 2>&1)
    fi

    echo -e "\n${YELLOW}[ 2. 虚拟内存设置 ]${NC}"
    read -p "是否设置/调整 Swap? [y/n]: " s_res
    if [[ "$s_res" == "y" ]]; then
        read -p "请输入 Swap 大小 (MB, 输入0为关闭): " sz
        swapoff -a >/dev/null 2>&1
        if [ "$sz" -gt 0 ]; then
            dd if=/dev/zero of=/swapfile bs=1M count=$sz
            chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
            grep -q "/swapfile" /etc/fstab || echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
            echo -e "${GREEN}Swap 设置完成${NC}"
        fi
    fi

    echo -e "\n${YELLOW}[ 3. 深度系统调优策略 ]${NC}"
    echo -e "系统检测内存为: ${TOTAL_MEM}MB"
    [[ $TOTAL_MEM -le 512 ]] && echo -e "建议选择: ${RED}1. 保守模式${NC}" || echo -e "建议选择: ${GREEN}2. 激进模式${NC}"
    read -p "请选择 (1:保守 / 2:激进 / n:跳过): " m_res

    if [[ "$m_res" == "1" || "$m_res" == "2" ]]; then
        if [[ "$V_TYPE" == "lxc" || "$V_TYPE" == "openvz" ]]; then
            echo -e "${RED}LXC/OpenVZ 仅执行应用层优化 (DNS/Ulimit/Cleanup)...${NC}"
            ulimit -n 655350 >/dev/null 2>&1
            echo "nameserver 8.8.8.8" > /etc/resolv.conf
        else
            # 激进模式参数
            if [[ "$m_res" == "2" ]]; then
                cat > /etc/sysctl.d/99-mc-opt.conf <<EOF
net.core.somaxconn = 65535
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fastopen = 3
fs.file-max = 1000000
vm.swappiness = 60
vm.vfs_cache_pressure = 150
EOF
            else
                # 保守模式参数
                cat > /etc/sysctl.d/99-mc-opt.conf <<EOF
net.ipv4.tcp_max_syn_backlog = 1024
vm.swappiness = 10
EOF
            fi
            sysctl --system >/dev/null 2>&1
        fi
        echo -e "${GREEN}调优执行完毕！${NC}"
    fi
}

# --- 菜单控制 ---
while true; do
    get_info
    echo -e "1. 一键优化/配置菜单 (自动识别开关)"
    echo -e "q. 退出脚本"
    read -p "选择操作: " choice
    case $choice in
        1) one_click_optimize; read -p "操作完成，回车返回菜单..." ;;
        q) exit 0 ;;
        *) continue ;;
    esac
done
