#!/bin/bash

#macos服务管理

#https://hanleylee.com/articles/manage-process-and-timed-task-by-launchd/

#全局返回变量

#服务名
SERVICE_NAME="app.eatm.service"

#安装类型
SERVICE_TYPE="root"
#root   -开机时加载-暂时仅支持root类型安装
#user   -当前用户登录时加载
#all    -所有用户登录时加载

#加载自动运行   逻辑值 true/false
SERVICE_AUTORUN="true"

#服务可执行路径与参数
SERVER_EXEC_FILE=""
SERVER_EXEC_ARGS=""

#自动执行命令,按照是否root用户,是否需要sudo
_service_exec() {
    #命令
    local cmd_str=$1
    #命令数组- 从第3个开始截取参数
    local params=(${@:2})

    local cmd_output
    if [ "$SERVICE_TYPE" = "root" ]; then
        cmd_output="$(sudo ${cmd_str} ${params[@]} 2>&1)"
    else
        cmd_output="$(${cmd_str} ${params[@]} 2>&1)"
    fi

    local errcode=$?

    if ! is_stdout; then
        echo "$cmd_output"
    fi

    return $errcode
}

#判断服务是否安装
service_is_install() {
    local ret

    if _service_exec launchctl list $SERVICE_NAME; then
        return 0
    fi

    return $?
}

#得到服务pid
service_pid() {
    local ret

    ret="$(_service_exec launchctl list $SERVICE_NAME)"

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
    if ! _service_exec launchctl stop $SERVICE_NAME; then
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
    if ! _service_exec launchctl start $SERVICE_NAME; then
        outerr "启动服务失败:$?"
        return 1
    fi

    outlog "等待服务启动..."
    local i=1
    local MAX=10
    while [ $i -le $MAX ]; do
        if  service_is_run; then
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
    sudo launchctl remove com.easy.ramdisk
}
