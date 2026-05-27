#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

#=================================================
#       System Required: RedHat/AlmaLinux/Rocky Linux/Debian/Ubuntu
#       Description: Install and manage the ShadowsocksR server
#       Version: 2.0.3-modernized
#       Original Author: Toyo
#       Modernized: RHEL/Debian/Ubuntu compatibility, systemd, firewall detection
#=================================================

ssr_folder="/usr/local/shadowsocksr"
ssr_ss_file="${ssr_folder}/shadowsocks"
config_file="${ssr_folder}/config.json"
config_folder="/etc/shadowsocksr"
config_user_file="${config_folder}/user-config.json"
ssr_log_file="${ssr_ss_file}/ssserver.log"
Libsodiumr_file="/usr/local/lib/libsodium.so"
Libsodiumr_ver_backup="1.0.18"
jq_file="${ssr_folder}/jq"
Green_font_prefix="\033[32m" && Red_font_prefix="\033[31m" && Font_color_suffix="\033[0m"
Info="${Green_font_prefix}[信息]${Font_color_suffix}"
Error="${Red_font_prefix}[错误]${Font_color_suffix}"
Tip="${Green_font_prefix}[注意]${Font_color_suffix}"
Separator_1="——————————————————————————————"
release="unknown"
bit=""

command_exists(){ command -v "$1" >/dev/null 2>&1; }

check_root(){
    if [[ "$(id -u)" != "0" ]]; then
        echo -e "${Error} 请使用 root 权限运行此脚本。"
        exit 1
    fi
}

check_sys(){
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case "${ID:-}" in
            debian) release="debian" ;;
            ubuntu) release="ubuntu" ;;
            rhel|redhat|almalinux|rocky) release="rhel" ;;
            *)
                if echo "${ID_LIKE:-}" | grep -q -E -i "rhel|fedora"; then
                    release="rhel"
                elif echo "${ID_LIKE:-}" | grep -q -E -i "ubuntu"; then
                    release="ubuntu"
                elif echo "${ID_LIKE:-}" | grep -q -E -i "debian"; then
                    release="debian"
                else
                    release="unknown"
                fi
                ;;
        esac
    elif cat /etc/issue 2>/dev/null | grep -q -E -i "debian"; then
        release="debian"
    elif cat /etc/issue 2>/dev/null | grep -q -E -i "ubuntu"; then
        release="ubuntu"
    elif cat /etc/issue 2>/dev/null | grep -q -E -i "Red Hat|redhat|rhel|almalinux|rocky"; then
        release="rhel"
    elif cat /proc/version 2>/dev/null | grep -q -E -i "debian"; then
        release="debian"
    elif cat /proc/version 2>/dev/null | grep -q -E -i "ubuntu"; then
        release="ubuntu"
    elif cat /proc/version 2>/dev/null | grep -q -E -i "Red Hat|redhat|rhel|almalinux|rocky"; then
        release="rhel"
    else
        release="unknown"
    fi
    bit="$(uname -m)"
}

pkg_update(){
    if [[ ${release} == "rhel" ]]; then
        if command_exists dnf; then dnf makecache -y; else yum makecache -y; fi
    else
        apt-get update
    fi
}

pkg_install(){
    if [[ ${release} == "rhel" ]]; then
        if command_exists dnf; then dnf install -y "$@"; else yum install -y "$@"; fi
    else
        DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
    fi
}

service_enable(){
    if command_exists systemctl; then
        systemctl daemon-reload >/dev/null 2>&1 || true
        systemctl enable ssr >/dev/null 2>&1 || true
    elif [[ ${release} == "rhel" ]]; then
        chkconfig --add ssr >/dev/null 2>&1 || true
        chkconfig ssr on >/dev/null 2>&1 || true
    else
        update-rc.d -f ssr defaults >/dev/null 2>&1 || true
    fi
}

service_disable(){
    if command_exists systemctl; then
        systemctl disable ssr >/dev/null 2>&1 || true
        systemctl daemon-reload >/dev/null 2>&1 || true
    elif [[ ${release} == "rhel" ]]; then
        chkconfig --del ssr >/dev/null 2>&1 || true
    else
        update-rc.d -f ssr remove >/dev/null 2>&1 || true
    fi
}

service_start(){
    if command_exists systemctl && [[ -f /etc/systemd/system/ssr.service ]]; then
        systemctl start ssr
    else
        /etc/init.d/ssr start
    fi
}

service_stop(){
    if command_exists systemctl && [[ -f /etc/systemd/system/ssr.service ]]; then
        systemctl stop ssr
    else
        /etc/init.d/ssr stop
    fi
}

service_restart(){
    if command_exists systemctl && [[ -f /etc/systemd/system/ssr.service ]]; then
        systemctl restart ssr
    else
        /etc/init.d/ssr restart
    fi
}

write_systemd_service(){
    [[ ! -d /etc/systemd/system ]] && return 0
    cat > /etc/systemd/system/ssr.service <<'EOS'
[Unit]
Description=ShadowsocksR Server
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
ExecStart=/etc/init.d/ssr start
ExecStop=/etc/init.d/ssr stop
ExecReload=/etc/init.d/ssr restart
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOS
    systemctl daemon-reload >/dev/null 2>&1 || true
}

check_pid(){
    PID="$(ps -ef | grep -v grep | grep -E 'server.py|ssserver' | awk '{print $2}' | tr '\n' ' ')"
}

SSR_installation_status(){
    [[ ! -e ${config_user_file} ]] && echo -e "${Error} 没有发现 ShadowsocksR 配置文件，请检查 !" && exit 1
    [[ ! -e ${ssr_folder} ]] && echo -e "${Error} 没有发现 ShadowsocksR 文件夹，请检查 !" && exit 1
}

open_firewall_port(){
    local p="$1"
    [[ -z "${p}" ]] && return 0
    if command_exists firewall-cmd && systemctl is-active firewalld >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port=${p}/tcp >/dev/null 2>&1 || true
        firewall-cmd --permanent --add-port=${p}/udp >/dev/null 2>&1 || true
        firewall-cmd --reload >/dev/null 2>&1 || true
    elif command_exists ufw && ufw status 2>/dev/null | grep -q "Status: active"; then
        ufw allow ${p}/tcp >/dev/null 2>&1 || true
        ufw allow ${p}/udp >/dev/null 2>&1 || true
    elif command_exists iptables; then
        iptables -C INPUT -m state --state NEW -m tcp -p tcp --dport ${p} -j ACCEPT 2>/dev/null || iptables -I INPUT -m state --state NEW -m tcp -p tcp --dport ${p} -j ACCEPT
        iptables -C INPUT -m state --state NEW -m udp -p udp --dport ${p} -j ACCEPT 2>/dev/null || iptables -I INPUT -m state --state NEW -m udp -p udp --dport ${p} -j ACCEPT
    else
        echo -e "${Tip} 未发现 firewalld/ufw/iptables，请自行放行端口 ${p}/tcp 和 ${p}/udp。"
    fi
}

close_firewall_port(){
    local p="$1"
    [[ -z "${p}" ]] && return 0
    if command_exists firewall-cmd && systemctl is-active firewalld >/dev/null 2>&1; then
        firewall-cmd --permanent --remove-port=${p}/tcp >/dev/null 2>&1 || true
        firewall-cmd --permanent --remove-port=${p}/udp >/dev/null 2>&1 || true
        firewall-cmd --reload >/dev/null 2>&1 || true
    elif command_exists ufw && ufw status 2>/dev/null | grep -q "Status: active"; then
        ufw delete allow ${p}/tcp >/dev/null 2>&1 || true
        ufw delete allow ${p}/udp >/dev/null 2>&1 || true
    elif command_exists iptables; then
        while iptables -C INPUT -m state --state NEW -m tcp -p tcp --dport ${p} -j ACCEPT 2>/dev/null; do
            iptables -D INPUT -m state --state NEW -m tcp -p tcp --dport ${p} -j ACCEPT || break
        done
        while iptables -C INPUT -m state --state NEW -m udp -p udp --dport ${p} -j ACCEPT 2>/dev/null; do
            iptables -D INPUT -m state --state NEW -m udp -p udp --dport ${p} -j ACCEPT || break
        done
    fi
}

save_firewall_rules(){
    if command_exists iptables-save; then
        iptables-save > /etc/iptables.up.rules 2>/dev/null || true
    fi
}

Add_iptables(){ open_firewall_port "${ssr_port}"; }
Del_iptables(){ close_firewall_port "${port}"; }
Save_iptables(){ save_firewall_rules; }
Set_iptables(){ save_firewall_rules; }

Get_IP(){
    ip="$(wget -qO- -t1 -T2 https://ipinfo.io/ip 2>/dev/null || true)"
    [[ -z "$ip" ]] && ip="VPS_IP"
}

jq_get(){
    local key="$1"
    ${jq_file} -r "$key" "${config_user_file}"
}

Get_User(){
    [[ ! -e ${jq_file} ]] && echo -e "${Error} JQ解析器 不存在，请检查 !" && exit 1
    port="$(jq_get '.server_port')"
    password="$(jq_get '.password')"
    method="$(jq_get '.method')"
    protocol="$(jq_get '.protocol')"
    obfs="$(jq_get '.obfs')"
    protocol_param="$(jq_get '.protocol_param')"
    speed_limit_per_con="$(jq_get '.speed_limit_per_con')"
    speed_limit_per_user="$(jq_get '.speed_limit_per_user')"
}

b64(){ echo -n "$1" | base64 | tr -d '\n'; }


ssr_link_qr(){
    SSRprotocol="$(echo ${protocol} | sed 's/_compatible//g')"
    SSRobfs="$(echo ${obfs} | sed 's/_compatible//g')"
    SSRPWDbase64="$(b64 "${password}")"
    SSRbase64="$(b64 "${ip}:${port}:${SSRprotocol}:${method}:${SSRobfs}:${SSRPWDbase64}")"
    SSRurl="ssr://${SSRbase64}"
    SSRQRcode="https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=${SSRurl}"
    ssr_link=" SSR   链接 : ${Red_font_prefix}${SSRurl}${Font_color_suffix} \n SSR 二维码 : ${Red_font_prefix}${SSRQRcode}${Font_color_suffix} \n "
}

ss_ssr_determine(){
    protocol_suffix="$(echo ${protocol} | awk -F "_" '{print $NF}')"
    obfs_suffix="$(echo ${obfs} | awk -F "_" '{print $NF}')"
    ss_link=""
    if [[ ${protocol} = "origin" ]]; then
        if [[ ${obfs} = "plain" ]]; then
            ss_link_qr
        elif [[ ${obfs_suffix} = "compatible" ]]; then
            ss_link_qr
        fi
    elif [[ ${protocol_suffix} = "compatible" ]]; then
        if [[ ${obfs_suffix} = "compatible" ]] || [[ ${obfs_suffix} = "plain" ]]; then
            ss_link_qr
        fi
    fi
    ssr_link_qr
}

View_User(){
    SSR_installation_status
    Get_IP
    Get_User
    now_mode="$(${jq_file} '.port_password' ${config_user_file})"
    [[ -z ${protocol_param} || ${protocol_param} == "null" ]] && protocol_param="0(无限)"
    if [[ "${now_mode}" = "null" ]]; then
        ss_ssr_determine
        clear
        echo "===================================================" && echo
        echo -e " ShadowsocksR账号 配置信息：" && echo
        echo -e " I  P\t    : ${Green_font_prefix}${ip}${Font_color_suffix}"
        echo -e " 端口\t    : ${Green_font_prefix}${port}${Font_color_suffix}"
        echo -e " 密码\t    : ${Green_font_prefix}${password}${Font_color_suffix}"
        echo -e " 加密\t    : ${Green_font_prefix}${method}${Font_color_suffix}"
        echo -e " 协议\t    : ${Red_font_prefix}${protocol}${Font_color_suffix}"
        echo -e " 混淆\t    : ${Red_font_prefix}${obfs}${Font_color_suffix}"
        echo -e " 设备数限制 : ${Green_font_prefix}${protocol_param}${Font_color_suffix}"
        echo -e " 单线程限速 : ${Green_font_prefix}${speed_limit_per_con} KB/S${Font_color_suffix}"
        echo -e " 端口总限速 : ${Green_font_prefix}${speed_limit_per_user} KB/S${Font_color_suffix}"
        echo -e "${ss_link}"
        echo -e "${ssr_link}"
        echo -e " ${Green_font_prefix} 提示: ${Font_color_suffix}\n 在浏览器中，打开二维码链接，就可以看到二维码图片。\n 协议和混淆后面的[ _compatible ]，指的是兼容原版协议/混淆。"
        echo && echo "==================================================="
    else
        user_total="$(${jq_file} '.port_password | length' ${config_user_file})"
        [[ ${user_total} = "0" ]] && echo -e "${Error} 没有发现 多端口用户，请检查 !" && exit 1
        clear
        echo "===================================================" && echo
        echo -e " ShadowsocksR账号 配置信息：" && echo
        echo -e " I  P\t    : ${Green_font_prefix}${ip}${Font_color_suffix}"
        echo -e " 加密\t    : ${Green_font_prefix}${method}${Font_color_suffix}"
        echo -e " 协议\t    : ${Red_font_prefix}${protocol}${Font_color_suffix}"
        echo -e " 混淆\t    : ${Red_font_prefix}${obfs}${Font_color_suffix}"
        echo -e " 设备数限制 : ${Green_font_prefix}${protocol_param}${Font_color_suffix}"
        echo -e " 单线程限速 : ${Green_font_prefix}${speed_limit_per_con} KB/S${Font_color_suffix}"
        echo -e " 端口总限速 : ${Green_font_prefix}${speed_limit_per_user} KB/S${Font_color_suffix}" && echo
        mapfile -t users < <(${jq_file} -r '.port_password | to_entries[] | "\(.key) \(.value)"' ${config_user_file})
        for line in "${users[@]}"; do
            port="${line%% *}"
            password="${line#* }"
            ss_ssr_determine
            echo -e ${Separator_1}
            echo -e " 端口\t    : ${Green_font_prefix}${port}${Font_color_suffix}"
            echo -e " 密码\t    : ${Green_font_prefix}${password}${Font_color_suffix}"
            echo -e "${ss_link}"
            echo -e "${ssr_link}"
        done
        echo -e " ${Green_font_prefix} 提示: ${Font_color_suffix}\n 在浏览器中，打开二维码链接，就可以看到二维码图片。\n 协议和混淆后面的[ _compatible ]，指的是兼容原版协议/混淆。"
        echo && echo "==================================================="
    fi
}

Set_config_port(){
    while true; do
        echo -e "请输入要设置的ShadowsocksR账号 端口"
        stty erase '^H' && read -r -p "(默认: 2333):" ssr_port
        [[ -z "$ssr_port" ]] && ssr_port="2333"
        if [[ "$ssr_port" =~ ^[0-9]+$ ]] && [[ ${ssr_port} -ge 1 ]] && [[ ${ssr_port} -le 65535 ]]; then
            echo && echo ${Separator_1} && echo -e "        端口 : ${Green_font_prefix}${ssr_port}${Font_color_suffix}" && echo ${Separator_1} && echo
            break
        else
            echo -e "${Error} 请输入正确的数字(1-65535)"
        fi
    done
}

Set_config_password(){
    echo "请输入要设置的ShadowsocksR账号 密码"
    stty erase '^H' && read -r -p "(默认: doub.io):" ssr_password
    [[ -z "${ssr_password}" ]] && ssr_password="doub.io"
    echo && echo ${Separator_1} && echo -e "        密码 : ${Green_font_prefix}${ssr_password}${Font_color_suffix}" && echo ${Separator_1} && echo
}

Set_config_method(){
    echo -e "请选择要设置的ShadowsocksR账号 加密方式
 ${Green_font_prefix}1.${Font_color_suffix} rc4-md5
 ${Green_font_prefix}2.${Font_color_suffix} aes-128-ctr
 ${Green_font_prefix}3.${Font_color_suffix} aes-256-ctr
 ${Green_font_prefix}4.${Font_color_suffix} aes-256-cfb
 ${Green_font_prefix}5.${Font_color_suffix} aes-256-cfb8
 ${Green_font_prefix}6.${Font_color_suffix} camellia-256-cfb
 ${Green_font_prefix}7.${Font_color_suffix} chacha20
 ${Green_font_prefix}8.${Font_color_suffix} chacha20-ietf
注意：chacha20-*系列加密方式，需要额外安装依赖 libsodium。" && echo
    stty erase '^H' && read -r -p "(默认: 2. aes-128-ctr):" ssr_method
    [[ -z "${ssr_method}" ]] && ssr_method="2"
    case "${ssr_method}" in
        1) ssr_method="rc4-md5" ;;
        2) ssr_method="aes-128-ctr" ;;
        3) ssr_method="aes-256-ctr" ;;
        4) ssr_method="aes-256-cfb" ;;
        5) ssr_method="aes-256-cfb8" ;;
        6) ssr_method="camellia-256-cfb" ;;
        7) ssr_method="chacha20" ;;
        8) ssr_method="chacha20-ietf" ;;
        *) ssr_method="aes-128-ctr" ;;
    esac
    echo && echo ${Separator_1} && echo -e "        加密 : ${Green_font_prefix}${ssr_method}${Font_color_suffix}" && echo ${Separator_1} && echo
}

Set_config_protocol(){
    echo -e "请选择要设置的ShadowsocksR账号 协议插件
 ${Green_font_prefix}1.${Font_color_suffix} origin
 ${Green_font_prefix}2.${Font_color_suffix} auth_sha1_v4
 ${Green_font_prefix}3.${Font_color_suffix} auth_aes128_md5
 ${Green_font_prefix}4.${Font_color_suffix} auth_aes128_sha1" && echo
    stty erase '^H' && read -r -p "(默认: 2. auth_sha1_v4):" ssr_protocol
    [[ -z "${ssr_protocol}" ]] && ssr_protocol="2"
    case "${ssr_protocol}" in
        1) ssr_protocol="origin" ;;
        2) ssr_protocol="auth_sha1_v4" ;;
        3) ssr_protocol="auth_aes128_md5" ;;
        4) ssr_protocol="auth_aes128_sha1" ;;
        *) ssr_protocol="auth_sha1_v4" ;;
    esac
    echo && echo ${Separator_1} && echo -e "        协议 : ${Green_font_prefix}${ssr_protocol}${Font_color_suffix}" && echo ${Separator_1} && echo
    if [[ ${ssr_protocol} != "origin" && ${ssr_protocol} == "auth_sha1_v4" ]]; then
        stty erase '^H' && read -r -p "是否设置 协议插件兼容原版(_compatible)？[Y/n]" ssr_protocol_yn
        [[ -z "${ssr_protocol_yn}" ]] && ssr_protocol_yn="y"
        [[ $ssr_protocol_yn == [Yy] ]] && ssr_protocol="${ssr_protocol}_compatible"
        echo
    fi
}

Set_config_obfs(){
    echo -e "请选择要设置的ShadowsocksR账号 混淆插件
 ${Green_font_prefix}1.${Font_color_suffix} plain
 ${Green_font_prefix}2.${Font_color_suffix} http_simple
 ${Green_font_prefix}3.${Font_color_suffix} http_post
 ${Green_font_prefix}4.${Font_color_suffix} random_head
 ${Green_font_prefix}5.${Font_color_suffix} tls1.2_ticket_auth" && echo
    stty erase '^H' && read -r -p "(默认: 5. tls1.2_ticket_auth):" ssr_obfs
    [[ -z "${ssr_obfs}" ]] && ssr_obfs="5"
    case "${ssr_obfs}" in
        1) ssr_obfs="plain" ;;
        2) ssr_obfs="http_simple" ;;
        3) ssr_obfs="http_post" ;;
        4) ssr_obfs="random_head" ;;
        5) ssr_obfs="tls1.2_ticket_auth" ;;
        *) ssr_obfs="tls1.2_ticket_auth" ;;
    esac
    echo && echo ${Separator_1} && echo -e "        混淆 : ${Green_font_prefix}${ssr_obfs}${Font_color_suffix}" && echo ${Separator_1} && echo
    if [[ ${ssr_obfs} != "plain" ]]; then
        stty erase '^H' && read -r -p "是否设置 混淆插件兼容原版(_compatible)？[Y/n]" ssr_obfs_yn
        [[ -z "${ssr_obfs_yn}" ]] && ssr_obfs_yn="y"
        [[ $ssr_obfs_yn == [Yy] ]] && ssr_obfs="${ssr_obfs}_compatible"
        echo
    fi
}

read_number_range(){
    local prompt="$1" default="$2" min="$3" max="$4" var_name="$5" unit="$6"
    local val
    while true; do
        echo -e "$prompt"
        stty erase '^H' && read -r -p "(默认: ${default}):" val
        if [[ -z "$val" ]]; then
            val="$default"
            [[ "$default" == "无限" ]] && val=0
            printf -v "$var_name" '%s' "$val"
            echo
            break
        fi
        if [[ "$val" =~ ^[0-9]+$ ]] && [[ ${val} -ge ${min} ]] && [[ ${val} -le ${max} ]]; then
            printf -v "$var_name" '%s' "$val"
            echo && echo ${Separator_1} && echo -e "        ${unit} : ${Green_font_prefix}${val}${Font_color_suffix}" && echo ${Separator_1} && echo
            break
        else
            echo -e "${Error} 请输入正确的数字(${min}-${max})"
        fi
    done
}

Set_config_protocol_param(){
    echo -e "请输入要设置的ShadowsocksR账号 欲限制的设备数 (${Green_font_prefix}auth_* 系列协议不兼容原版才有效${Font_color_suffix})"
    echo -e "${Tip} 设备数限制：每个端口同一时间能链接的客户端数量，建议最少 2 个。"
    read_number_range "" "无限" 1 9999 ssr_protocol_param "设备数限制"
    [[ "${ssr_protocol_param}" == "0" ]] && ssr_protocol_param=""
}
Set_config_speed_limit_per_con(){
    echo -e "${Tip} 单线程限速：每个端口单线程的限速上限，多线程即无效。"
    read_number_range "请输入要设置的每个端口 单线程 限速上限(单位：KB/S)" "无限" 1 131072 ssr_speed_limit_per_con "单线程限速"
}
Set_config_speed_limit_per_user(){
    echo -e "${Tip} 端口总限速：每个端口总速度限速上限。"
    read_number_range "请输入要设置的每个端口 总速度 限速上限(单位：KB/S)" "无限" 1 131072 ssr_speed_limit_per_user "端口总限速"
}

Set_config_all(){
    Set_config_port
    Set_config_password
    Set_config_method
    Set_config_protocol
    Set_config_obfs
    Set_config_protocol_param
    Set_config_speed_limit_per_con
    Set_config_speed_limit_per_user
}

jq_write(){
    local filter="$1"
    local tmp
    tmp="$(mktemp)"
    ${jq_file} "$filter" "${config_user_file}" > "$tmp" && mv "$tmp" "${config_user_file}"
}

Modify_config_port(){ jq_write ".server_port = ${ssr_port}"; }
Modify_config_password(){ jq_write ".password = \"${ssr_password}\""; }
Modify_config_method(){ jq_write ".method = \"${ssr_method}\""; }
Modify_config_protocol(){ jq_write ".protocol = \"${ssr_protocol}\""; }
Modify_config_obfs(){ jq_write ".obfs = \"${ssr_obfs}\""; }
Modify_config_protocol_param(){ jq_write ".protocol_param = \"${ssr_protocol_param}\""; }
Modify_config_speed_limit_per_con(){ jq_write ".speed_limit_per_con = ${ssr_speed_limit_per_con}"; }
Modify_config_speed_limit_per_user(){ jq_write ".speed_limit_per_user = ${ssr_speed_limit_per_user}"; }
Modify_config_all(){
    Modify_config_port
    Modify_config_password
    Modify_config_method
    Modify_config_protocol
    Modify_config_obfs
    Modify_config_protocol_param
    Modify_config_speed_limit_per_con
    Modify_config_speed_limit_per_user
}

Write_configuration(){
    mkdir -p "${config_folder}"
    cat > ${config_user_file} <<EOF_CONF
{
    "server": "0.0.0.0",
    "server_ipv6": "::",
    "server_port": ${ssr_port},
    "local_address": "127.0.0.1",
    "local_port": 1080,
    "password": "${ssr_password}",
    "method": "${ssr_method}",
    "protocol": "${ssr_protocol}",
    "protocol_param": "${ssr_protocol_param}",
    "obfs": "${ssr_obfs}",
    "obfs_param": "",
    "speed_limit_per_con": ${ssr_speed_limit_per_con},
    "speed_limit_per_user": ${ssr_speed_limit_per_user},
    "additional_ports" : {},
    "timeout": 120,
    "udp_timeout": 60,
    "dns_ipv6": false,
    "connect_verbose_info": 0,
    "redirect": "",
    "fast_open": false
}
EOF_CONF
}

Write_configuration_many(){
    mkdir -p "${config_folder}"
    cat > ${config_user_file} <<EOF_CONF
{
    "server": "0.0.0.0",
    "server_ipv6": "::",
    "local_address": "127.0.0.1",
    "local_port": 1080,
    "port_password": {
        "${ssr_port}": "${ssr_password}"
    },
    "method": "${ssr_method}",
    "protocol": "${ssr_protocol}",
    "protocol_param": "${ssr_protocol_param}",
    "obfs": "${ssr_obfs}",
    "obfs_param": "",
    "speed_limit_per_con": ${ssr_speed_limit_per_con},
    "speed_limit_per_user": ${ssr_speed_limit_per_user},
    "additional_ports" : {},
    "timeout": 120,
    "udp_timeout": 60,
    "dns_ipv6": false,
    "connect_verbose_info": 0,
    "redirect": "",
    "fast_open": false
}
EOF_CONF
}

Check_python(){
    if command_exists python2; then
        ln -sf "$(command -v python2)" /usr/local/bin/python >/dev/null 2>&1 || true
        return 0
    fi
    if command_exists python; then
        return 0
    fi
    echo -e "${Info} 没有发现 Python，开始安装..."
    if [[ ${release} == "rhel" ]]; then
        pkg_install python2 || pkg_install python3
    else
        pkg_install python2 || pkg_install python-is-python3 python3
    fi
    if command_exists python2; then
        ln -sf "$(command -v python2)" /usr/local/bin/python >/dev/null 2>&1 || true
    elif command_exists python3 && ! command_exists python; then
        ln -sf "$(command -v python3)" /usr/local/bin/python >/dev/null 2>&1 || true
    fi
}

Rhel_pkg(){ pkg_install vim git wget curl ca-certificates net-tools iproute iproute-tc tar make gcc autoconf automake libtool; }
Debian_apt(){ pkg_install vim git wget curl ca-certificates net-tools iproute2 tar make gcc autoconf automake libtool build-essential; }

Installation_dependency(){
    pkg_update
    if [[ ${release} == "rhel" ]]; then Rhel_pkg; else Debian_apt; fi
    Check_python
    [[ -f /usr/share/zoneinfo/Asia/Shanghai ]] && cp -f /usr/share/zoneinfo/Asia/Shanghai /etc/localtime || true
}

Download_SSR(){
    cd /usr/local
    git clone https://github.com/gexqin/shadowsocksr
    [[ ! -e ${ssr_folder} ]] && echo -e "${Error} ShadowsocksR服务端 下载失败 !" && exit 1
    rm -rf "${config_folder}"
    mkdir -p "${config_folder}"
    echo -e "${Info} ShadowsocksR服务端 下载完成 !"
}

Service_SSR(){
    if ! wget https://raw.githubusercontent.com/gexqin/shadowsocksr/main/ssr -O /etc/init.d/ssr; then
        echo -e "${Error} ShadowsocksR服务 管理脚本下载失败 !" && exit 1
    fi
    chmod +x /etc/init.d/ssr
    write_systemd_service
    service_enable
    echo -e "${Info} ShadowsocksR服务 管理脚本下载完成 !"
}

JQ_install(){
    if [[ ! -e ${jq_file} ]]; then
        if [[ ${bit} = "x86_64" ]]; then
            wget "https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64" -O ${jq_file}
        else
            wget "https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux32" -O ${jq_file}
        fi
        [[ ! -e ${jq_file} ]] && echo -e "${Error} JQ解析器 下载失败，请检查 !" && exit 1
        chmod +x ${jq_file}
        echo -e "${Info} JQ解析器 安装完成，继续..."
    else
        echo -e "${Info} JQ解析器 已安装，继续..."
    fi
}

Install_SSR(){
    [[ -e ${config_user_file} ]] && echo -e "${Error} ShadowsocksR 配置文件已存在，请先卸载或备份 !" && exit 1
    [[ -e ${ssr_folder} ]] && echo -e "${Error} ShadowsocksR 文件夹已存在，请先卸载或备份 !" && exit 1
    echo -e "${Info} 开始设置 ShadowsocksR账号配置..."
    Set_config_all
    echo -e "${Info} 开始安装/配置 ShadowsocksR依赖..."
    Installation_dependency
    echo -e "${Info} 开始下载/安装 ShadowsocksR文件..."
    Download_SSR
    echo -e "${Info} 开始下载/安装 ShadowsocksR服务脚本..."
    Service_SSR
    echo -e "${Info} 开始下载/安装 JSON解析器 JQ..."
    JQ_install
    echo -e "${Info} 开始写入 ShadowsocksR配置文件..."
    Write_configuration
    echo -e "${Info} 开始设置防火墙..."
    Add_iptables
    Save_iptables
    echo -e "${Info} 所有步骤安装完毕，开始启动 ShadowsocksR服务端..."
    Start_SSR
}

Update_SSR(){
    SSR_installation_status
    cd ${ssr_folder}
    git pull
    Restart_SSR
}

Uninstall_SSR(){
    [[ ! -e ${config_user_file} ]] && [[ ! -e ${ssr_folder} ]] && echo -e "${Error} 没有安装 ShadowsocksR，请检查 !" && exit 1
    now_mode="$(${jq_file} '.port_password' ${config_user_file} 2>/dev/null || echo null)"
    echo "确定要 卸载ShadowsocksR？[y/N]" && echo
    stty erase '^H' && read -r -p "(默认: n):" unyn
    [[ -z ${unyn} ]] && unyn="n"
    if [[ ${unyn} == [Yy] ]]; then
        check_pid
        [[ -n "${PID}" ]] && kill -9 ${PID} 2>/dev/null || true
        if [[ "${now_mode}" = "null" ]]; then
            port="$(${jq_file} '.server_port' ${config_user_file} 2>/dev/null || true)"
            Del_iptables
        else
            mapfile -t ports < <(${jq_file} -r '.port_password | keys[]' ${config_user_file})
            for port in "${ports[@]}"; do Del_iptables; done
        fi
        Save_iptables
        service_disable
        rm -rf ${ssr_folder} ${config_folder} /etc/init.d/ssr /etc/systemd/system/ssr.service
        command_exists systemctl && systemctl daemon-reload >/dev/null 2>&1 || true
        echo && echo " ShadowsocksR 卸载完成 !" && echo
    else
        echo && echo " 卸载已取消..." && echo
    fi
}

Check_Libsodium_ver(){
    echo -e "${Info} 开始获取 libsodium 最新版本..."
    Libsodiumr_ver="$(wget -qO- https://download.libsodium.org/libsodium/releases/LATEST.tar.gz 2>/dev/null | grep "<title>" | perl -e 'while($_=<>){ /Release (.*) · jedisct1/; print $1;}' || true)"
    [[ -z ${Libsodiumr_ver} ]] && Libsodiumr_ver=${Libsodiumr_ver_backup}
    echo -e "${Info} libsodium 最新版本为 ${Green_font_prefix}${Libsodiumr_ver}${Font_color_suffix} !"
}

Install_Libsodium(){
    [[ -e ${Libsodiumr_file} ]] && echo -e "${Error} libsodium 已安装 !" && exit 1
    echo -e "${Info} libsodium 未安装，开始安装..."
    Check_Libsodium_ver
    pkg_update
    if [[ ${release} == "rhel" ]]; then
        Rhel_pkg
    else
        Debian_apt
    fi
    wget -N https://download.libsodium.org/libsodium/releases/LATEST.tar.gz
    tar -xzf LATEST.tar.gz && cd libsodium-stable
    ./configure --disable-maintainer-mode && make -j2 && make install
    echo /usr/local/lib > /etc/ld.so.conf.d/usr_local_lib.conf
    ldconfig
    cd .. && rm -rf LATEST.tar.gz libsodium-stable
    [[ ! -e ${Libsodiumr_file} ]] && echo -e "${Error} libsodium 安装失败 !" && exit 1
    echo && echo -e "${Info} libsodium 安装成功 !" && echo
}

connection_rows(){
    local port_filter="$1"
    if command_exists ss; then
        ss -Hantp 2>/dev/null | grep ESTAB | grep -E 'python|ssserver|server.py' | grep ":${port_filter} " || true
    elif command_exists netstat; then
        netstat -anp 2>/dev/null | grep ESTABLISHED | grep -E 'python|ssserver|server.py' | grep "${port_filter}" || true
    fi
}

View_user_connection_info(){
    SSR_installation_status
    now_mode="$(${jq_file} '.port_password' ${config_user_file})"
    if [[ "${now_mode}" = "null" ]]; then
        now_mode="单端口"
        user_port="$(${jq_file} '.server_port' ${config_user_file})"
        rows="$(connection_rows "${user_port}")"
        user_IP="$(echo "${rows}" | awk '{print $5}' | sed 's/\[//g;s/\]//g' | awk -F ':' '{print $1}' | sort -u | sed '/^$/d')"
        user_IP_total="$(echo "${user_IP}" | sed '/^$/d' | wc -l)"
        echo -e "当前模式: ${Green_font_prefix}${now_mode}${Font_color_suffix}"
        echo -e "端口: ${Green_font_prefix}${user_port}${Font_color_suffix}, 链接IP总数: ${Green_font_prefix}${user_IP_total}${Font_color_suffix}, 当前链接IP: ${Green_font_prefix}${user_IP}${Font_color_suffix}"
    else
        now_mode="多端口"
        mapfile -t ports < <(${jq_file} -r '.port_password | keys[]' ${config_user_file})
        user_total="${#ports[@]}"
        echo -e "当前模式: ${Green_font_prefix}${now_mode}${Font_color_suffix} ，用户总数: ${Green_font_prefix}${user_total}${Font_color_suffix}"
        for user_port in "${ports[@]}"; do
            rows="$(connection_rows "${user_port}")"
            user_IP="$(echo "${rows}" | awk '{print $5}' | sed 's/\[//g;s/\]//g' | awk -F ':' '{print $1}' | sort -u | sed '/^$/d')"
            user_IP_total="$(echo "${user_IP}" | sed '/^$/d' | wc -l)"
            echo -e "端口: ${Green_font_prefix}${user_port}${Font_color_suffix}, 链接IP总数: ${Green_font_prefix}${user_IP_total}${Font_color_suffix}, 当前链接IP: ${Green_font_prefix}${user_IP}${Font_color_suffix}"
        done
    fi
}

List_multi_port_user(){
    user_total="$(${jq_file} '.port_password | length' ${config_user_file})"
    [[ ${user_total} = "0" ]] && echo -e "${Error} 没有发现 多端口用户，请检查 !" && exit 1
    echo && echo -e "用户总数 ${Green_font_prefix}${user_total}${Font_color_suffix}"
    ${jq_file} -r '.port_password | to_entries[] | "端口: \(.key) 密码: \(.value)"' ${config_user_file}
}

Add_multi_port_user(){
    Set_config_port
    Set_config_password
    jq_write ".port_password[\"${ssr_port}\"] = \"${ssr_password}\""
    Add_iptables
    Save_iptables
    echo -e "${Info} 多端口用户添加完成 ${Green_font_prefix}[端口: ${ssr_port} , 密码: ${ssr_password}]${Font_color_suffix} "
}

Modify_multi_port_user(){
    List_multi_port_user
    echo && echo -e "请输入要修改的用户端口"
    stty erase '^H' && read -r -p "(默认: 取消):" modify_user_port
    [[ -z "${modify_user_port}" ]] && echo -e "已取消..." && exit 1
    if ${jq_file} -e ".port_password[\"${modify_user_port}\"]" ${config_user_file} >/dev/null; then
        port=${modify_user_port}
        password="$(${jq_file} -r ".port_password[\"${modify_user_port}\"]" ${config_user_file})"
        Set_config_port
        Set_config_password
        jq_write "del(.port_password[\"${port}\"]) | .port_password[\"${ssr_port}\"] = \"${ssr_password}\""
        Del_iptables
        Add_iptables
        Save_iptables
        echo -e "${Info} 多端口用户修改完成 ${Green_font_prefix}[旧: ${modify_user_port} ${password} , 新: ${ssr_port} ${ssr_password}]${Font_color_suffix} "
    else
        echo "${Error} 请输入正确的端口 !" && exit 1
    fi
}

Del_multi_port_user(){
    List_multi_port_user
    user_total="$(${jq_file} '.port_password | length' ${config_user_file})"
    [[ "${user_total}" = "1" ]] && echo -e "${Error} 多端口用户仅剩 1个，不能删除 !" && exit 1
    echo -e "请输入要删除的用户端口"
    stty erase '^H' && read -r -p "(默认: 取消):" del_user_port
    [[ -z "${del_user_port}" ]] && echo -e "已取消..." && exit 1
    if ${jq_file} -e ".port_password[\"${del_user_port}\"]" ${config_user_file} >/dev/null; then
        port=${del_user_port}
        Del_iptables
        Save_iptables
        jq_write "del(.port_password[\"${del_user_port}\"])"
        echo -e "${Info} 多端口用户删除完成 ${Green_font_prefix}${del_user_port}${Font_color_suffix} "
    else
        echo "${Error} 请输入正确的端口 !" && exit 1
    fi
}

Modify_Config(){
    SSR_installation_status
    now_mode="$(${jq_file} '.port_password' ${config_user_file})"
    if [[ "${now_mode}" = "null" ]]; then
        echo && echo -e "当前模式: 单端口，你要做什么？
 ${Green_font_prefix}1.${Font_color_suffix} 修改 用户端口
 ${Green_font_prefix}2.${Font_color_suffix} 修改 用户密码
 ${Green_font_prefix}3.${Font_color_suffix} 修改 加密方式
 ${Green_font_prefix}4.${Font_color_suffix} 修改 协议插件
 ${Green_font_prefix}5.${Font_color_suffix} 修改 混淆插件
 ${Green_font_prefix}6.${Font_color_suffix} 修改 设备数限制
 ${Green_font_prefix}7.${Font_color_suffix} 修改 单线程限速
 ${Green_font_prefix}8.${Font_color_suffix} 修改 端口总限速
 ${Green_font_prefix}9.${Font_color_suffix} 修改 全部配置" && echo
        stty erase '^H' && read -r -p "(默认: 取消):" ssr_modify
        [[ -z "${ssr_modify}" ]] && echo "已取消..." && exit 1
        Get_User
        case "${ssr_modify}" in
            1) Set_config_port; Modify_config_port; Add_iptables; Del_iptables; Save_iptables ;;
            2) Set_config_password; Modify_config_password ;;
            3) Set_config_method; Modify_config_method ;;
            4) Set_config_protocol; Modify_config_protocol ;;
            5) Set_config_obfs; Modify_config_obfs ;;
            6) Set_config_protocol_param; Modify_config_protocol_param ;;
            7) Set_config_speed_limit_per_con; Modify_config_speed_limit_per_con ;;
            8) Set_config_speed_limit_per_user; Modify_config_speed_limit_per_user ;;
            9) Set_config_all; Modify_config_all ;;
            *) echo -e "${Error} 请输入正确的数字(1-9)" && exit 1 ;;
        esac
    else
        echo && echo -e "当前模式: 多端口，你要做什么？
 ${Green_font_prefix}1.${Font_color_suffix} 添加 用户配置
 ${Green_font_prefix}2.${Font_color_suffix} 删除 用户配置
 ${Green_font_prefix}3.${Font_color_suffix} 修改 用户配置
——————————
 ${Green_font_prefix}4.${Font_color_suffix} 修改 加密方式
 ${Green_font_prefix}5.${Font_color_suffix} 修改 协议插件
 ${Green_font_prefix}6.${Font_color_suffix} 修改 混淆插件
 ${Green_font_prefix}7.${Font_color_suffix} 修改 设备数限制
 ${Green_font_prefix}8.${Font_color_suffix} 修改 单线程限速
 ${Green_font_prefix}9.${Font_color_suffix} 修改 端口总限速
${Green_font_prefix}10.${Font_color_suffix} 修改 全部配置" && echo
        stty erase '^H' && read -r -p "(默认: 取消):" ssr_modify
        [[ -z "${ssr_modify}" ]] && echo "已取消..." && exit 1
        Get_User
        case "${ssr_modify}" in
            1) Add_multi_port_user ;;
            2) Del_multi_port_user ;;
            3) Modify_multi_port_user ;;
            4) Set_config_method; Modify_config_method ;;
            5) Set_config_protocol; Modify_config_protocol ;;
            6) Set_config_obfs; Modify_config_obfs ;;
            7) Set_config_protocol_param; Modify_config_protocol_param ;;
            8) Set_config_speed_limit_per_con; Modify_config_speed_limit_per_con ;;
            9) Set_config_speed_limit_per_user; Modify_config_speed_limit_per_user ;;
            10) Set_config_method; Set_config_protocol; Set_config_obfs; Set_config_protocol_param; Set_config_speed_limit_per_con; Set_config_speed_limit_per_user; Modify_config_method; Modify_config_protocol; Modify_config_obfs; Modify_config_protocol_param; Modify_config_speed_limit_per_con; Modify_config_speed_limit_per_user ;;
            *) echo -e "${Error} 请输入正确的数字" && exit 1 ;;
        esac
    fi
    Restart_SSR
}

Manually_Modify_Config(){
    SSR_installation_status
    now_mode="$(${jq_file} '.port_password' ${config_user_file})"
    port="$(${jq_file} '.server_port' ${config_user_file} 2>/dev/null || true)"
    vi ${config_user_file}
    if [[ "${now_mode}" = "null" ]]; then
        ssr_port="$(${jq_file} '.server_port' ${config_user_file})"
        Del_iptables
        Add_iptables
        Save_iptables
    fi
    Restart_SSR
}

Port_mode_switching(){
    SSR_installation_status
    now_mode="$(${jq_file} '.port_password' ${config_user_file})"
    if [[ "${now_mode}" = "null" ]]; then
        echo && echo -e "       当前模式: ${Green_font_prefix}单端口${Font_color_suffix}" && echo
        echo -e "确定要切换为 多端口模式？[y/N]"
        stty erase '^H' && read -r -p "(默认: n):" mode_yn
        [[ -z ${mode_yn} ]] && mode_yn="n"
        if [[ ${mode_yn} == [Yy] ]]; then
            port="$(${jq_file} '.server_port' ${config_user_file})"
            Set_config_all
            Write_configuration_many
            Del_iptables
            Add_iptables
            Save_iptables
            Restart_SSR
        else
            echo && echo "  已取消..." && echo
        fi
    else
        echo && echo -e "       当前模式: ${Green_font_prefix}多端口${Font_color_suffix}" && echo
        echo -e "确定要切换为 单端口模式？[y/N]"
        stty erase '^H' && read -r -p "(默认: n):" mode_yn
        [[ -z ${mode_yn} ]] && mode_yn="n"
        if [[ ${mode_yn} == [Yy] ]]; then
            mapfile -t ports < <(${jq_file} -r '.port_password | keys[]' ${config_user_file})
            for port in "${ports[@]}"; do Del_iptables; done
            Set_config_all
            Write_configuration
            Add_iptables
            Save_iptables
            Restart_SSR
        else
            echo && echo "  已取消..." && echo
        fi
    fi
}

Start_SSR(){
    SSR_installation_status
    check_pid
    [[ -n ${PID} ]] && echo -e "${Error} ShadowsocksR 正在运行 !" && exit 1
    service_start
    View_User
}
Stop_SSR(){
    SSR_installation_status
    check_pid
    [[ -z ${PID} ]] && echo -e "${Error} ShadowsocksR 未运行 !" && exit 1
    service_stop
}
Restart_SSR(){
    SSR_installation_status
    check_pid
    if [[ -n ${PID} ]]; then service_stop || true; fi
    service_start
    View_User
}
View_Log(){
    SSR_installation_status
    [[ ! -e ${ssr_log_file} ]] && echo -e "${Error} ShadowsocksR日志文件不存在 !" && exit 1
    echo && echo -e "${Tip} 按 ${Red_font_prefix}Ctrl+C${Font_color_suffix} 终止查看日志" && echo
    tail -f ${ssr_log_file}
}

BanBTPTSPAM(){
    echo -e "${Tip} 为安全起见，已禁用直接 wget | bash 执行远程脚本。"
    echo -e "请手动审计脚本后再执行："
    echo "wget -O Get_Out_Spam.sh https://raw.githubusercontent.com/ToyoDAdoubi/doubi/master/Get_Out_Spam.sh"
    echo "less Get_Out_Spam.sh"
    echo "bash Get_Out_Spam.sh"
}
Other_functions(){
    echo && echo -e "你要做什么？
  ${Green_font_prefix}1.${Font_color_suffix} 防火墙iptables 封禁 BT/PT/SPAM" && echo
    stty erase '^H' && read -r -p "(默认: 取消):" other_num
    [[ -z "${other_num}" ]] && echo "已取消..." && exit 1
    case "${other_num}" in
        1) BanBTPTSPAM ;;
        *) echo -e "${Error} 请输入正确的数字(1-1)" && exit 1 ;;
    esac
}

menu_status(){
    if [[ -e ${config_user_file} ]]; then
        check_pid
        if [[ -n "${PID}" ]]; then
            echo -e " 当前状态: ${Green_font_prefix}已安装${Font_color_suffix} 并 ${Green_font_prefix}已启动${Font_color_suffix}"
        else
            echo -e " 当前状态: ${Green_font_prefix}已安装${Font_color_suffix} 但 ${Red_font_prefix}未启动${Font_color_suffix}"
        fi
        now_mode="$(${jq_file} '.port_password' ${config_user_file} 2>/dev/null || echo null)"
        if [[ "${now_mode}" = "null" ]]; then
            echo -e " 当前模式: ${Green_font_prefix}单端口${Font_color_suffix}"
        else
            echo -e " 当前模式: ${Green_font_prefix}多端口${Font_color_suffix}"
        fi
    else
        echo -e " 当前状态: ${Red_font_prefix}未安装${Font_color_suffix}"
    fi
}

main(){
    check_root
    check_sys
    [[ ${release} != "debian" ]] && [[ ${release} != "ubuntu" ]] && [[ ${release} != "rhel" ]] && echo -e "${Error} 本脚本不支持当前系统 ${release} !" && exit 1
    echo -e "  请输入一个数字来选择菜单选项

  ${Green_font_prefix}1.${Font_color_suffix} 安装 ShadowsocksR
  ${Green_font_prefix}2.${Font_color_suffix} 更新 ShadowsocksR
  ${Green_font_prefix}3.${Font_color_suffix} 卸载 ShadowsocksR
  ${Green_font_prefix}4.${Font_color_suffix} 安装 libsodium(chacha20)
————————————
  ${Green_font_prefix}5.${Font_color_suffix} 查看 账号信息
  ${Green_font_prefix}6.${Font_color_suffix} 显示 连接信息
  ${Green_font_prefix}7.${Font_color_suffix} 修改 用户配置
  ${Green_font_prefix}8.${Font_color_suffix} 手动 修改配置
  ${Green_font_prefix}9.${Font_color_suffix} 切换 端口模式
————————————
 ${Green_font_prefix}10.${Font_color_suffix} 启动 ShadowsocksR
 ${Green_font_prefix}11.${Font_color_suffix} 停止 ShadowsocksR
 ${Green_font_prefix}12.${Font_color_suffix} 重启 ShadowsocksR
 ${Green_font_prefix}13.${Font_color_suffix} 查看 ShadowsocksR 日志
————————————
 ${Green_font_prefix}14.${Font_color_suffix} 其他功能

  "
    menu_status
    echo && stty erase '^H' && read -r -p "请输入数字(1-14)：" num
    case "$num" in
        1) Install_SSR ;;
        2) Update_SSR ;;
        3) Uninstall_SSR ;;
        4) Install_Libsodium ;;
        5) View_User ;;
        6) View_user_connection_info ;;
        7) Modify_Config ;;
        8) Manually_Modify_Config ;;
        9) Port_mode_switching ;;
        10) Start_SSR ;;
        11) Stop_SSR ;;
        12) Restart_SSR ;;
        13) View_Log ;;
        14) Other_functions ;;
        *) echo -e "${Error} 请输入正确的数字(1-14)" ;;
    esac
}

main "$@"

