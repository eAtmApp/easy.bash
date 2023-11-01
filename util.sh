#!/bin/bash

#用户密码
#USER_PASSWORD="$USER_PASSWORD"

#全局配置文件
if [ ! "$CONFIG_FILE" ]; then
    CONFIG_FILE="$(dirname "$0")/config.plist"
fi

#日志文件
if [ ! "$CONFIG_LOG_FILE" ]; then
    CONFIG_LOG_FILE="$(dirname "$0")/easy.log"
fi

#判断是否mac
is_macos() {
    if [ "$(uname)"=="Darwin" ]; then
        return 0
    else
        return 1
    fi
}

#当前运行脚本的路径
SCRIPT_FILE="$0"

#全局返回值
#G_RET=""

#日志标识符
G_LOG_ID=""

#全局进程ID
G_PID=$$

#清空屏幕
cls() {
    tput reset
}

#判断当前是标准输出,还是输出到变量 或 文件
is_stdout() {
    if [[ -t 1 ]]; then
        return 0
    else
        return 1
    fi
}

#字符串处理前后空白
trim() {
    local cmd_output=$(echo "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    echo "$cmd_output"
}

#判断字符串是否为空
is_str_empty() {
    local str="$1"
    str=$(trim "$str")

    if [ -z "$str" ]; then
        return 0
    else
        return 1
    fi
}

#输出
output() {
    local type_str=$1
    local log_str="${@:2}"

    local logid=""

    if [ "$G_LOG_ID" ]; then
        logid=" - [ $G_LOG_ID ] "
    fi

    # 定义颜色编码
    RED='\033[0;31m'         #红色
    BLUE='\033[0;34m'        #蓝色
    GREEN='\033[0;32m'       #绿色
    LIGHT_GREEN='\033[1;32m' #浅绿色
    GRAY='\033[0;37m'        #灰
    NC='\033[0m'             # 清除颜色

    local time_str="$(date +"[ %Y-%m-%d %H:%M:%S ]${logid} - ${G_PID} -")"
    local name_str=$(get_username)

    local msg="$time_str - $log_str"

    # 判断 type_str 是否为 "ERR" 字符串
    if [ "$type_str" = "ERR" ]; then #错误日志
        echo -e "${RED}${msg}${NC}" >&2
    elif [ "$type_str" = "RAW" ]; then #原始日志
        echo -e "${GRAY}${log_str}${NC}" >&2
    elif [ "$type_str" = "RAW_ERR" ]; then #原始日志
        echo -e "${RED}${log_str}${NC}" >&2
    else
        #echo -e "${GRAY}${msg}${NC}" >&2
        echo "$msg" >&2
    fi

    # 将日志写入文件
    echo "$time_str - $name_str - $type_str - $log_str " >>"$CONFIG_LOG_FILE"
}

#输出日志
outlog() {
    output "DEF" "$@"
}
#输出错误
outerr() {
    output "ERR" "$@"
}

#原始日志输出
rawout() {
    output "RAW" "$@"
}

#原始错误输出
rawerr() {
    output "RAW_ERR" "$@"
}

#判断文件是否存在
file_exists() {
    local file="$1"

    if [ -e "$file" ]; then
        return 0 # 返回真
    else
        return 1 # 返回假
    fi
}

#判断是否需要root密码
is_req_passwd() {
    if sudo -n true 2>/dev/null; then
        return 1
    else
        return 0
    fi
}

#提升root权限,提升后sudo时不用输入密码
su_root() {
    #先判断当前是否需要输入密码

    if ! is_req_passwd; then
        return 0
    fi

    if [ "$USER_PASSWORD" ]; then
        echo $USER_PASSWORD | sudo -S true

        if [ $? != 0 ]; then
            outerr "环境变量中的密码错误!"
            return 1
        fi
    else
        sudo true
        if [ $? != 0 ]; then
            outerr "密码错误!"
            return 1
        fi

    fi

    if ! is_req_passwd; then
        return 0
    fi

    outerr "提升操作权限失败!"
    return 1
}

#执行命令
#$1 失败是否退出
#$2 返回原始输出
#$3 描述
#$4 命令
#$... 参数.
exec_cmd_ex() {
    local err_is_exit=$1
    local raw_out=$2
    local desc=$3

    #命令
    local cmd_str=$4

    #命令数组- 从第3个开始截取参数
    local params=(${@:5})

    if [ $desc != "null" ]; then
        outlog "$desc..."
    fi

    #${cmd_str} ${params[@]}

    cmd_output="$(${cmd_str} ${params[@]} 2>&1)"
    local ret_code=$?

    #这里处理一次权限总是.
    if [ $ret_code != 0 ]; then
        if [[ $cmd_output == *"Permission"* || $cmd_output == *"permitted"* ]]; then
            outerr "执行命令$cmd_str ${params[@]} 失败! code: $ret_code ,权限不足,尝试用管理员身份执行!"

            if su_root; then
                cmd_output="$(sudo ${cmd_str} ${params[@]} 2>&1)"
                ret_code=$?

                if [ $ret_code == 0 ]; then
                    outlog "以管理员身份执行成功!"
                fi
            fi

        fi
    fi

    #'declare -- cmd_output="mkdir: /Library/LaunchDaemons: Permission denied"'

    if [ $ret_code != 0 ]; then

        if [ $desc != "null" ]; then
            outerr $desc"失败! code: $ret_code"
        else
            outerr "执行命令$cmd_str 失败! code: $ret_code"
        fi

        rawerr "############################################################################################"
        rawerr "命令: " $cmd_str "${params[@]}"
        rawerr "$cmd_output"
        rawerr "############################################################################################\n"

        #失败了需要退出.
        if [ $err_is_exit = "true" ]; then
            exit $ret_code
        else
            return $ret_code
        fi
    else
        if [ $raw_out = "true" ]; then

            #去掉前后空白字符
            cmd_output=$(trim "$cmd_output")
            echo "$cmd_output"

            G_RET="$cmd_output"
        fi
        return "0"
    fi
}

#执行命令-显示描述
#$2 描述
#$3 命令
#$... 参数.
exec_desc() {
    exec_cmd_ex false false "$@"
    return $?
}

#执行命令-显示描述,并且返回命令的输出字符串
#$2 描述
#$3 命令
#$... 参数.
call_desc() {
    exec_cmd_ex false true "$@"
    return $?
}

#执行命令
exec_cmd() {
    exec_cmd_ex false false null "$@"
    return $?
}

# 检查当前用户是否为root用户
function is_root {
    if [ "$(id -u)" = "0" ]; then
        return 0
    else
        return 1
    fi
}

# 得到当前用户名
function get_username() {
    local name=$(id -un)
    echo $name
    G_RET=$name
}

#判断上一个命令是否出错
function is_error() {
    G_RET=$?
    if [ $G_RET -ne 0 ]; then
        return 0
    else
        return 1
    fi
}

#判断上一个命令是否成功
function is_success() {
    G_RET=$?
    if [ $G_RET -eq 0 ]; then
        return 0
    else
        return $G_RET
    fi
}

#写文件
write_file() {
    local file_path="$1"
    local content="${@:2}"

    local folderpath=$(dirname "$file_path")

    #测试该目录权限
    if ! test -w "$folderpath"; then

        #没权限的话先写到临时目录中
        temp_file=$(mktemp)
        if is_error; then
            outerr "创建临时文件失败"
            return 1
        fi
        if ! write_file "$temp_file" "$content"; then
            outerr "写入临时文件失败"
            return 1
        fi

        if ! su_root; then
            return 1
        fi

        sudo mv -f "$temp_file" "$file_path"

        local ret_code=$?
        if [ $ret_code != 0 ]; then
            outerr "移动文件失败,错误代码: $ret_code , $file_path"
            return $ret_code
        fi

    else
        echo "$content" >"$file_path"
        local ret_code=$?
        if [ $ret_code != 0 ]; then
            outerr "写入文件失败,错误代码: $ret_code , $file_path"
            return $ret_code
        fi
    fi

    return 0
}

#读文件
read_text() {
    local file_path="$1"
    G_RET=""

    # 读取文件内容并去除前后空白字符
    local content
    # content=$(<"$file_path")
    content=$(cat "$1")
    local ret_code=$?
    if [ $ret_code != 0 ]; then
        outerr "读取文件失败,错误代码: $ret_code , $file_path"
        return $ret_code
    else
        content=$(echo "$content" | xargs)
        echo "$content"
        G_RET="$content"
        return 0
    fi
}

#删除文件

del_file() {
    local file_path="$1"

    # 强制删除文件
    rm -f "$file_path"

    local ret_code=$?

    if [ $ret_code != 0 ]; then
        outerr "删除文件失败,错误代码: $ret_code , $file_path"
        return $ret_code
    else
        return 0
    fi
}

#是否是文件夹
is_dir() {
    if [ -d "$1" ]; then
        return 0
    else
        return 1
    fi
}

#创建文件夹
mkdir() {

    local file_path="$1"

    local mode=777

    if [ "$2" ]; then
        mode=$2
    fi

    if file_exists "$file_path"; then
        if is_dir "$file_path"; then
            return 0
        else
            outerr "创建文件夹失败,该位置存在同名文件: $file_path"
            return 1
        fi
    fi

    exec_cmd "/bin/mkdir" -p -m $mode "$file_path"

    return $?
}

#判断用户是否已经登录
is_login() {
    local uname="$(users)"
    if [ "$uname" = "" ]; then
        return 1
    else
        return 0
    fi
}

#判断进程是否存在
ps_exists() {
    local ret_str=$(pgrep "$1")
    if [ "$ret_str" = "" ]; then
        return 1
    else
        return 0
    fi
}

#读取磁盘信息,设备路径,项名称
get_disk_info() {
    local dev_path=$1
    local item_str=$2
    G_RET=""

    if [ -z "$dev_path" ] || [ -z "$item_str" ]; then
        outerr "get_disk_info失败,参数不正确: path:${dev_path} , item name:{item_str}"
        return 1
    fi

    if ! file_exists $dev_path; then
        outerr "get_disk_info失败,设备文件不存在:$dev_path"
        return 1
    fi

    local devInfo="$(call_desc "获取磁盘${devStr}信息..." diskutil info $dev_path)"
    #local devInfo="$(diskutil info $dev_path)"
    if is_error; then
        return 1
    fi

    #local uuid=$(echo "$devInfo" | grep -o 'Volume UUID:.*' | sed 's/Volume UUID://')
    local value=$(echo "$devInfo" | grep -o "${item_str}:.*" | sed "s/${item_str}://")
    value=$(trim "$value")
    #media_name=$(echo "$devInfo" | grep -o 'Device / Media Name:.*' | sed 's/Device \/ Media Name://')
    #media_name=$(trim "$media_name")

    echo "$value"
    G_RET="$value"

    return 0
}

#得到磁盘uuid
get_disk_uuid() {
    local uuid=$(get_disk_info $1 "Volume UUID")
    local ret=$?
    if [ $ret == 0 ]; then
        if [ ${#uuid} != 36 ]; then
            outerr "uuid长度不对:${value}"
            return 1
        else
            echo $uuid
            G_RET=$uuid
            return 0
        fi
    else
        return $ret
    fi
}

#替换字符串
#原字符串,需要查找的,需要替换的.
str_replace() {
    #local src=$1
    #echo "${src//$2/$3}"
    oldStr="$1"  # 原字符串
    findStr="$2" # 需要查找的字符串
    replStr="$3" # 需要替换的字符串

    local new_str="${oldStr//$findStr/$replStr}"
    echo "$new_str"
}

#处理字符串中所有空白字符
trim_all() {
    local srcStr="$1"
    templ="$(str_replace "$srcStr" " " "")"
    templ="$(str_replace "$srcStr" "\t" "")"
    echo "$templ"
}

#字符串查找(源字符串,查找字符串)
str_find_regex() {
    local ret=$(echo "$1" | grep -oE "$2")
    if [ "$3" ]; then
        ret=$(echo "$ret" | grep -oE "$3")
    fi

    if [ "$ret" ]; then
        echo "$ret"
        return 0
    fi
    return 1
}

#退出进程-发送退出信号
ps_exit() {
    exec_desc "关闭进程:${1}" kill -INT $1
    return $?
}

#中止进程-强制退出
ps_kill() {
    exec_desc "中止进程:${1}" kill -KILL $1
    return $?
}

#读配置
read_config() {
    if ! file_exists "$CONFIG_FILE"; then
        outlog "读取配置${1}时,配置文件不存在:${CONFIG_FILE}"
        return 0
    fi

    local val="$(defaults read "$CONFIG_FILE" "$1")"
    echo "$val"
    return 0

    #不存在的key读出来也不会出错 - 所以下面就没用了
    #if is_success; then
    #   printf "$val"
    #else
    #   outlog "读取配置${1}时,出现错误:${CONFIG_FILE}"
    #  outlog "$val"
    #fi
}

#写配置
write_config() {
    local ret=$(defaults write "$CONFIG_FILE" "$1" "$2")
    if is_error; then
        outerr "保存配置失败${CONFIG_FILE},name:${1}:value:${2}"
        outerr "$ret"
        return 1
    fi

    return 0
}

#msg_query
msg_query() {

    cls

    while true; do
        echo -e "$1" >&2
        echo -e "请输入(y/n)" >&2

        read reply

        case $reply in
        n | N)
            return 1
            ;;
        y | Y)
            return 0
            ;;
        *)
            cls
            echo "输入错误!" >&2
            ;;
        esac
    done
}

#创建日志文件
if ! file_exists "$CONFIG_LOG_FILE"; then
    echo "" >"$CONFIG_LOG_FILE"
    chmod 777 "$CONFIG_LOG_FILE"
fi

#非root用户时清屏
if ! is_root; then
    cls
fi

echo $0
