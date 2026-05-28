# ShadowsocksR 项目架构说明

## 项目概述

ShadowsocksR (SSR) 是一个快速代理隧道工具，用于绕过防火墙。它是 Shadowsocks 项目的改进分支，在加密、混淆协议和多用户管理方面进行了大量增强。

## 整体架构

```
┌─────────────────────────────────────────────────────────────────────┐
│                          启动入口                                    │
│              server.py (主进程)  /  local.py (客户端)                │
└──────────────────┬──────────────────────────────────────────────────┘
                   │
        ┌──────────┴──────────┐
        ▼                     ▼
┌──────────────┐    ┌────────────────┐
│ server_pool   │    │  db_transfer   │
│ (线程1: 事件循环)│  │ (线程2: 用户管理) │
└──────┬───────┘    └───────┬────────┘
       │                    │
       │              ┌─────┴──────┐
       │              │            │
       ▼              ▼            ▼
┌──────────┐    ┌──────────┐  ┌──────────┐
│ TCPRelay │    │ UDPRelay │  │ API/DB   │
│ (TCP中继) │    │ (UDP中继) │  │ 流量上报  │
└──────────┘    └──────────┘  └──────────┘
```

## 目录结构

```
shadowsocksr/
├── server.py                    # 主入口：初始化 ServerPool + 数据同步线程
├── server_pool.py               # 单例模式 ServerPool：管理 TCP/UDP relay 实例池
├── asyncmgr.py                  # 管理通道（UDP 管理器，用于动态更新）
├── config.json                  # 基础配置文件（单用户模式）
├── mudb.json                    # 多用户配置文件（JSON 存储）
├── configloader.py              # 配置加载器：合并 config.json + mudb.json
├── apiconfig.py                 # API 接口配置
├── db_transfer.py               # 数据库传输层：
│   ├── TransferBase            #   - 基类：流量统计、用户更新
│   ├── DbTransfer              #   - v2 版：MySQL 传输（sspanelv2）
│   ├── Dbv3Transfer            #   - v3 版：增强 MySQL 传输（sspanelv3ssr）
│   └── MuJsonTransfer          #   - JSON 存储：多用户本地模式
├── mujson_mgr.py                # 多用户管理工具：增删改查用户
├── switchrule.py                # 开关规则：判断用户是否允许运行
├── importloader.py              # 动态模块加载器
├── initcfg.sh / initcfg.bat     # 初始化脚本（创建 user-config.json）
├── run.sh / logrun.sh / stop.sh / tail.sh  # 运行/后台运行/停止/查看日志
├── ssr.sh                       # 综合管理脚本
├── mujson_mgr.py                # 多用户 CLI 管理工具
├── setup.py                     # Python 包安装配置
├── Dockerfile                   # Docker 镜像构建文件
├── .travis.yml                  # CI 配置
│
├── shadowsocks/                 # 核心模块（可复用自 Shadowsocks 原版）
│   ├── __init__.py
│   ├── shell.py                 # 命令行解析、配置检查、版本信息
│   ├── common.py                # 通用工具：IPNetwork、PortRange、协议转换
│   ├── encrypt.py               # 加密模块：AES、RC4-MD5、Salsa20、ChaCha20 等
│   ├── encrypt_test.py          # 加密单元测试
│   ├── eventloop.py             # 事件循环（基于 epoll/select/kqueue）
│   ├── tcprelay.py              # TCP 中继核心：TCPRelay + TCPRelayHandler
│   ├── udprelay.py              # UDP 中继核心：UDPRelay
│   ├── asyncdns.py              # 异步 DNS 解析器
│   ├── daemon.py                # 守护进程化支持
│   ├── manager.py               # 管理器协议（用于外部控制）
│   ├── obfs.py                  # 混淆协议统一接口
│   ├── lru_cache.py             # LRU 缓存实现
│   ├── ordereddict.py           # 有序字典兼容层
│   ├── version.py               # 版本信息
│   │
│   ├── crypto/                  # 加密后端
│   │   ├── __init__.py          # 统一导出
│   │   ├── rc4_md5.py           # RC4-MD5 加密
│   │   ├── openssl.py           # OpenSSL 绑定（AES、ChaCha20 等）
│   │   ├── sodium.py            # libsodium 绑定
│   │   ├── table.py             # table 加密
│   │   ├── util.py              # 加密工具函数
│   │   ├── ctypes_libsodium.py  # ctypes 调用 libsodium
│   │   └── ctypes_openssl.py    # ctypes 调用 OpenSSL
│   │
│   └── obfsplugin/              # 混淆插件
│       ├── __init__.py          # 统一注册和加载
│       ├── plain.py             # 原始模式（无混淆）
│       ├── http_simple.py       # HTTP 简单混淆（伪装 HTTP）
│       ├── obfs_tls.py          # TLS 1.2 Ticket 混淆（伪装 HTTPS）
│       ├── verify.py            # Verify 系列（校验数据完整性）
│       ├── auth.py              # Auth 系列（auth_aes128_md5/sha1）
│       └── auth_chain.py        # Auth Chain 系列（auth_chain_a）
│
├── tests/                       # 测试套件
│   ├── test.py                  # 主测试入口
│   ├── nose_plugin.py           # Nose 测试插件
│   ├── coverage_server.py       # 覆盖率服务器
│   ├── *.json                   # 各种测试配置
│   ├── *.sh                     # 测试脚本
│   ├── libsodium/               # libsodium 安装脚本
│   └── socksify/                # SOCKS 代理配置
│
├── debian/                      # Debian/Ubuntu 打包
│   ├── control                  # 控制文件
│   ├── changelog                # 版本变更日志
│   ├── init.d/                  # SystemV 启动脚本
│   ├── ssserver.1 / sslocal.1   # 手册页
│   └── ...
│
├── utils/                       # 辅助工具
│   ├── autoban.py               # 自动封禁（检测暴力破解）
│   └── fail2ban/                # Fail2ban 规则配置
│
└── .claude/                     # Claude Code 配置
    └── settings.local.json
```

## 核心运行流程

### 1. 启动流程 (server.py)

```python
# 1. shell.check_python() - Python 版本检查
# 2. load_config() - 加载配置文件
# 3. get_config() - 获取配置（支持 mudbjson / sspanelv2 / sspanelv3ssr 接口）
# 4. 根据 API_INTERFACE 创建对应的 Transfer 线程:
#    - MuJsonTransfer (mudbjson)
#    - DbTransfer (sspanelv2)
#    - Dbv3Transfer (sspanelv3ssr)
# 5. ServerPool.get_instance() - 创建事件循环 + DNS 解析器
# 6. 主线程等待，子线程不断从数据库拉取用户数据并更新
```

### 2. ServerPool 架构

```
ServerPool (单例)
├── tcp_servers_pool      # IPv4 TCP 中继池 {port: TCPRelay}
├── tcp_ipv6_servers_pool # IPv6 TCP 中继池 {port: TCPRelay}
├── udp_servers_pool      # IPv4 UDP 中继池 {port: UDPRelay}
├── udp_ipv6_servers_pool # IPv6 UDP 中继池 {port: UDPRelay}
├── loop                  # EventLoop 事件循环
├── dns_resolver          # DNS 异步解析器
└── mgr                   # 管理通道管理器
```

### 3. 数据同步线程 (db_transfer)

```python
# 死循环中:
# 1. pull_db_all_user()    - 从数据库拉取所有用户信息
# 2. del_server_out_of_bound_safe() - 根据流量/开关状态启停服务
# 3. push_db_all_user()    - 将统计的流量推送到数据库
# 4. event.wait(UPDATE_TIME) # 定时唤醒
```

### 4. TCP 连接处理流程 (tcprelay.py)

```
客户端连接 → TCPRelay.server_socket.accept()
           → 创建 TCPRelayHandler
           → 状态机流转:
             STAGE_INIT → STAGE_ADDR → STAGE_DNS → STAGE_CONNECTING → STAGE_STREAM
           → 双向数据管道:
             上游(client→server): read local → encrypt → obfs → write remote
             下游(server→client): read remote → obfs → decrypt → write local
```

## 配置文件说明

### config.json (主配置)
```json
{
  "server": "0.0.0.0",              # 监听地址
  "server_port": 8388,               # 监听端口
  "password": "m",                   # 密码
  "method": "aes-128-ctr",           # 加密方式
  "protocol": "auth_aes128_md5",     # 协议插件
  "obfs": "tls1.2_ticket_auth_compatible",  # 混淆插件
  "timeout": 120,                    # 超时时间
  "additional_ports": {},            # 额外端口
  "fast_open": false                 # TCP Fast Open
}
```

### mudb.json (多用户数据)
```json
[
  {
    "user": "user1",
    "port": 8389,
    "passwd": "password1",
    "method": "aes-256-cfb",
    "protocol": "auth_aes128_md5",
    "obfs": "tls1.2_ticket_auth",
    "transfer_enable": 107374182400,  # 流量上限
    "u": 0, "d": 0,                   # 已用上行/下行
    "enable": 1                       # 1=启用, 0=禁用
  }
]
```

## 加密与混淆体系

### 加密方法 (crypto/)
| 方法 | 说明 |
|------|------|
| aes-128/192/256-ctr | AES 计数器模式 |
| aes-128/192/256-cfb | AES 密码反馈模式 |
| rc4-md5 | RC4 + MD5 密钥派生 |
| chacha20/chacha20-ietf | ChaCha20 |
| salsa20 | Salsa20 |
| table | 表替换加密 |

### 协议插件 (protocol)
| 协议 | 说明 |
|------|------|
| origin | 原始协议 |
| auth_sha1_v4 | 带认证的 SHA1 协议 |
| auth_aes128_md5 | AES128 认证协议 |
| auth_aes128_sha1 | SHA1 变体 |
| auth_chain_a | 链式认证 |

### 混淆插件 (obfs)
| 混淆 | 说明 |
|------|------|
| plain | 无混淆 |
| http_simple | HTTP 伪装 |
| http_post | HTTP POST 伪装 |
| tls1.2_ticket_auth | TLS 1.2 Ticket 认证 |
| tls1.2_ticket_fastauth | 快速 TLS 认证 |

## 关键设计模式

1. **单例模式**: ServerPool 使用单例，确保全局唯一
2. **工厂模式**: 加密方法、协议插件、混淆插件通过字典注册表动态创建
3. **观察者模式**: EventLoop 管理文件描述符的事件回调
4. **状态机模式**: TCPRelayHandler 使用状态机管理连接生命周期
5. **缓存策略**: LRU Cache 用于 UDP 会话缓存和在线用户状态
6. **多线程模型**: 主线程(事件循环) + 数据线程(数据库同步)

## 多用户工作原理

1. **用户数据源**: mudb.json 或 MySQL 数据库
2. **流量统计**: 每个 TCPRelayHandler 记录上传/下载量，定期汇总到用户级别
3. **用户切换**: protocol_param 中包含用户列表 (`uid:passwd#uid2:passwd2`)
4. **限速**: 支持 per_con (单连接) 和 per_user (每用户) 速度限制
5. **API 接口**: 支持 sspanelv2 / sspanelv3ssr / glzjinmod / legendsockssr 等多种 API

## 运行脚本

| 脚本 | 说明 |
|------|------|
| run.sh | 前台启动 |
| logrun.sh | 后台日志模式启动 |
| stop.sh | 停止服务 |
| tail.sh | 查看日志 |
| initcfg.sh | 初始化配置文件 |
| initmudbjson.sh | 初始化多用户数据库 |
| ssr.sh | 综合管理（安装/卸载/配置/升级） |
