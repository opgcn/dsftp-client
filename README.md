# dsftp-client

基于[lftp](http://lftp.tech/)、[rclone](https://rclone.org/)、[sshfs](https://github.com/libfuse/sshfs)等开源组件集成的[东珠DSFTP文件交换服务](http://dsftp.opg.cn)**示例客户端**，旨在让租户以最低的开发代价与总部数据中台进行数据文件**传输**（接入/导出）。它包括以下引人的特性：

- 简单配置地址、用户、秘钥后，租户马上可以通过交互式CLI/GUI的方式访问DSFTP，加速联调对接；
- 租户可以将DSFTP中的文件内容以HTTP方式代理给租户网络中的非技术人员，在浏览器中查看；
- 租户工程师可以将DSFTP存储挂载为本地目录，方便快速开发数据读写程序；
- 租户可以将DSFTP租户空间和自身多种存储（如OSS、S3、Ceph、本地磁盘等）进行异步镜像同步，回避网络抖动；

## 1 安装和配置

依赖的组件*rclone*可以使用[官方文档](https://rclone.org/install/)中建议方式进行安装:
```bash
yum install -y https://downloads.rclone.org/v1.53.3/rclone-v1.53.3-linux-amd64.rpm
```

依赖其它组件可以使用*yum*工具安装：
```bash
sudo yum install -y lftp fuse-sshfs sshpass
```

安装*ds-client*：
```bash
git clone https://github.com/opgcn/dsftp-client.git
cd dsftp-client/
chmod a+x ./ctl.sh
```

初始化配置文件，并填写*DSFTP*的地址等信息:
```bash
cp conf/client.conf.example conf/client.conf
vim conf/client.conf
```
`conf/client.conf`中的以下配置项，决定从本地连接DSFTP及其租户空间：
- `DSFTP_HOST`: DSFTP的地址，注意公网对接和私网对接时不同；
- `DSFTP_USER`: DSFTP的租户ID，由数据中台产品经理提供；
- `DSFTP_PASS`: DSFTP的租户秘钥，由数据中台产品经理提供；

验证DSFTP的网络可达性及租户可用性:
```bash
./ctl.sh help
./ctl.sh isvalid
```

*ds-client*的使用十分简单，配置完整后，只需要`./ctl.sh 子命令`调取相应的功能即可。

## 2 直接访问DSFTP

用户可以通过`lftp`、`sftp`、`explore`子命令交互式访问其DSFTP租户空间，也可使用`tree`、`list`、`size`列取DSFTP租户空间的文件信息。

以上代理方式均为同步传输，无法抵抗网络抖动，建议仅作为交互式联调作用使用。

## 3 代理DSFTP

### 3.1 HTTP代理

用户侧非技术人员期望通过浏览器方式查看DSFTP内文件时，租户侧工程师可以在其网络内开启HTTP代理：
- `conf/client.conf`中的`DSFTP_PROXY_HTTP_OPTS`配置项定义了HTTP代理服务的端口、用户名、密码
- 子命令`http`可以启动HTTP服务
- 租户侧工程师需要对代理服务器的入口白名单进行控制

### 3.2 FTP代理

*ds-client*和*DSFTP*之间是强制使用SFTP连接的（以保证跨系统通信链路的安全），当租户侧其它系统期望使用*FTP*协议访问时，租户侧工程师可以在其网络内开启FTP代理：
- `conf/client.conf`中的`DSFTP_PROXY_FTP_OPTS`配置项定义了FTP代理服务的端口、用户名、密码
- 子命令`ftp`可以启动FTP服务
- 租户侧工程师需要对代理服务器的入口白名单进行控制

### 3.3 SFTP代理

一般的，DSFTP对单个租户只会放行单个IP白名单，当租户侧网络情况复杂时，建议租户侧工程师使用nginx等软件在四层反代DSFTP的*SFTP*协议：
- 子命令`nginx`可以查看推荐的nginx配置；
- 租户侧工程师需要对代理服务器的入口白名单进行控制

以上代理方式均为同步传输，可用性同时受限于远端DSFTP的可用性及本地代理服务的可用性。

## 4 挂载DSFTP

在数据接入/导出数据中台的过程中，如果租户侧期望尽可能的简化开发成本，只通过`cp`、`mv`等本地方式上传、下载文件，可以通过将DSFTP的租户空间挂载为本地目录来实现:
- 子命令`mount`实现挂载；
- 子命令`lmount`显示目前挂载状态列表；
- 子命令`umount`取消挂载；

此方式为同步传输，无法抵抗网络抖动，生产环境读写逻辑需要租户侧需要额外的监控和异常处理。

## 5 镜像DSFTP

*镜像*是指将DSFTP租户空间中的文件，自动化同步到租户的其它存储系统（如租户的OSS、租户自建的FTP等）中，或相反的过程。*dsftp-client*在`conf/client.conf`中提供以下参数，用以描述*镜像*功能相关配置：
- `MIRROR_OTHER`表示租户侧其它存储系统的配置信息，采用`存储类型 配置项1 配置值1 配置项2 配置值2 配置项3 配置值3 .....`的形式，例如：
  - *OSS*存储: `s3 provider Alibaba endpoint OSS的地域内网终端节点 env_auth false access_key_id 填写AK secret_access_key 填写SK`
  - *SFTP*存储: `sftp host 租户侧其它SFTP地址 user 用户名 pass 密码`
  - *FTP*存储: `ftp host 租户侧FTP地址 user 用户名 pass 密码`
  - 本地磁盘存储: `local`
- `MIRROR_DIRECTIONS`镜像方向数组，支持配置多个，且满足`源存储系统标识:源存储位置 目标存储标识:目标存储位置`的格式：
  - 存储系统标识：`DSFTP`标识租户的DSFTP存储空间，`OTHER`标识租户的其它存储系统。
  - 存储位置: 对于对象存储为`桶名/对象前置`，块存储为`/绝对路径目录/`
  - 例如:
    - 假设`OTHER`被配置为本地存储，`DSFTP:writable/ OTHER:/root/mirror`表示从DSFTP的`writable/`到本地的`/root/mirror`目录
    - 假设`OTHER`被配置为对象存储，`OTHER:abc/data DSFTP:writable/abc/`表示从对象存储`abc`桶的`data`前缀路径到DSFTP的`writable/abc/`目录
- `MIRROR_METHOD`镜像方式：
  - `copy`，增量复制方式，如果目标中包括源中不存在的文件，不会删除目标上的文件
  - `move`，增量移动方式，类似copy，但是复制完成后会删除源存储中文件
  - `sync`，增量强制方式，如果目标中包括源中不存在的文件，会删除目标上的文件，也不会删除源上的文件
  - 一般`copy`方式即可
- `MIRROR_INTERVAL`：该参数代表任意两次`mirrorloop`子命令中`mirroronce`之间间隔的秒数

配置完成后，通过使用的子命令有：
- `mirroronce`会以前台进程一次性方式进行不停歇的镜像同步；
- `mirrorloop`会以前台进程循环方式进行不停歇的镜像同步；

这是数据中台的**推荐方式**，它通过**异步传输**的方式，将租户侧*数据编解码逻辑*和*数据传输逻辑*完全解耦。易用性、稳定性、可维护性最高。例如，租户侧可以配置`MIRROR_OTHER=local`、`MIRROR_METHOD=move`、`MIRROR_DIRECTIONS[1]="OTHER:/home/root/upload-to-dsftp/ DSFTP:writable/uploaded-from-mirror/"`，实现本地`/home/root/upload-to-dsftp/`目录中的子目录及文件增量异步移动到DSFTP的租户目录`writable/uploaded-from-mirror/`下，实现离线文件接入数据中台。这样，既不影响租户侧本地的数据文件生成逻辑，也能对抗网络的不稳定性实现具备自愈能力的数据文件传输。

## 6 后台运行

默认情况下，`http`协议转换代理、`ftp`协议转换代理、`mirrorloop`循环镜像同步等子命令都是前台运行的，如果我们期望以后台方式运行，可以通过`daemon`方式查看触发命令示例：
- 它同时给出了日常后台运行和开机自启的方式；
- 它建议将日志增量输出到`logs/${子命令}.log`；

同时，`logrotate`命令可以对`logs/*.log`进行按天轮转，压缩或丢弃历史日志。

此外，如果租户侧如果会自行配置`supervisord`、`systemd`、`initd`，会是更好的选择。

## 7 其它说明

- *dsftp-client*仅作为**示例业务侧离线文件传输客户端**，由于其组件均为开源工具且在业务侧服务器中运行，中台提供技术支持，但不便提供SLA保障。
- *dsftp-client***仅包括文件传输而非文件处理**，业务侧**CSV文件的编解码需求**可参考中台示例的[dscsv项目](https://github.com/opgcn/dscsv)。
