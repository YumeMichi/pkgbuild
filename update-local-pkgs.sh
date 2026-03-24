#!/bin/bash

# PKGBUILD 目录
PKG_ROOT="."

# 颜色与样式定义
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # 重置颜色

# 图标定义
ICON_INFO="${BLUE}::${NC}"
ICON_CHECK="${GREEN}✔${NC}"
ICON_UPDATE="${YELLOW}➜${NC}"
ICON_ERROR="${RED}✘${NC}"
ICON_PROCESS="${MAGENTA}⚙${NC}"

# 检查根目录
if [[ ! -d "$PKG_ROOT" ]]; then
    echo -e "${ICON_ERROR} ${RED}错误: 目录 $PKG_ROOT 不存在。${NC}"
    exit 1
fi

cd "$PKG_ROOT" || exit 1

echo -e "${BOLD}${CYAN}开始扫描本地 PKGBUILD 仓库...${NC}\n"

# 遍历子目录
for dir in */; do
    dir=${dir%/}
    if [[ ! -f "$dir/PKGBUILD" ]]; then continue; fi

    # 打印当前处理的包名
    echo -e "${ICON_INFO} ${BOLD}正在检查目录: ${CYAN}$dir${NC}"

    pushd "$dir" > /dev/null

    # 1. 更新源码以触发 pkgver()
    echo -ne "   ${ICON_PROCESS} 正在拉取最新 Git 信息并更新版本号... "
    # 使用 makepkg -od 更新版本号，捕获可能的错误
    if ! makepkg -od --noconfirm > /dev/null 2>&1; then
        echo -e "\r   ${ICON_ERROR} ${RED}获取更新失败 (Git 或依赖错误)${NC}"
        popd > /dev/null
        continue
    else
        echo -e "\r   ${ICON_CHECK} ${GREEN}Git 信息已同步${NC}                       "
    fi

    # 2. 解析版本信息
    srcinfo=$(makepkg --printsrcinfo)
    pkgnames=$(echo "$srcinfo" | grep -E "^\s*pkgname =" | sed 's/.*= //')
    l_pkgver=$(echo "$srcinfo" | grep -E "^\s*pkgver =" | sed 's/.*= //')
    l_pkgrel=$(echo "$srcinfo" | grep -E "^\s*pkgrel =" | sed 's/.*= //')
    l_epoch=$(echo "$srcinfo" | grep -E "^\s*epoch =" | sed 's/.*= //')

    # 处理版本号字符串
    if [[ -z "$l_epoch" ]]; then
        local_full_ver="$l_pkgver-$l_pkgrel"
    else
        local_full_ver="$l_epoch:$l_pkgver-$l_pkgrel"
    fi

    need_build=false

    # 3. 遍历检查 PKGBUILD 产生的所有包（针对拆分包）
    for name in $pkgnames; do
        inst_ver=$(pacman -Q "$name" 2>/dev/null | awk '{print $2}')

        if [[ -z "$inst_ver" ]]; then
            echo -e "   ${ICON_UPDATE} ${MAGENTA}[${name}]${NC} 状态: ${RED}未安装${NC}"
            echo -e "      ${BOLD}目标版本:${NC} ${GREEN}${local_full_ver}${NC}"
            need_build=true
        else
            # 版本比对
            cmp_res=$(vercmp "$local_full_ver" "$inst_ver")

            if (( cmp_res > 0 )); then
                echo -e "   ${ICON_UPDATE} ${MAGENTA}[${name}]${NC} 状态: ${YELLOW}发现更新!${NC}"
                echo -e "      ${BOLD}当前版本:${NC} ${RED}${inst_ver}${NC}"
                echo -e "      ${BOLD}最新版本:${NC} ${GREEN}${local_full_ver}${NC}"
                need_build=true
            elif (( cmp_res < 0 )); then
                echo -e "   ${ICON_CHECK} ${MAGENTA}[${name}]${NC} 状态: 系统版本更高 (${inst_ver})"
            else
                echo -e "   ${ICON_CHECK} ${MAGENTA}[${name}]${NC} 状态: ${GREEN}已是最新${NC} (${inst_ver})"
            fi
        fi
    done

    # 4. 执行编译与安装
    if [[ "$need_build" = true ]]; then
        echo -e "   ${ICON_PROCESS} ${BOLD}${YELLOW}开始编译并安装新版本...${NC}"
        # -s 安装依赖, -i 安装包, --noconfirm 不询问, --needed 如果已安装相同版本则跳过
        if makepkg -si --noconfirm --needed; then
            echo -e "   ${ICON_CHECK} ${BOLD}${GREEN}$dir 更新成功！${NC}"
        else
            echo -e "   ${ICON_ERROR} ${BOLD}${RED}$dir 编译或安装失败。${NC}"
        fi
    fi

    popd > /dev/null
    echo -e "${BLUE}-------------------------------------------------------${NC}"
done

echo -e "\n${BOLD}${GREEN}所有任务检查完毕。${NC}"
