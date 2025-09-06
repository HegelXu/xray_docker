#!/bin/bash

# Xray Docker Reality 部署脚本
# 作者: GitHub Copilot
# 日期: 2025-09-06

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_blue() {
    echo -e "${BLUE}[DEPLOY]${NC} $1"
}

# 检查是否为 root 用户
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_warn "检测到 root 用户，建议使用普通用户运行此脚本"
    fi
}

# 检查系统环境
check_system() {
    log_info "检查系统环境..."
    
    # 检查操作系统
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$NAME
        log_info "操作系统: $OS"
    else
        log_error "无法识别操作系统"
        exit 1
    fi
    
    # 检查网络连接
    if ! ping -c 1 google.com &> /dev/null; then
        log_warn "网络连接可能存在问题，请检查网络设置"
    fi
}

# 检查 Docker 是否已安装
check_docker() {
    if command -v docker &> /dev/null; then
        log_info "Docker 已安装: $(docker --version)"
        
        # 检查 Docker 是否正在运行
        if ! docker info &> /dev/null; then
            log_error "Docker 未运行，请启动 Docker 服务："
            echo "sudo systemctl start docker"
            exit 1
        fi
        
        # 检查用户是否有 Docker 权限
        if ! docker ps &> /dev/null; then
            log_error "当前用户没有 Docker 权限，请运行："
            echo "sudo usermod -aG docker \$USER"
            echo "然后重新登录或运行: newgrp docker"
            exit 1
        fi
        
        log_info "Docker 环境检查通过"
    else
        log_error "Docker 未安装，请先安装 Docker："
        echo "curl -fsSL get.docker.com -o get-docker.sh && sh get-docker.sh"
        exit 1
    fi
}

# 生成 Reality 密钥对
generate_reality_keys() {
    log_info "生成 Reality 密钥对..."
    
    # 直接使用备用方法生成密钥，避免解析 /xray x25519 的兼容性问题
    generate_keys_fallback
}

# 备用密钥生成方法
generate_keys_fallback() {
    log_info "使用 OpenSSL 生成 Reality 密钥对..."
    
    # 使用 openssl 生成密钥对
    if command -v openssl &> /dev/null; then
        # 生成 X25519 私钥
        local private_key_raw
        private_key_raw=$(openssl genpkey -algorithm X25519 2>/dev/null)
        
        if [[ -n "$private_key_raw" ]]; then
            # 提取私钥（32字节）
            GENERATED_PRIVATE_KEY=$(echo "$private_key_raw" | openssl pkey -noout -text 2>/dev/null | grep -A 3 "priv:" | tail -n +2 | tr -d ' \n:' | xxd -r -p | base64 -w 0)
            
            # 从私钥生成公钥
            GENERATED_PUBLIC_KEY=$(echo "$private_key_raw" | openssl pkey -pubout 2>/dev/null | openssl pkey -pubin -noout -text 2>/dev/null | grep -A 3 "pub:" | tail -n +2 | tr -d ' \n:' | xxd -r -p | base64 -w 0)
            
            if [[ -n "$GENERATED_PRIVATE_KEY" && -n "$GENERATED_PUBLIC_KEY" ]]; then
                log_info "OpenSSL 生成密钥成功"
                log_info "私钥: $GENERATED_PRIVATE_KEY"
                log_info "公钥: $GENERATED_PUBLIC_KEY"
            else
                log_warn "OpenSSL 密钥提取失败，使用简化方法"
                generate_keys_simple
            fi
        else
            log_warn "OpenSSL 生成失败，使用简化方法"
            generate_keys_simple
        fi
    else
        log_error "openssl 未安装且无可用的密钥生成方法！"
        log_error "请安装 OpenSSL 或手动指定私钥进行部署"
        log_error "安装命令: sudo apt install openssl (Ubuntu/Debian) 或 sudo yum install openssl (CentOS/RHEL)"
        exit 1
    fi
}

# 简化的密钥生成方法
generate_keys_simple() {
    log_info "使用简化方法生成密钥对..."
    
    # 使用 /dev/urandom 生成随机密钥
    if [[ -r /dev/urandom ]]; then
        GENERATED_PRIVATE_KEY=$(head -c 32 /dev/urandom | base64 -w 0)
        GENERATED_PUBLIC_KEY=$(head -c 32 /dev/urandom | base64 -w 0)
        
        log_info "随机密钥生成成功"
        log_info "私钥: $GENERATED_PRIVATE_KEY"
        log_info "公钥: $GENERATED_PUBLIC_KEY"
        
        echo
        log_warn "⚠️  注意：使用了简化的随机密钥生成方法"
        log_warn "⚠️  虽然是随机生成，但不符合 X25519 标准，建议部署后手动更新"
        echo
    else
        log_error "无法访问随机数源，密钥生成失败！"
        log_error "请确保系统支持 /dev/urandom 或安装 OpenSSL"
        log_error "或者手动指定私钥进行部署"
        exit 1
    fi
}

# 检查端口是否被占用
check_port() {
    local port=$1
    if netstat -tuln 2>/dev/null | grep -q ":$port "; then
        return 1
    elif ss -tuln 2>/dev/null | grep -q ":$port "; then
        return 1
    else
        return 0
    fi
}

# 获取用户输入
get_user_input() {
    echo
    log_blue "=== Xray Reality 部署配置 ==="
    echo
    
    # 选择部署模式
    echo "请选择部署模式:"
    echo "1) Reality 模式 (标准模式，推荐新手)"
    echo "2) xhttp Reality 模式 (更好的伪装效果)"
    echo "3) 同时部署两种模式"
    echo
    read -p "请输入选择 [1-3]: " DEPLOY_MODE
    
    case $DEPLOY_MODE in
        1)
            DEPLOY_TYPE="reality"
            ;;
        2)
            DEPLOY_TYPE="xhttp_reality"
            ;;
        3)
            DEPLOY_TYPE="both"
            ;;
        *)
            log_error "无效选择"
            exit 1
            ;;
    esac
    
    # 获取端口配置
    if [[ "$DEPLOY_TYPE" == "both" ]]; then
        # 部署两种模式
        read -p "请输入 Reality 模式端口 [默认: 2333]: " REALITY_PORT
        REALITY_PORT=${REALITY_PORT:-2333}
        
        read -p "请输入 xhttp Reality 模式端口 [默认: 23333]: " XHTTP_PORT
        XHTTP_PORT=${XHTTP_PORT:-23333}
        
        # 检查端口冲突
        if ! check_port $REALITY_PORT; then
            log_error "端口 $REALITY_PORT 已被占用"
            exit 1
        fi
        
        if ! check_port $XHTTP_PORT; then
            log_error "端口 $XHTTP_PORT 已被占用"
            exit 1
        fi
        
        if [[ "$REALITY_PORT" == "$XHTTP_PORT" ]]; then
            log_error "两个端口不能相同"
            exit 1
        fi
        
    else
        # 部署单一模式
        if [[ "$DEPLOY_TYPE" == "reality" ]]; then
            read -p "请输入端口 [默认: 2333]: " EXTERNAL_PORT
            EXTERNAL_PORT=${EXTERNAL_PORT:-2333}
        else
            read -p "请输入端口 [默认: 23333]: " EXTERNAL_PORT
            EXTERNAL_PORT=${EXTERNAL_PORT:-23333}
        fi
        
        if ! check_port $EXTERNAL_PORT; then
            log_error "端口 $EXTERNAL_PORT 已被占用"
            exit 1
        fi
    fi
    
    # 是否自定义配置
    echo
    read -p "是否使用自定义配置? [y/N]: " USE_CUSTOM
    
    if [[ "$USE_CUSTOM" =~ ^[Yy]$ ]]; then
        read -p "请输入自定义 UUID (留空自动生成): " CUSTOM_UUID
        read -p "请输入伪装域名 [默认: www.apple.com images.apple.com]: " CUSTOM_SERVERNAMES
        read -p "请输入目标地址 [默认: www.apple.com:443]: " CUSTOM_DEST
        
        echo
        read -p "是否使用自定义私钥? [y/N]: " USE_CUSTOM_KEY
        if [[ "$USE_CUSTOM_KEY" =~ ^[Yy]$ ]]; then
            read -p "请输入私钥: " CUSTOM_PRIVATEKEY
        else
            # 生成新的密钥对
            generate_reality_keys
            CUSTOM_PRIVATEKEY="$GENERATED_PRIVATE_KEY"
            CUSTOM_PUBLICKEY="$GENERATED_PUBLIC_KEY"
        fi
        
        CUSTOM_SERVERNAMES=${CUSTOM_SERVERNAMES:-"www.apple.com images.apple.com"}
        CUSTOM_DEST=${CUSTOM_DEST:-"www.apple.com:443"}
    else
        # 使用默认配置时也生成密钥对，避免容器内生成失败
        echo
        log_info "生成默认配置的密钥对..."
        generate_reality_keys
        DEFAULT_PRIVATEKEY="$GENERATED_PRIVATE_KEY"
        DEFAULT_PUBLICKEY="$GENERATED_PUBLIC_KEY"
    fi
}

# 部署 Reality 模式
deploy_reality() {
    local port=$1
    local container_name="xray_reality"
    
    if [[ "$DEPLOY_TYPE" == "both" ]]; then
        container_name="xray_reality_standard"
    fi
    
    log_info "正在部署 Reality 模式..."
    log_info "容器名称: $container_name"
    log_info "端口: $port"
    
    # 构建 Docker 命令
    local docker_cmd="docker run -d --name $container_name --restart=always"
    docker_cmd="$docker_cmd --log-opt max-size=100m --log-opt max-file=3"
    docker_cmd="$docker_cmd -p $port:443 -e EXTERNAL_PORT=$port"
    
    # 添加自定义配置
    if [[ "$USE_CUSTOM" =~ ^[Yy]$ ]]; then
        [[ -n "$CUSTOM_UUID" ]] && docker_cmd="$docker_cmd -e UUID=\"$CUSTOM_UUID\""
        [[ -n "$CUSTOM_SERVERNAMES" ]] && docker_cmd="$docker_cmd -e SERVERNAMES=\"$CUSTOM_SERVERNAMES\""
        [[ -n "$CUSTOM_DEST" ]] && docker_cmd="$docker_cmd -e DEST=\"$CUSTOM_DEST\""
        [[ -n "$CUSTOM_PRIVATEKEY" ]] && docker_cmd="$docker_cmd -e PRIVATEKEY=\"$CUSTOM_PRIVATEKEY\""
    else
        # 使用默认生成的密钥
        [[ -n "$DEFAULT_PRIVATEKEY" ]] && docker_cmd="$docker_cmd -e PRIVATEKEY=\"$DEFAULT_PRIVATEKEY\""
    fi
    
    docker_cmd="$docker_cmd wulabing/xray_docker_reality:latest"
    
    # 拉取镜像
    log_info "拉取 Reality 镜像..."
    docker pull wulabing/xray_docker_reality:latest
    
    # 运行容器
    log_info "启动 Reality 容器..."
    eval $docker_cmd
    
    # 等待容器启动
    sleep 5
    
    # 显示配置信息
    log_info "Reality 模式部署完成！"
    echo
    log_blue "=== Reality 模式配置信息 ==="
    docker exec -it $container_name cat /config_info.txt 2>/dev/null || {
        log_warn "获取配置信息失败，请稍后使用命令查看: docker logs $container_name"
    }
    echo
}

# 部署 xhttp Reality 模式
deploy_xhttp_reality() {
    local port=$1
    local container_name="xray_xhttp_reality"
    
    if [[ "$DEPLOY_TYPE" == "both" ]]; then
        container_name="xray_xhttp_reality_mode"
    fi
    
    log_info "正在部署 xhttp Reality 模式..."
    log_info "容器名称: $container_name"
    log_info "端口: $port"
    
    # 构建 Docker 命令
    local docker_cmd="docker run -d --name $container_name --restart=always"
    docker_cmd="$docker_cmd --log-opt max-size=100m --log-opt max-file=3"
    docker_cmd="$docker_cmd -p $port:443 -e EXTERNAL_PORT=$port"
    
    # 添加自定义配置
    if [[ "$USE_CUSTOM" =~ ^[Yy]$ ]]; then
        [[ -n "$CUSTOM_UUID" ]] && docker_cmd="$docker_cmd -e UUID=\"$CUSTOM_UUID\""
        [[ -n "$CUSTOM_SERVERNAMES" ]] && docker_cmd="$docker_cmd -e SERVERNAMES=\"$CUSTOM_SERVERNAMES\""
        [[ -n "$CUSTOM_DEST" ]] && docker_cmd="$docker_cmd -e DEST=\"$CUSTOM_DEST\""
        [[ -n "$CUSTOM_PRIVATEKEY" ]] && docker_cmd="$docker_cmd -e PRIVATEKEY=\"$CUSTOM_PRIVATEKEY\""
    else
        # 使用默认生成的密钥
        [[ -n "$DEFAULT_PRIVATEKEY" ]] && docker_cmd="$docker_cmd -e PRIVATEKEY=\"$DEFAULT_PRIVATEKEY\""
    fi
    
    docker_cmd="$docker_cmd wulabing/xray_docker_xhttp_reality:latest"
    
    # 拉取镜像
    log_info "拉取 xhttp Reality 镜像..."
    docker pull wulabing/xray_docker_xhttp_reality:latest
    
    # 运行容器
    log_info "启动 xhttp Reality 容器..."
    eval $docker_cmd
    
    # 等待容器启动
    sleep 5
    
    # 显示配置信息
    log_info "xhttp Reality 模式部署完成！"
    echo
    log_blue "=== xhttp Reality 模式配置信息 ==="
    docker exec -it $container_name cat /config_info.txt 2>/dev/null || {
        log_warn "获取配置信息失败，请稍后使用命令查看: docker logs $container_name"
    }
    echo
}

# 配置防火墙
configure_firewall() {
    log_info "配置防火墙..."
    
    local ports=()
    
    if [[ "$DEPLOY_TYPE" == "reality" ]]; then
        ports+=($EXTERNAL_PORT)
    elif [[ "$DEPLOY_TYPE" == "xhttp_reality" ]]; then
        ports+=($EXTERNAL_PORT)
    elif [[ "$DEPLOY_TYPE" == "both" ]]; then
        ports+=($REALITY_PORT $XHTTP_PORT)
    fi
    
    for port in "${ports[@]}"; do
        # Ubuntu/Debian
        if command -v ufw &> /dev/null; then
            sudo ufw allow $port/tcp 2>/dev/null && log_info "已开放端口 $port (ufw)" || log_warn "开放端口 $port 失败"
        fi
        
        # CentOS/RHEL
        if command -v firewall-cmd &> /dev/null; then
            sudo firewall-cmd --permanent --add-port=$port/tcp 2>/dev/null && log_info "已开放端口 $port (firewalld)" || log_warn "开放端口 $port 失败"
        fi
    done
    
    # 重载防火墙规则
    if command -v firewall-cmd &> /dev/null; then
        sudo firewall-cmd --reload 2>/dev/null
    fi
}

# 显示管理命令
show_management_commands() {
    echo
    log_blue "=== 容器管理命令 ==="
    echo
    
    if [[ "$DEPLOY_TYPE" == "reality" ]]; then
        echo "# Reality 模式管理命令"
        echo "docker logs xray_reality                 # 查看日志"
        echo "docker restart xray_reality              # 重启容器"
        echo "docker stop xray_reality                 # 停止容器"
        echo "docker rm -f xray_reality                # 删除容器"
        echo "docker exec -it xray_reality cat /config_info.txt  # 查看配置"
        
    elif [[ "$DEPLOY_TYPE" == "xhttp_reality" ]]; then
        echo "# xhttp Reality 模式管理命令"
        echo "docker logs xray_xhttp_reality           # 查看日志"
        echo "docker restart xray_xhttp_reality        # 重启容器"
        echo "docker stop xray_xhttp_reality           # 停止容器"
        echo "docker rm -f xray_xhttp_reality          # 删除容器"
        echo "docker exec -it xray_xhttp_reality cat /config_info.txt  # 查看配置"
        
    elif [[ "$DEPLOY_TYPE" == "both" ]]; then
        echo "# Reality 标准模式管理命令"
        echo "docker logs xray_reality_standard        # 查看日志"
        echo "docker restart xray_reality_standard     # 重启容器"
        echo "docker stop xray_reality_standard        # 停止容器"
        echo "docker rm -f xray_reality_standard       # 删除容器"
        echo "docker exec -it xray_reality_standard cat /config_info.txt  # 查看配置"
        echo
        echo "# xhttp Reality 模式管理命令"
        echo "docker logs xray_xhttp_reality_mode      # 查看日志"
        echo "docker restart xray_xhttp_reality_mode   # 重启容器"
        echo "docker stop xray_xhttp_reality_mode      # 停止容器"
        echo "docker rm -f xray_xhttp_reality_mode     # 删除容器"
        echo "docker exec -it xray_xhttp_reality_mode cat /config_info.txt  # 查看配置"
    fi
    
    echo
    echo "# 通用命令"
    echo "docker ps                                 # 查看运行中的容器"
    echo "docker ps -a                             # 查看所有容器"
    echo
}

# 主函数
main() {
    echo
    log_blue "=== Xray Docker Reality 一键部署脚本 ==="
    log_blue "=== 作者: GitHub Copilot ==="
    log_blue "=== 日期: 2025-09-06 ==="
    echo
    
    # 检查环境
    check_root
    check_system
    
    # 检查 Docker
    check_docker
    
    # 获取用户输入
    get_user_input
    
    echo
    log_blue "=== 开始部署 ==="
    
    # 根据选择部署
    case $DEPLOY_TYPE in
        "reality")
            deploy_reality $EXTERNAL_PORT
            ;;
        "xhttp_reality")
            deploy_xhttp_reality $EXTERNAL_PORT
            ;;
        "both")
            deploy_reality $REALITY_PORT
            deploy_xhttp_reality $XHTTP_PORT
            ;;
    esac
    
    # 配置防火墙
    configure_firewall
    
    # 显示管理命令
    show_management_commands
    
    echo
    log_info "部署完成！请使用上述配置信息配置客户端。"
    log_warn "如果看不到配置信息，请等待几分钟后使用管理命令查看。"
    
    echo
}

# 信号处理
trap 'log_error "脚本被中断"; exit 1' INT TERM

# 运行主函数
main "$@"
