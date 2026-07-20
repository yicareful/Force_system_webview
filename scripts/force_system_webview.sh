#!/system/bin/sh

MODDIR=${0%/*}/..
APP_CONFIG="${MODDIR}/scripts/apps.conf"

BLUE='\033[34m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'

print_app_result() {
    echo "APP_RESULT|$1|$2|$3"
}

is_safe_pkg() {
    case "$1" in
        ""|*[!a-zA-Z0-9._-]*|.*|*..*) return 1 ;;
        *) return 0 ;;
    esac
}

is_safe_subdir() {
    case "$1" in
        ""|/*|*../*|../*|*'/../'*|*'..'*) return 1 ;;
        *) return 0 ;;
    esac
}

find_app_config() {
    local target="$1"

    APP_NAME=""
    APP_DIRS=""

    while IFS='|' read -r pkg name dirs
    do
        case "$pkg" in
            ""|\#*) continue ;;
        esac

        if [ "$pkg" = "$target" ]; then
            APP_NAME="$name"
            APP_DIRS="$dirs"
            return 0
        fi
    done < "$APP_CONFIG"

    return 1
}

list_all_packages() {
    while IFS='|' read -r pkg name dirs
    do
        case "$pkg" in
            ""|\#*) continue ;;
        esac
        echo "$pkg"
    done < "$APP_CONFIG"
}

is_dir_locked() {
    local path="$1"
    local mode

    [ -d "$path" ] || return 1
    mode="$(stat -c '%a' "$path" 2>/dev/null)"
    case "$mode" in
        0|00|000) return 0 ;;
        *) return 1 ;;
    esac
}

detect_app() {
    local pkg="$1"
    local check_running="$2"
    local check_done_running="$3"

    DETECT_STATUS="FAIL"
    DETECT_MESSAGE=""

    if ! is_safe_pkg "$pkg"; then
        DETECT_MESSAGE="包名非法或空白"
        print_app_result "$pkg" "$DETECT_STATUS" "$DETECT_MESSAGE"
        return 1
    fi

    if ! find_app_config "$pkg"; then
        DETECT_MESSAGE="未找到内置配置"
        print_app_result "$pkg" "$DETECT_STATUS" "$DETECT_MESSAGE"
        return 1
    fi

    local base_path="/data/data/${pkg}"
    if [ ! -d "$base_path" ]; then
        DETECT_STATUS="NOT_INSTALLED"
        DETECT_MESSAGE="应用数据目录不存在"
        print_app_result "$pkg" "$DETECT_STATUS" "$DETECT_MESSAGE"
        return 0
    fi

    local total=0
    local locked=0
    local invalid=0
    local sub_dir
    local full_path

    for sub_dir in $APP_DIRS
    do
        total=$((total + 1))
        if ! is_safe_subdir "$sub_dir"; then
            invalid=$((invalid + 1))
            continue
        fi

        full_path="${base_path}/${sub_dir}"
        case "$full_path" in
            "$base_path"/*) ;;
            *) invalid=$((invalid + 1)); continue ;;
        esac

        if is_dir_locked "$full_path"; then
            locked=$((locked + 1))
        fi
    done

    if [ "$invalid" -gt 0 ]; then
        DETECT_STATUS="FAIL"
        DETECT_MESSAGE="配置中存在异常目录：${invalid} 个"
        print_app_result "$pkg" "$DETECT_STATUS" "$DETECT_MESSAGE"
        return 1
    fi

    if [ "$locked" -eq "$total" ]; then
        if [ "$check_running" = "1" ] && [ "$check_done_running" = "1" ] && is_app_running "$pkg"; then
            DETECT_STATUS="RUNNING"
            DETECT_MESSAGE="APP 仍在运行，请先强行停止"
            print_app_result "$pkg" "$DETECT_STATUS" "$DETECT_MESSAGE"
            return 0
        fi
        DETECT_STATUS="DONE"
        DETECT_MESSAGE="已锁定 ${locked}/${total} 个私有 WebView 目录"
        print_app_result "$pkg" "$DETECT_STATUS" "$DETECT_MESSAGE"
        return 0
    fi

    if [ "$locked" -gt 0 ]; then
        DETECT_STATUS="PARTIAL"
        DETECT_MESSAGE="仅锁定 ${locked}/${total} 个私有 WebView 目录"
        if [ "$check_running" = "1" ] && is_app_running "$pkg"; then
            DETECT_STATUS="RUNNING"
            DETECT_MESSAGE="APP 仍在运行，请先强行停止"
        fi
        print_app_result "$pkg" "$DETECT_STATUS" "$DETECT_MESSAGE"
        return 0
    fi

    DETECT_STATUS="PENDING"
    DETECT_MESSAGE="尚未锁定私有 WebView 目录"
    if [ "$check_running" = "1" ] && is_app_running "$pkg"; then
        DETECT_STATUS="RUNNING"
        DETECT_MESSAGE="APP 仍在运行，请先强行停止"
    fi
    print_app_result "$pkg" "$DETECT_STATUS" "$DETECT_MESSAGE"
    return 0
}

is_app_running() {
    local pkg="$1"
    local proc
    local cmdline

    for proc in /proc/[0-9]*
    do
        [ -r "${proc}/cmdline" ] || continue
        cmdline="$(tr '\000' ' ' < "${proc}/cmdline" 2>/dev/null)"
        cmdline="${cmdline%% *}"
        case "$cmdline" in
            "$pkg"|"$pkg":*) return 0 ;;
        esac
    done

    return 1
}

lock_private_webview_dir() {
    local base_path="$1"
    local sub_dir="$2"
    local full_path="${base_path}/${sub_dir}"

    if ! is_safe_subdir "$sub_dir"; then
        echo -e "${RED}路径异常，跳过：${sub_dir}${RESET}"
        return 1
    fi

    case "$full_path" in
        "$base_path"/*) ;;
        *)
            echo -e "${RED}路径越界，跳过：${full_path}${RESET}"
            return 1
            ;;
    esac

    echo "删除目录：${full_path}"
    rm -rf "$full_path"
    if [ -e "$full_path" ]; then
        echo -e "${RED}删除失败：${full_path}${RESET}"
        return 1
    fi

    mkdir -p "$full_path"
    chown root:root "$full_path" 2>/dev/null
    chmod 000 "$full_path" 2>/dev/null

    local mode
    mode="$(stat -c '%a' "$full_path" 2>/dev/null)"
    case "$mode" in
        0|00|000)
            echo "已创建占位目录并锁定权限 000：${full_path}"
            return 0
            ;;
        *)
            echo -e "${RED}权限校验失败：${full_path} 当前权限=${mode:-unknown}${RESET}"
            return 1
            ;;
    esac
}

clear_app_cache() {
    local base_path="$1"

    if [ -d "${base_path}/cache" ]; then
        rm -rf "${base_path}/cache/"*
    fi

    if [ -d "${base_path}/code_cache" ]; then
        rm -rf "${base_path}/code_cache/"*
    fi

    echo "已清理当前应用缓存"
}

process_app() {
    local pkg="$1"
    local force="$2"

    if ! is_safe_pkg "$pkg"; then
        echo -e "${YELLOW}包名非法或空白，跳过：${pkg}${RESET}"
        print_app_result "$pkg" "FAIL" "包名非法或空白"
        return 1
    fi

    if ! find_app_config "$pkg"; then
        echo -e "${YELLOW}未找到内置配置，跳过：${pkg}${RESET}"
        print_app_result "$pkg" "FAIL" "未找到内置配置"
        return 1
    fi

    local base_path="/data/data/${pkg}"
    echo -e "${GREEN}>>> 正在处理应用：${APP_NAME} (${pkg})${RESET}"

    if [ ! -d "$base_path" ]; then
        echo -e "${YELLOW}应用数据目录不存在，可能未安装或尚未启动过：${base_path}${RESET}"
        print_app_result "$pkg" "NOT_INSTALLED" "应用数据目录不存在"
        echo ""
        return 0
    fi

    echo "检测当前锁定状态..."
    if ! detect_app "$pkg" "0"; then
        return 1
    fi

    if [ "$DETECT_STATUS" = "DONE" ] && [ "$force" != "1" ]; then
        echo "检测结果：已完成，跳过重复操作"
        echo ""
        return 0
    fi

    if is_app_running "$pkg"; then
        echo -e "${RED}检测到 APP 仍在运行，请先强行停止后再执行：${APP_NAME} (${pkg})${RESET}"
        print_app_result "$pkg" "RUNNING" "APP 仍在运行，请先强行停止"
        echo ""
        return 1
    fi

    local total=0
    local failed=0
    local sub_dir

    for sub_dir in $APP_DIRS
    do
        total=$((total + 1))
        if ! lock_private_webview_dir "$base_path" "$sub_dir"; then
            failed=$((failed + 1))
        fi
    done

    clear_app_cache "$base_path"

    if [ "$failed" -eq 0 ]; then
        print_app_result "$pkg" "OK" "已锁定 ${total} 个私有 WebView 目录"
        echo ""
        return 0
    fi

    if [ "$failed" -lt "$total" ]; then
        print_app_result "$pkg" "PARTIAL" "部分目录处理失败：${failed}/${total}"
        echo ""
        return 1
    fi

    print_app_result "$pkg" "FAIL" "全部目录处理失败：${failed}/${total}"
    echo ""
    return 1
}

run_detect() {
    local check_running="$1"
    local check_done_running="$2"
    shift
    shift
    local overall_failed=0
    local pkg

    echo -e "${BLUE}==================== Force System WebView 检测开始 ====================${RESET}"
    for pkg in "$@"
    do
        if ! detect_app "$pkg" "$check_running" "$check_done_running"; then
            overall_failed=1
        fi
        if [ "$DETECT_STATUS" = "RUNNING" ]; then
            overall_failed=1
        fi
    done
    echo -e "${BLUE}==================== Force System WebView 检测完成 ====================${RESET}"

    return "$overall_failed"
}

wait_volume_key() {
    local event

    while true
    do
        event="$(getevent -qlc 1 2>/dev/null)"
        case "$event" in
            *KEY_VOLUMEUP*UP*) echo "all"; return 0 ;;
            *KEY_VOLUMEDOWN*UP*) echo "pending"; return 0 ;;
        esac
    done
}

run_interactive() {
    local done_list=""
    local pending_list=""
    local done_count=0
    local pending_count=0
    local skipped_count=0
    local running_list=""
    local running_count=0
    local status
    local running
    local pkg
    local choice

    echo -e "${BLUE}==================== Force System WebView 执行前检测 ====================${RESET}"
    for pkg in "$@"
    do
        detect_app "$pkg" "0" "0"
        status="$DETECT_STATUS"
        running=0
        if [ "$status" != "NOT_INSTALLED" ] && is_app_running "$pkg"; then
            running=1
            running_count=$((running_count + 1))
            running_list="${running_list} ${pkg}"
        fi

        case "$status" in
            DONE)
                done_count=$((done_count + 1))
                done_list="${done_list} ${pkg}"
                ;;
            NOT_INSTALLED)
                skipped_count=$((skipped_count + 1))
                ;;
            *)
                if [ "$running" != "1" ]; then
                    pending_count=$((pending_count + 1))
                    pending_list="${pending_list} ${pkg}"
                fi
                ;;
        esac
    done

    echo ""
    echo "已执行成功，无需再次执行：${done_count} 个"
    [ -n "$done_list" ] && echo "$done_list"
    echo "还未执行或未完整完成：${pending_count} 个"
    [ -n "$pending_list" ] && echo "$pending_list"
    echo "仍在运行，需先强行停止：${running_count} 个"
    [ -n "$running_list" ] && echo "$running_list"
    [ "$skipped_count" -gt 0 ] && echo "未安装或未启动过，已跳过：${skipped_count} 个"
    echo ""
    echo "音量+：重新执行全部 APP"
    echo "音量-：仅执行未完成 APP"

    choice="$(wait_volume_key)"
    case "$choice" in
        all)
            if [ -n "$running_list" ]; then
                echo "存在仍在运行的 APP。请先强行停止后再重新执行全部 APP："
                echo "$running_list"
                return 1
            fi
            set -- "$@"
            FORCE_RUN=1
            ;;
        pending)
            if [ -z "$pending_list" ]; then
                echo "没有待执行 APP，退出"
                return 0
            fi
            set -- $pending_list
            FORCE_RUN=0
            ;;
    esac

    run_process "$FORCE_RUN" "$@"
}

run_process() {
    local force="$1"
    shift
    local overall_failed=0
    local pkg

    echo -e "${BLUE}==================== Force System WebView 开始运行 ====================${RESET}"
    echo "作用：删除指定 APP 内置 TBS/X5/U4/MTWebView 内核，创建 000 权限占位目录"
    echo "范围：仅清理私有内核目录、cache 与 code_cache，不删除账号、聊天、本地业务数据"
    echo ""

    for pkg in "$@"
    do
        if ! process_app "$pkg" "$force"; then
            overall_failed=1
        fi
    done

    echo -e "${BLUE}==================== Force System WebView 执行完成 ====================${RESET}"
    echo "操作建议：彻底关闭对应 APP 后重新打开，使其重新初始化 WebView。"

    return "$overall_failed"
}

if [ ! -f "$APP_CONFIG" ]; then
    echo -e "${RED}缺少 APP 配置文件：${APP_CONFIG}${RESET}"
    exit 2
fi

MODE="run"
FORCE_RUN=0
TARGETS=""

while [ "$#" -gt 0 ]
do
    case "$1" in
        --list)
            cat "$APP_CONFIG"
            exit 0
            ;;
        --detect)
            MODE="detect"
            ;;
        --preflight)
            MODE="preflight"
            ;;
        --preflight-force)
            MODE="preflight_force"
            ;;
        --interactive)
            MODE="interactive"
            ;;
        --force)
            FORCE_RUN=1
            ;;
        --all)
            TARGETS="${TARGETS} $(list_all_packages)"
            ;;
        *)
            TARGETS="${TARGETS} $1"
            ;;
    esac
    shift
done

set -- $TARGETS

if [ "$#" -eq 0 ]; then
    echo -e "${YELLOW}未指定包名，默认处理全部内置 APP${RESET}"
    set -- $(list_all_packages)
fi

case "$MODE" in
    detect) run_detect "0" "0" "$@" ;;
    preflight) run_detect "1" "0" "$@" ;;
    preflight_force) run_detect "1" "1" "$@" ;;
    interactive) run_interactive "$@" ;;
    *) run_process "$FORCE_RUN" "$@" ;;
esac

exit "$?"
