#!/bin/bash

#macos服务管理

#https://hanleylee.com/articles/manage-process-and-timed-task-by-launchd/

#全局返回变量

#服务名
_SERVICE_NAME="app.eatm.service"

#安装类型
_SERVICE_TYPE="root"
#root   -开机时加载-暂时仅支持root类型安装
#user   -当前用户登录时加载
#all    -所有用户登录时加载

#加载自动运行   逻辑值 true/false
_SERVICE_AUTORUN="true"

#服务可执行路径与参数
_SERVER_EXEC_FILE=""
_SERVER_EXEC_ARGS=""

_SERVICE_EXIT_TIMEOUT=30

#配置服务 _SERVICE_NAME [_SERVICE_AUTORUN] [_SERVICE_EXIT_TIMEOUT] _SERVER_EXEC_FILE [_SERVER_EXEC_ARGS]
service_config() {
    _SERVICE_NAME=$1
    _SERVICE_AUTORUN=$2
    _SERVICE_EXIT_TIMEOUT=$3
    _SERVER_EXEC_FILE=$(to_abs_path "$4")
    _SERVER_EXEC_ARGS="$5"

    #不定长度参数
    for i in "${@:6}"; do
        _SERVER_EXEC_ARGS+=("$i")
    done
}

#是否root用户服务
service_is_root() {
    if [ "$_SERVICE_TYPE" = "root" ]; then
        return 0
    else
        return 1
    fi
}

#得到服务的配置文件 路径
service_get_config_path() {
    if service_is_root; then
        echo "/Library/LaunchDaemons/${_SERVICE_NAME}.plist"
    else
        echo cfPath="$HOME/Library/LaunchAgents/${_SERVICE_NAME}.plist"
    fi
}

#自动执行命令,按照是否root用户,是否需要sudo
_service_exec() {
    #命令
    local cmd_str=$1
    #命令数组- 从第3个开始截取参数
    local params=(${@:2})

    local cmd_output
    if service_is_root; then
        cmd_output="$(sudo ${cmd_str} ${params[@]} 2>&1)"
    else
        cmd_output="$(${cmd_str} ${params[@]} 2>&1)"
    fi

    local errcode=$?

    #if ! is_stdout; then
    echo "$cmd_output"
    #fi

    return $errcode
}

service_install() {
    local argsStr=""
    for f in "${_SERVER_EXEC_ARGS[@]}"; do
        local item="<string>"${f}"</string>"
        argsStr+="$item"
    done

    local plistText='
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>'${_SERVICE_NAME}'</string>
                <key>ProgramArguments</key>
                <array>
                    <string>'${_SERVER_EXEC_FILE}'</string>
                    '${argsStr}'
                </array>
                <key>RunAtLoad</key>
                <'${_SERVICE_AUTORUN}' />
                <key>ExitTimeOut</key>
                <integer>'${_SERVICE_EXIT_TIMEOUT}'</integer>
            </dict>
        </plist>
    '

    local cfPath="$(service_get_config_path)"

    write_file "${cfPath}" "$plistText"
    
    if ! _service_exec launchctl load -w "${cfPath}"; then
        outerr "安装服务失败"
        return 1
    fi

    sudo chmod 777 "${cfPath}"

    outlog "安装服务成功!"
    return 0
}

#判断服务是否安装
service_is_install() {
    _service_exec launchctl list $_SERVICE_NAME
    if is_success; then
        return 0
    else
        return 1
    fi
}

#得到服务pid
service_pid() {
    local ret

    ret="$(_service_exec launchctl list $_SERVICE_NAME)"

    if ! is_success; then
        outerr "获取服务pid失败,可能服务不存在"
        return $?
    fi

    local pid=$(str_find_regex "$ret" '"PID"\s*=\s*([0-9]+);' '\d+')

    if is_success; then

        if ! is_stdout; then
            echo $pid
        fi

        return 0
    fi

    if str_find_regex "$ret" '"LastExitStatus"\s*=\s*([0-9]+);' '\d+'; then
        outerr "获取服务PID失败,服务没有运行!"
    else
        outerr "获取服务PID失败,未知错误:${ret}!"
    fi

    return 1
}

#判断服务是否正在运行
service_is_run() {
    local pid=$(service_pid)

    if [ "$pid" ]; then
        return 0
    else
        return 1
    fi
}

#停止服务
service_stop() {

    outlog "停止服务..."
    if ! _service_exec launchctl stop $_SERVICE_NAME; then
        outerr "停止服务失败:$?"
        return 1
    fi

    outlog "等待服务停止..."
    local i=1
    local MAX=180
    while [ $i -le $MAX ]; do
        if ! service_is_run; then
            outlog "服务已停止!"
            return 0
        fi

        sleep 1
        #echo "当前第${i}次循环"
        i=$((i + 1))
    done

    outerr "等待服务停止超时!"
    return 1
}

#启动
service_start() {

    outlog "启动服务..."
    if ! _service_exec launchctl start $_SERVICE_NAME; then
        outerr "启动服务失败:$?"
        return 1
    fi

    outlog "等待服务启动..."
    local i=1
    local MAX=10
    while [ $i -le $MAX ]; do
        if service_is_run; then
            outlog "服务已启动!"
            return 0
        fi

        sleep 1
        i=$((i + 1))
    done

    outerr "等待服务启动超时!"
    return 1
}

#删除服务
service_remote() {

    outlog "删除服务..."
    if ! _service_exec launchctl remove $_SERVICE_NAME; then
        outerr "删除服务失败"
    fi

    local cfPath="$(service_get_config_path)"

    if ! file_exists "${cfPath}"; then
        outerr "服务配置文件不存在:${cfPath}!"
        return 1
    fi

    if [ "$_SERVICE_TYPE" = "root" ]; then
        exec_desc "删除服务配置文件" sudo rm -f "${cfPath}"
    else
        exec_desc "删除服务配置文件" rm -f "${cfPath}"
    fi
}
