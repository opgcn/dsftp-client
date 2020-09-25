#!/usr/bin/env bash
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Author:   li.lei03@opg.cn
# Created:  2020-09-25
# Purpose:  DSFTP client controlor

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# global configs

DIR_HOME=$(dirname $(realpath ${BASH_SOURCE[0]}))
DIR_TMP=$DIR_HOME/tmp
DIR_MNT=$DIR_HOME/mnt
FILE_THIS=$(basename ${BASH_SOURCE[0]})
PATH_CONF=$DIR_HOME/conf/client.conf

IS_LOGGING=1

HELP="
$FILE_THIS - DSFTP客户端控制器 https://github.com/opgcn/dsftp-client

用法:
    open    使用lftp工具交互式访问DSFTP
    rclone  对操作系统重新安装rclone工具
    tree    使用rclone工具显示DSFTP的目录树
    lsl     使用rclone工具列取DSFTP中所有文件的大小/时间/路径
    size    使用rclone工具统计DSFTP中所有文件数量和大小
    explore 使用rclone工具以交互式方式访问DSFTP
    mount   使用sshfs工具将DSFTP挂载到本地 $DIR_MNT/
    umount  使用fusermount工具将本地挂载点取消
    help    显示此帮助
"

HELP_NCDU="
交互式浏览器中快捷键提示：

 ↑      向上移动光标
 ↓      向下移动光标
 →      进入目录
 ←      返回上级目录
 c      显示各个目录包含文件数
 g      显示各个目录/文件大小百分比示意图
 n      按名称排序
 s      按大小排序
 C      按文件数排序
 d      删除当前目录/文件
 y      将当前路径复制到剪切板
 Y      显示当前路径
 ^L     刷新屏幕
 ?      显示此帮助
 q/ESC  退出交互式GUI浏览器

按任意键继续....
"

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# common functions

function echoDebug
# echo debug message
#   $1: debug level
#   $2: message string
{
    if [ 1 -eq ${IS_LOGGING} ]; then
        echo -e "\e[7;93m[$FILE_THIS $(date +'%F %T') $1]\e[0m \e[93m$2\e[0m" >&2
    fi
}

function runCmd
{
    echoDebug DEBUG "开始执行命令: $*"
    $@
    nRet=$?; [ 0 -eq $nRet ] || echoDebug WARN "命令返回非零值: $nRet"
    return $nRet
}

function checkConf
{
    [ -z "$DSFTP_ENDPOINT" ] && echoDebug FATAL "DSFTP_ENDPOINT 未配置!" && return 252
    [ -z "$DSFTP_USER" ] && echoDebug FATAL "DSFTP_USER 未配置!" && return 251
    [ -z "$DSFTP_PASS" ] && echoDebug FATAL "DSFTP_PASS 未配置!" && return 250
    return 0
}

function checkRclone
{
    [ "$(which rclone 2> /dev/null)" ] && return 0
    echoDebug FATAL "rclone工具未正确安装!" && return 254
}

function checkLftp
{
    [ "$(which lftp 2> /dev/null)" ] && return 0
    echoDebug FATAL "lftp工具未正确安装! 请使用'sudo yum install -y lftp'等方式安装" && return 253
}

function checkSshfs
{
    [ "$(which sshfs 2> /dev/null)" ] && return 0
    echoDebug FATAL "sshfs工具未正确安装! 请使用'sudo yum install -y fuse-sshfs'等方式安装" && return 249
}

function prepareMntDir
{
    mkdir -p $DIR_MNT
    [ -n "$(ls -A $DIR_MNT)" ] && echoDebug ERROR "目前目录 $DIR_MNT/ 非空, 请检查!" && return 248
    return 0
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# process functions

function main
{
    declare sOpt="$1"
    if [ "$sOpt" == "help" ] || [ "$sOpt" == '' ]; then
        echo "$HELP"
    elif [ "$sOpt" == "open" ]; then
        echoDebug INFO "开始使用lftp工具交互式访问DSFTP...."
        checkConf && checkLftp \
        && runCmd lftp -u ${DSFTP_USER},${DSFTP_PASS} -e 'help' sftp://${DSFTP_ENDPOINT}
    elif [ "$sOpt" == "rclone" ]; then
        echoDebug INFO "开始重新安装rclone工具...."
        runCmd rm -rf $DIR_TMP \
        && runCmd mkdir -p $DIR_TMP \
        && runCmd cd $DIR_TMP \
        && runCmd wget https://downloads.rclone.org/rclone-current-linux-amd64.zip \
        && runCmd unzip rclone-current-linux-amd64.zip \
        && runCmd cd rclone-*-linux-amd64 \
        && runCmd sudo cp -f rclone /usr/bin/ \
        && runCmd sudo chown root:root /usr/bin/rclone \
        && runCmd sudo chmod 755 /usr/bin/rclone \
        && runCmd sudo mkdir -p /usr/local/share/man/man1 \
        && runCmd sudo cp rclone.1 /usr/local/share/man/man1/ \
        && runCmd sudo mandb \
        && runCmd cd $DIR_HOME \
        && runCmd rm -rf $DIR_TMP \
        && runCmd rclone version
    elif [ "$sOpt" == "tree" ]; then
        echoDebug INFO "开始使用rclone工具列取DSFTP的目录树...."
        checkConf && checkRclone \
        && runCmd rclone tree -aC --dirsfirst :sftp: --sftp-host=${DSFTP_ENDPOINT} --sftp-user=${DSFTP_USER} --sftp-pass=$(rclone obscure "${DSFTP_PASS}")
    elif [ "$sOpt" == "lsl" ]; then
        echoDebug INFO "开始使用rclone工具列取DSFTP中所有文件的大小/时间/路径...."
        checkConf && checkRclone \
        && runCmd rclone lsl :sftp: --sftp-host=${DSFTP_ENDPOINT} --sftp-user=${DSFTP_USER} --sftp-pass=$(rclone obscure "${DSFTP_PASS}")
    elif [ "$sOpt" == "explore" ]; then
        echoDebug INFO "开始使用rclone工具以交互式方式访问DSFTP...."
        checkConf && checkRclone \
        && read -n 1 -s -r -p "$HELP_NCDU" \
        && runCmd rclone ncdu :sftp: --sftp-host=${DSFTP_ENDPOINT} --sftp-user=${DSFTP_USER} --sftp-pass=$(rclone obscure "${DSFTP_PASS}")
    elif [ "$sOpt" == "size" ]; then
        echoDebug INFO "开始使用rclone工具统计DSFTP中所有文件数量和大小...."
        checkConf && checkRclone \
        && runCmd rclone size :sftp: --sftp-host=${DSFTP_ENDPOINT} --sftp-user=${DSFTP_USER} --sftp-pass=$(rclone obscure "${DSFTP_PASS}")
    elif [ "$sOpt" == "mount" ]; then
        echoDebug INFO "开始使用sshfs工具将DSFTP挂载到本地目录 $DIR_MNT/ ...."
        sCmd1="echo ${DSFTP_PASS}"
        sCmd2="sshfs ${DSFTP_USER}@${DSFTP_ENDPOINT}:/ $DIR_MNT -C -o password_stdin,StrictHostKeyChecking=no,PreferredAuthentications=password,reconnect,ServerAliveInterval=15,ServerAliveCountMax=3"
        checkConf && checkSshfs && prepareMntDir \
        && echoDebug INFO "开始执行命令: $sCmd1 | $sCmd2" && $sCmd1 | $sCmd2 \
        && echoDebug INFO "sshfs调用结束，请查看目录 $DIR_MNT/ !"
    elif [ "$sOpt" == "umount" ]; then
        echoDebug INFO "开始使用fusermount工具取消挂本地载点 $DIR_MNT/ ...."
        checkConf && checkSshfs \
        && runCmd fusermount -u $DIR_MNT
    else
        echoDebug ERROR "非法参数 '$sOpt'"
        echo "$HELP"
        return 1
    fi
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# main process

source $PATH_CONF
if [ 0 -ne $? ]; then
    echoDebug FATAL "无法加载配置文件 $PATH_CONF"
    exit 255
fi
main $@
