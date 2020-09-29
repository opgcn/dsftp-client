#!/usr/bin/env bash
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Author:   li.lei03@opg.cn
# Created:  2020-09-25
# Purpose:  DSFTP client controlor

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# global configs

PATH_CONF_CLIENT=$(dirname $(realpath ${BASH_SOURCE[0]}))/conf/client.conf
source $PATH_CONF_CLIENT || { echo "无法加载配置文件'$PATH_CONF_CLIENT'，请检查！"; exit 255; }

IS_LOGGING=1
FILE_THIS=$(basename ${BASH_SOURCE[0]})
DSFTP_URI="sftp://$DSFTP_USER@$DSFTP_HOST"

HELP="$FILE_THIS - DSFTP客户端控制器 https://github.com/opgcn/dsftp-client

当前重要配置:
    DSFTP空间   $DSFTP_URI
    OTHER存储   $MIRROR_OTHER
    镜像方向    ${MIRROR_DIRECTION/ / ===(${MIRROR_METHOD})==> }
    挂载状态    $(mount -l | fgrep fuse.sshfs | fgrep $DSFTP_USER | cut -d' ' -f1,3 | sed 's| | ===(fuse.sshfs)==> |g')

用法:
    lftp        使用lftp工具交互式访问DSFTP
    sftp        使用sftp工具交互式访问DSFTP
    explore     使用rclone工具以交互式方式访问DSFTP
    tree        使用rclone工具显示DSFTP的目录树
    list        使用rclone工具列取DSFTP中所有文件的大小/时间/路径
    size        使用rclone工具统计DSFTP中所有文件数量和大小
    http        使用rclone工具代理DSFTP为本地HTTP服务, 端口$(echo $DSFTP_PROXY_HTTP_OPTS|egrep -o '[[:digit:]]+')
    ftp         使用rclone工具代理DSFTP为本地FTP服务, 端口$(echo $DSFTP_PROXY_FTP_OPTS|egrep -o '[[:digit:]]+')
    nginx       显示nginx本地反代DSFTP四层SFTP协议的配置示例
    mount       使用sshfs工具将DSFTP挂载到本地目录${DIR_MNT}
    lmount      列取正在进行中的sshfs挂载
    umount      使用fusermount工具取消本地挂载点${DIR_MNT}
    mirroronce  一次性使用rclone进行跨存储镜像同步
    mirrorloop  循环的使用rclone进行跨存储镜像同步
    daemon      显示部分命令后台运行的命令示例
    logrotate   轮转压缩${DIR_LOGS}目录中的日志
    help        显示此帮助
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

TPL_RCLONE="
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

TPL_NGINX="
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
        proxy_pass $DSFTP_HOST:22;
    }
} # stream
"

TPL_DAEMON="
# 日常以后台进程方式启动命令
subcmd=指定子命令 && nohup bash -l $(realpath ${BASH_SOURCE[0]}) \$subcmd >> $DIR_LOGS/\$subcmd.log 2>&1 &

# 开机自启后台进程，在crontab -e中加入
@reboot subcmd=指定子命令 && nohup bash -l $(realpath ${BASH_SOURCE[0]}) \$subcmd >> $DIR_LOGS/\$subcmd.log 2>&1 &

# 每天日志轮转，在crontab -e中加入
@daily bash -l $(realpath ${BASH_SOURCE[0]}) logrotate >> $DIR_LOGS/logrotate.journal 2>&1
"

TPL_LOGROTATE="# 此配置文件由 $(realpath ${BASH_SOURCE[0]}) 自动更新
$DIR_LOGS/*.log {
    daily
    rotate 30
    notifempty
    missingok
    dateext
    dateyesterday
    copytruncate
    compress
    compresscmd $(which xz)
    uncompresscmd $(which unxz)
    compressext .xz
    compressoptions -9
}
"

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# common functions

function echoDebug
# echo debug message
#   $1: debug level
#   $2: message string
{
    sPos=""
    for x in ${FUNCNAME[@]}; do
        [ "echoDebug" != "$x" ] && [ "runCmd" != "$x" ] && sPos="${sPos}${x}@"
    done
    if [ 1 -eq ${IS_LOGGING} ]; then
        echo -e "\e[7;93m[${sPos}${FILE_THIS} $(date +'%F %T') $1]\e[0m \e[93m$2\e[0m" >&2
    fi
}

function runCmd
{
    echoDebug DEBUG "命令: $*"
    $@
    nRet=$?; [ 0 -eq $nRet ] || echoDebug WARN "命令返回非零值: $nRet"
    return $nRet
}

function rcloneWrapper
{
    runCmd rclone -v --config=$PATH_CONF_RCLONE $@
}

function checkConf
{
    [ "$DSFTP_HOST" ] || { echoDebug FATAL "DSFTP_HOST 未配置!"; return 252; }
    [ "$DSFTP_USER" ] || { echoDebug FATAL "DSFTP_USER 未配置!"; return 251; }
    [ "$DSFTP_PASS" ] || { echoDebug FATAL "DSFTP_PASS 未配置!"; return 250; }
    return 0
}

function checkRclone
{
    [ "$(which rclone 2> /dev/null)" ] || { echoDebug FATAL "rclone工具未正确安装! 请参考 https://rclone.org/install/ , 或使用如下命令安装:"; echo "$TPL_RCLONE"; return 254; }
    return 0
}

function configRcloneDsftp
{
     rcloneWrapper config create DSFTP sftp host "$DSFTP_HOST" user "$DSFTP_USER" pass "$DSFTP_PASS" > /dev/null
}

function configRcloneLocal
{
    rcloneWrapper config create OTHER $MIRROR_OTHER > /dev/null
}

function checkLftp
{
    [ "$(which lftp 2> /dev/null)" ] || { echoDebug FATAL "lftp工具未正确安装! 请使用'sudo yum install -y lftp'等方式安装"; return 253; }
    return 0
}

function checkSshfs
{
    [ "$(which sshfs 2> /dev/null)" ] || { echoDebug FATAL "sshfs工具未正确安装! 请使用'sudo yum install -y fuse-sshfs'等方式安装"; return 249; }
    return 0
}

function prepareMntDir
{
    mkdir -p $DIR_MNT
    [ "$(ls -A $DIR_MNT)" ] && echoDebug ERROR "挂载目录 $DIR_MNT/ 非空, 请检查!" && return 248
    return 0
}

function checkSshpass
{
    [ "$(which sshpass 2> /dev/null)" ] || { echoDebug FATAL "sshpass工具未正确安装! 请使用'sudo yum install -y sshpass'等方式安装"; return 247; }
    return 0
}

function prepareHttpHtml
{
    sed "s|DSFTP_PREFIX|$DSFTP_URI|g" $PATH_CONF_HTTP_TPL > $PATH_CONF_HTTP_HTML
}

function doMirror
{
    [ "move" == "$MIRROR_METHOD" ] && MIRROR_METHOD="$MIRROR_METHOD --delete-empty-src-dirs --create-empty-src-dirs"
    checkConf && checkRclone && configRcloneDsftp && configRcloneLocal \
    && rcloneWrapper $MIRROR_METHOD $MIRROR_DIRECTION $OPTS_RCLONE_ORDER $OPTS_RCLONE_STATS
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# process functions

function parseOpts
{
    declare sOpt="$1"
    if [ "$sOpt" == "help" ] || [ "$sOpt" == '' ]; then
        echo "$HELP"
    elif [ "$sOpt" == "lftp" ]; then
        checkConf && checkLftp \
        && runCmd lftp -u ${DSFTP_USER},${DSFTP_PASS} -e 'help' sftp://${DSFTP_HOST}
    elif [ "$sOpt" == "sftp" ]; then
        checkConf && checkSshpass \
        && runCmd sshpass -p ${DSFTP_PASS} sftp -C ${DSFTP_USER}@${DSFTP_HOST}
    elif [ "$sOpt" == "tree" ]; then
        checkConf && checkRclone && configRcloneDsftp \
        && rcloneWrapper tree DSFTP: -aC --dirsfirst
    elif [ "$sOpt" == "list" ]; then
        checkConf && checkRclone && configRcloneDsftp \
        && rcloneWrapper lsl DSFTP:
    elif [ "$sOpt" == "explore" ]; then
        checkConf && checkRclone && configRcloneDsftp \
        && read -n 1 -s -r -p "$HELP_NCDU" \
        && rcloneWrapper ncdu DSFTP:
    elif [ "$sOpt" == "size" ]; then
        checkConf && checkRclone && configRcloneDsftp \
        && rcloneWrapper size DSFTP:
    elif [ "$sOpt" == "http" ]; then
        checkConf && checkRclone && configRcloneDsftp && prepareHttpHtml \
        && rcloneWrapper serve http DSFTP: $OPTS_RCLONE_STATS $OPTS_RCLONE_VFS $DSFTP_PROXY_HTTP_OPTS --template $PATH_CONF_HTTP_HTML
    elif [ "$sOpt" == "ftp" ]; then
        checkConf && checkRclone && configRcloneDsftp \
        && rcloneWrapper serve ftp DSFTP: $OPTS_RCLONE_STATS $OPTS_RCLONE_VFS $DSFTP_PROXY_FTP_OPTS
    elif [ "$sOpt" == "nginx" ]; then
        checkConf && echo "$TPL_NGINX"
    elif [ "$sOpt" == "mount" ]; then
        sCmd1="echo ${DSFTP_PASS}"
        sCmd2="sshfs ${DSFTP_USER}@${DSFTP_HOST}:/ $DIR_MNT $OPTS_SSHFS"
        checkConf && checkSshfs && prepareMntDir \
        && echoDebug DEBUG "命令: $sCmd1 | $sCmd2" && $sCmd1 | $sCmd2 \
        && echoDebug INFO "sshfs调用结束，请查看目录 $DIR_MNT/ !"
    elif [ "$sOpt" == "lmount" ]; then
        sCmd1="mount -l"
        sCmd2="fgrep fuse.sshfs"
        checkConf && checkSshfs \
        && echoDebug DEBUG "命令: $sCmd1 | $sCmd2" && $sCmd1 | $sCmd2 
    elif [ "$sOpt" == "umount" ]; then
        checkConf && checkSshfs \
        && runCmd fusermount -u $DIR_MNT
    elif [ "$sOpt" == "mirroronce" ]; then
        doMirror
    elif [ "$sOpt" == "mirrorloop" ]; then
        while true; do
            doMirror
            runCmd sleep $MIRROR_INTERVAL
        done
    elif [ "$sOpt" == "daemon" ]; then
        checkConf && mkdir -p $DIR_LOGS \
        && echo "$TPL_DAEMON"
    elif [ "$sOpt" == "logrotate" ]; then
        checkConf && mkdir -p $DIR_LOGS \
        && echo "$TPL_LOGROTATE" > $PATH_LOGROTATE_CONF \
        && runCmd logrotate -v -s $PATH_LOGROTATE_STATE $PATH_LOGROTATE_CONF
    else
        echoDebug ERROR "非法参数'$sOpt'! 请使用'$FILE_THIS help'查看帮助"
        return 1
    fi
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# main process
parseOpts $@
