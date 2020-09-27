# dsftp-client

基于[lftp](http://lftp.tech/)、[rclone](https://rclone.org/)、[sshfs](https://github.com/libfuse/sshfs)等开源组件集成的[东珠DSFTP文件交换服务](http://dsftp.opg.cn)**示例客户端**。旨在方便租户侧接入/导出数据中台离线文件数据。它包括以下引人特性：

- 让用户可以通过交互式CLI/GUI的方式访问DSFTP；
- 让用户网络内可以使用HTTP浏览器访问DSFTP；
- 让用户将其DSFTP租户空间挂载为本地存储；
- 让用户将其DSFTP租户空间和自身多种存储（如OSS、S3、Ceph、本地磁盘等）进行自动化镜像同步；

## 1 安装和配置

依赖组件*rclone*可以使用[官方文档](https://rclone.org/install/)中建议的方式安装:
```bash
curl https://rclone.org/install.sh | sudo bash
```

依赖其它组件可以使用*yum*工具安装：
```bash
sudo yum install -y lftp fuse-sshfs sshpass
```

安装*ds-client*：
```bash
git clone https://github.com/opgcn/dsftp-client.git
```

初始化配置文件，并填写相关配置:
```bash
cd dsftp-client/
cp conf/client.conf.example conf/client.conf
vim conf/client.conf
```

查看命令行帮助:
```bash
chmod a+x ./ctl.sh
./ctl.sh help
```

*ds-client*的使用十分简单，配置完整后，只需要`./ctl.sh 子命令`调取相应的功能即可。

## 2 连接DSFTP

`conf/client.conf`中的以下配置项，决定从本地连接DSFTP及其租户空间：
- `DSFTP_HOST`: DSFTP的地址，注意公网对接和私网对接时不同；
- `DSFTP_USER`: DSFTP的租户ID，由数据中台产品经理提供；
- `DSFTP_PASS`: DSFTP的租户秘钥，由数据中台产品经理提供；

配置完成后，用户可以通过`lftp`、`sftp`、`explore`子命令交互式访问其DSFTP租户空间，也可使用`tree`、`list`、`size`列取DSFTP租户空间的文件信息。

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

一般的，DSFTP对单个租户只会放行单个IP白名单，当租户侧网络情况复杂时，建议租户侧工程师使用nginx等软件在四层反代DSFTP：
- 子命令`nginx`可以查看推荐的nginx配置；
- 租户侧工程师需要对代理服务器的入口白名单进行控制

## 4 挂载DSFTP

## 5 镜像DSFTP

## 6 其它说明

