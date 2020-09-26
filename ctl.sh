#!/usr/bin/env bash
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Author:   li.lei03@opg.cn
# Created:  2020-09-25
# Purpose:  DSFTP client controlor

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# global configs

FILE_THIS=$(basename ${BASH_SOURCE[0]})
DIR_HOME=$(dirname $(realpath ${BASH_SOURCE[0]}))

DIR_CONF=$DIR_HOME/conf
PATH_CONF_CLIENT=$DIR_CONF/client.conf
PATH_CONF_HTTP_TPL=$DIR_CONF/http.tpl
PATH_CONF_HTTP_HTML=$DIR_CONF/http.html

source $PATH_CONF_CLIENT || { echo "请初始化配置文件 $PATH_CONF_CLIENT"; exit 255; }

DIR_TMP=$DIR_HOME/tmp
DIR_MNT=$DIR_HOME/mnt
DIR_CACHE=$DIR_HOME/cache

DSFTP_PREFIX="sftp://$DSFTP_USER@$DSFTP_ENDPOINT:"
FLAGS_COMMON="-v --stats=30s --stats-one-line"
FLAGS_VFS="--dir-cache-time=1m --cache-dir=$DIR_CACHE --vfs-cache-mode=writes --vfs-cache-max-age=10m --vfs-cache-max-size=1g"
FLAGS_DSFTP=":sftp: --sftp-host=${DSFTP_ENDPOINT} --sftp-user=${DSFTP_USER} --sftp-pass=$(rclone obscure ${DSFTP_PASS})"

IS_LOGGING=1

HELP="$FILE_THIS - DSFTP客户端控制器 https://github.com/opgcn/dsftp-client

当前配置文件$PATH_CONF_CLIENT:
$(grep -E -v '^[[:space:]]*$|^[[:space:]]*#' conf/client.conf | sed 's/^/    /g')

用法:
    lftp    使用lftp工具交互式访问DSFTP
    sftp    使用sftp工具交互式访问DSFTP
    tree    使用rclone工具显示DSFTP的目录树
    lsl     使用rclone工具列取DSFTP中所有文件的大小/时间/路径
    size    使用rclone工具统计DSFTP中所有文件数量和大小
    explore 使用rclone工具以交互式方式访问DSFTP
    http    使用rclone工具代理DSFTP为本地HTTP协议服务
    ftp     使用rclone工具代理DSFTP为本地FTP协议服务
    nginx   显示nginx本地反代DSFTP四层SFTP协议的配置示例
    mount   使用sshfs工具将DSFTP挂载到本地 $DIR_MNT/
    umount  使用fusermount工具将本地挂载点取消
    help    显示此帮助
"

HELP_NCDU="交互式浏览器中快捷键提示：

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

HELP_RCLONE="
rm -rf $DIR_TMP \\
&& mkdir -p $DIR_TMP \\
&& cd $DIR_TMP \\
&& wget https://downloads.rclone.org/rclone-current-linux-amd64.zip \\
&& unzip rclone-current-linux-amd64.zip \\
&& cd rclone-*-linux-amd64 \\
&& sudo cp -f rclone /usr/bin/ \\
&& sudo chown root:root /usr/bin/rclone \\
&& sudo chmod 755 /usr/bin/rclone \\
&& sudo mkdir -p /usr/local/share/man/man1 \\
&& sudo cp rclone.1 /usr/local/share/man/man1/ \\
&& sudo mandb \\
&& cd $DIR_HOME \\
&& rm -rf $DIR_TMP \\
&& rclone version
"

HELP_NGINX="
# http://nginx.org/en/docs/ngx_core_module.html
user                nginx;
worker_processes    auto;
error_log           /var/log/nginx/error.log warn;
pid                 /var/run/nginx.pid;
include             /usr/share/nginx/modules/*.conf;

events {
    use                 epoll;
    multi_accept        on;
    worker_connections  1024;
} # events

# http://nginx.org/en/docs/stream/ngx_stream_core_module.html
stream {
    server {
        listen 1;  # 本地代理SFTP协议的端口
        proxy_pass $DSFTP_ENDPOINT:22;
    }
} # stream
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
    echoDebug FATAL "rclone工具未正确安装! 请参考 https://rclone.org/install/ , 或使用如下命令安装:" && echo "$HELP_RCLONE" && return 254
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

function checkSshpass
{
    [ "$(which sshpass 2> /dev/null)" ] && return 0
    echoDebug FATAL "sshpass工具未正确安装! 请使用'sudo yum install -y sshpass'等方式安装" && return 247
}

function getDsftpRcloneAddrOpts
{
    echo :sftp: --sftp-host=${DSFTP_ENDPOINT} --sftp-user=${DSFTP_USER} --sftp-pass=$(rclone obscure ${DSFTP_PASS})
}

function prepareHttpHtml
{
    sed "s|DSFTP_PREFIX|$DSFTP_PREFIX|g" $PATH_CONF_HTTP_TPL > $PATH_CONF_HTTP_HTML
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# process functions

function main
{
    declare sOpt="$1"
    if [ "$sOpt" == "help" ] || [ "$sOpt" == '' ]; then
        echo "$HELP"
    elif [ "$sOpt" == "lftp" ]; then
        checkConf && checkLftp \
        && runCmd lftp -u ${DSFTP_USER},${DSFTP_PASS} -e 'help' sftp://${DSFTP_ENDPOINT}
    elif [ "$sOpt" == "sftp" ]; then
        checkConf && checkSshpass \
        && runCmd sshpass -p ${DSFTP_PASS} sftp -C ${DSFTP_USER}@${DSFTP_ENDPOINT}
    elif [ "$sOpt" == "tree" ]; then
        checkConf && checkRclone \
        && runCmd rclone tree -aC --dirsfirst $FLAGS_DSFTP
    elif [ "$sOpt" == "lsl" ]; then
        checkConf && checkRclone \
        && runCmd rclone lsl $FLAGS_DSFTP
    elif [ "$sOpt" == "explore" ]; then
        checkConf && checkRclone \
        && read -n 1 -s -r -p "$HELP_NCDU" \
        && runCmd rclone ncdu $FLAGS_DSFTP
    elif [ "$sOpt" == "size" ]; then
        checkConf && checkRclone \
        && runCmd rclone size $FLAGS_DSFTP
    elif [ "$sOpt" == "http" ]; then
        checkConf && checkRclone && prepareHttpHtml \
        && runCmd rclone serve http $FLAGS_COMMON $FLAGS_VFS $DSFTP_PROXY_HTTP_OPTS --template $PATH_CONF_HTTP_HTML $FLAGS_DSFTP
    elif [ "$sOpt" == "ftp" ]; then
        checkConf && checkRclone \
        && runCmd rclone serve ftp $FLAGS_COMMON $FLAGS_VFS $DSFTP_PROXY_FTP_OPTS $FLAGS_DSFTP
    elif [ "$sOpt" == "nginx" ]; then
        checkConf && echo "$HELP_NGINX"
    elif [ "$sOpt" == "mount" ]; then
        sCmd1="echo ${DSFTP_PASS}"
        sCmd2="sshfs ${DSFTP_USER}@${DSFTP_ENDPOINT}:/ $DIR_MNT -C -o password_stdin,StrictHostKeyChecking=no,PreferredAuthentications=password,reconnect,ServerAliveInterval=15,ServerAliveCountMax=3"
        checkConf && checkSshfs && prepareMntDir \
        && echoDebug DEBUG "开始执行命令: $sCmd1 | $sCmd2" && $sCmd1 | $sCmd2 \
        && echoDebug INFO "sshfs调用结束，请查看目录 $DIR_MNT/ !"
    elif [ "$sOpt" == "umount" ]; then
        checkConf && checkSshfs \
        && runCmd fusermount -u $DIR_MNT
    else
        echoDebug ERROR "非法参数'$sOpt'! 请使用'$0 help'查看帮助"
        return 1
    fi
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# main process
main $@
