#!/bin/bash

# Xray Reality 管理脚本

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# 显示菜单
show_menu() {
    echo
    echo -e "${BLUE}=== Xray Reality 管理脚本 ===${NC}"
    echo
    echo "1) 查看所有容器状态"
    echo "2) 查看 Reality 配置信息"
    echo "3) 查看 xhttp Reality 配置信息"
    echo "4) 查看容器日志"
    echo "5) 重启容器"
    echo "6) 停止容器"
    echo "7) 启动容器"
    echo "8) 删除容器"
    echo "9) 更新镜像并重新部署"
    echo "0) 退出"
    echo
}

# 查看容器状态
show_status() {
    echo -e "${YELLOW}=== 容器状态 ===${NC}"
    docker ps -a --filter "name=xray" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo
}

# 查看配置信息
show_config() {
    local container_name=$1
    
    if docker ps --filter "name=$container_name" --format "{{.Names}}" | grep -q "$container_name"; then
        echo -e "${YELLOW}=== $container_name 配置信息 ===${NC}"
        docker exec -it $container_name cat /config_info.txt 2>/dev/null || {
            echo -e "${RED}获取配置信息失败${NC}"
        }
    else
        echo -e "${RED}容器 $container_name 未运行${NC}"
    fi
    echo
}

# 查看日志
show_logs() {
    echo "选择要查看日志的容器:"
    echo "1) xray_reality"
    echo "2) xray_xhttp_reality"
    echo "3) xray_reality_standard"
    echo "4) xray_xhttp_reality_mode"
    echo
    
    read -p "请输入选择: " choice
    
    case $choice in
        1) container_name="xray_reality" ;;
        2) container_name="xray_xhttp_reality" ;;
        3) container_name="xray_reality_standard" ;;
        4) container_name="xray_xhttp_reality_mode" ;;
        *) echo -e "${RED}无效选择${NC}"; return ;;
    esac
    
    if docker ps --filter "name=$container_name" --format "{{.Names}}" | grep -q "$container_name"; then
        echo -e "${YELLOW}=== $container_name 日志 (按 Ctrl+C 退出) ===${NC}"
        docker logs -f $container_name
    else
        echo -e "${RED}容器 $container_name 未运行${NC}"
    fi
}

# 容器操作
container_operation() {
    local operation=$1
    
    echo "选择要${operation}的容器:"
    echo "1) xray_reality"
    echo "2) xray_xhttp_reality"
    echo "3) xray_reality_standard"
    echo "4) xray_xhttp_reality_mode"
    echo "5) 所有容器"
    echo
    
    read -p "请输入选择: " choice
    
    local containers=()
    case $choice in
        1) containers=("xray_reality") ;;
        2) containers=("xray_xhttp_reality") ;;
        3) containers=("xray_reality_standard") ;;
        4) containers=("xray_xhttp_reality_mode") ;;
        5) containers=("xray_reality" "xray_xhttp_reality" "xray_reality_standard" "xray_xhttp_reality_mode") ;;
        *) echo -e "${RED}无效选择${NC}"; return ;;
    esac
    
    for container in "${containers[@]}"; do
        if docker ps -a --filter "name=$container" --format "{{.Names}}" | grep -q "^$container$"; then
            echo -e "${YELLOW}${operation}容器: $container${NC}"
            
            case $operation in
                "重启")
                    docker restart $container
                    ;;
                "停止")
                    docker stop $container
                    ;;
                "启动")
                    docker start $container
                    ;;
                "删除")
                    read -p "确认删除容器 $container? [y/N]: " confirm
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        docker rm -f $container
                        echo -e "${GREEN}容器 $container 已删除${NC}"
                    fi
                    ;;
            esac
        else
            echo -e "${RED}容器 $container 不存在${NC}"
        fi
    done
    echo
}

# 更新镜像并重新部署
update_and_redeploy() {
    echo "选择要更新的服务:"
    echo "1) Reality 模式"
    echo "2) xhttp Reality 模式"
    echo "3) 两种模式都更新"
    echo
    
    read -p "请输入选择: " choice
    
    case $choice in
        1)
            echo -e "${YELLOW}更新 Reality 模式...${NC}"
            # 停止并删除旧容器
            docker stop xray_reality 2>/dev/null || true
            docker rm xray_reality 2>/dev/null || true
            
            # 拉取最新镜像
            docker pull wulabing/xray_docker_reality:latest
            
            # 重新部署
            read -p "请输入端口 [默认: 2333]: " port
            port=${port:-2333}
            
            docker run -d --name xray_reality --restart=always \
                --log-opt max-size=100m --log-opt max-file=3 \
                -p $port:443 -e EXTERNAL_PORT=$port \
                wulabing/xray_docker_reality:latest
            
            echo -e "${GREEN}Reality 模式更新完成${NC}"
            ;;
            
        2)
            echo -e "${YELLOW}更新 xhttp Reality 模式...${NC}"
            # 停止并删除旧容器
            docker stop xray_xhttp_reality 2>/dev/null || true
            docker rm xray_xhttp_reality 2>/dev/null || true
            
            # 拉取最新镜像
            docker pull wulabing/xray_docker_xhttp_reality:latest
            
            # 重新部署
            read -p "请输入端口 [默认: 23333]: " port
            port=${port:-23333}
            
            docker run -d --name xray_xhttp_reality --restart=always \
                --log-opt max-size=100m --log-opt max-file=3 \
                -p $port:443 -e EXTERNAL_PORT=$port \
                wulabing/xray_docker_xhttp_reality:latest
            
            echo -e "${GREEN}xhttp Reality 模式更新完成${NC}"
            ;;
            
        3)
            echo -e "${YELLOW}更新两种模式...${NC}"
            
            # Reality 模式
            docker stop xray_reality 2>/dev/null || true
            docker rm xray_reality 2>/dev/null || true
            docker pull wulabing/xray_docker_reality:latest
            
            read -p "请输入 Reality 模式端口 [默认: 2333]: " reality_port
            reality_port=${reality_port:-2333}
            
            docker run -d --name xray_reality --restart=always \
                --log-opt max-size=100m --log-opt max-file=3 \
                -p $reality_port:443 -e EXTERNAL_PORT=$reality_port \
                wulabing/xray_docker_reality:latest
            
            # xhttp Reality 模式
            docker stop xray_xhttp_reality 2>/dev/null || true
            docker rm xray_xhttp_reality 2>/dev/null || true
            docker pull wulabing/xray_docker_xhttp_reality:latest
            
            read -p "请输入 xhttp Reality 模式端口 [默认: 23333]: " xhttp_port
            xhttp_port=${xhttp_port:-23333}
            
            docker run -d --name xray_xhttp_reality --restart=always \
                --log-opt max-size=100m --log-opt max-file=3 \
                -p $xhttp_port:443 -e EXTERNAL_PORT=$xhttp_port \
                wulabing/xray_docker_xhttp_reality:latest
            
            echo -e "${GREEN}两种模式更新完成${NC}"
            ;;
            
        *)
            echo -e "${RED}无效选择${NC}"
            ;;
    esac
    
    echo
    echo -e "${YELLOW}等待容器启动...${NC}"
    sleep 5
}

# 主循环
main() {
    while true; do
        show_menu
        read -p "请输入选择: " choice
        
        case $choice in
            1)
                show_status
                ;;
            2)
                show_config "xray_reality"
                ;;
            3)
                show_config "xray_xhttp_reality"
                ;;
            4)
                show_logs
                ;;
            5)
                container_operation "重启"
                ;;
            6)
                container_operation "停止"
                ;;
            7)
                container_operation "启动"
                ;;
            8)
                container_operation "删除"
                ;;
            9)
                update_and_redeploy
                ;;
            0)
                echo -e "${GREEN}再见！${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选择，请重新输入${NC}"
                ;;
        esac
        
        read -p "按回车键继续..."
    done
}

# 检查 Docker 是否安装
if ! command -v docker &> /dev/null; then
    echo -e "${RED}错误: Docker 未安装${NC}"
    echo "请先运行部署脚本安装 Docker"
    exit 1
fi

# 运行主程序
main
