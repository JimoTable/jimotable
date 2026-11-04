本轮支持 Linux amd64（x86-64）；ARM64 暂未验收。

# 社区版单机自托管

本文说明如何在一台 Linux 主机上部署 jimoTable 社区版。部署包默认包含 PostgreSQL 18.6、内置前端的 API、Worker、一次性数据库角色初始化任务，以及统一运维脚本。

## 适用范围

最低建议配置为 2 vCPU、4 GiB 内存和 20 GiB 可用磁盘。首版只支持单机 Docker Compose 和本地文件卷；不包含内置 TLS、S3/MinIO、多节点高可用、在线无停机备份或真实 AI Provider。默认关闭外部 AI 投递，附件、导入和异步 Schema 任务仍可用。

API 只监听宿主机 `127.0.0.1`。PostgreSQL 和 Worker 没有宿主端口，公网访问必须经过 HTTPS 反向代理。

## 数据库版本与环境边界

线上新部署和 Free 自托管默认使用 PostgreSQL 18，镜像由 `.env` 的 `JIMOTABLE_POSTGRES_IMAGE` 指定，当前固定为 `postgres:18.6-alpine`；数据库和角色初始化容器使用同一镜像。PG18 数据卷挂载到 `/var/lib/postgresql`，默认数据库目录为 `/var/lib/postgresql/18/docker`。

现有 dev 环境不调整：`dev/compose.yml`、`demo/compose.yml` 及正在运行的开发数据库沿用原配置。旧 PG16/17 数据目录不能直接供 PG18 使用；应另建 PG18 实例，通过单独验证的导出/恢复或大版本升级流程迁移。这里的 `upgrade` 命令只升级 jimoTable 应用，不执行 PostgreSQL 大版本升级。

## 安装

主机需要 Docker Engine 24+、Docker Compose v2、OpenSSL、curl 和 jq（Linux 推荐安装 util-linux 的 flock 实现进程锁，在无 flock 的环境自动优雅降级为 POSIX 目录锁）。运维入口会主动检查所需命令，Compose 文件使用 v2 的健康依赖和等待能力。 下载发布页中的 `jimotable-free-<version>.tar.gz` 与 `SHA256SUMS` 后先校验：

```bash
sha256sum -c SHA256SUMS
tar -xzf jimotable-free-0.2.1.tar.gz
cd jimotable-free-0.2.1
./selfhost/jimotable.sh init
```

macOS 可将 `sha256sum` 换为 `shasum -a 256`。`init` 会复制最小化 `.env.example` 为 `.env`，并在 `selfhost/secrets/` 生成持久密钥。该目录权限为 `0700`，文件为 `0600`。如果已有 PostgreSQL 卷却缺少匹配密钥，脚本会拒绝生成新密钥；此时必须恢复同一套备份。

检查 `.env` 中的公开地址和端口，然后启动：

```bash
./selfhost/jimotable.sh up
./selfhost/jimotable.sh bootstrap
./selfhost/jimotable.sh verify
```

`up` 会先拉取 `ghcr.io/jimotable/jimotable:<version>`。拉取失败时，只有本地已存在指定镜像才会继续；安装脚本不会自动构建源码。`bootstrap` 等待 API 健康后创建一年期 operator，并只保存到 `selfhost/operator.json`；命令不会输出原始 Token。成功后 bootstrap secret 会立即轮换并重建 API，数据库中的一次性声明保证凭证只创建一次；已有有效 operator 时再次执行会验证并复用。

初始化中断后可重新执行 `bootstrap`：即使凭证已经保存、阶段标记尚未更新，也会补齐密钥轮换。恢复前和 API 重载后均验证 operator；失败保留凭证和阶段文件，验证成功才清除阶段。

确实需要读取原始凭证时必须显式确认：

```bash
./selfhost/jimotable.sh operator-show --yes
```

请将 `selfhost/secrets/`、`.env` 和 `selfhost/operator.json` 视为同等级敏感材料。不要提交到 Git，不要发送到聊天或工单，也不要只备份数据库而遗漏这些文件。

## HTTPS 反向代理

将 DNS 指向主机，防火墙只开放 80/443。下面示例假设 `.env` 中 `JIMOTABLE_PUBLIC_BASE_URL=https://table.example.com`。

### Caddy

```caddyfile
table.example.com {
    encode zstd gzip
    reverse_proxy 127.0.0.1:8080
}
```

### Nginx

```nginx
server {
    listen 443 ssl http2;
    server_name table.example.com;

    ssl_certificate /etc/letsencrypt/live/table.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/table.example.com/privkey.pem;

    client_max_body_size 105m;
    location / {
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_pass http://127.0.0.1:8080;
    }
}
```

修改公开地址后运行 `./selfhost/jimotable.sh up` 使容器重建。不要把 Compose 端口绑定改为 `0.0.0.0`。

## 社区版 Quota

Free 社区版内置最高额度（`.env` 可调低）：每租户最多 2 个 Base，每 Base 最多 20 张表，每表最多 30 个字段；每租户所有表合计最多 2,000,000 条记录，单表最多 100,000 条；每租户附件总容量为 1 GiB。AI 并发默认仍为每租户 4。

运行时有效值始终为“数据库策略与部署上限中的较小值”。因此可以保存更低的自定义策略；提高数据库策略不能绕过部署上限。降低 `.env` 后会立即停止新增超额资源，但不会删除既有数据；已有超额数据仍可读取和清理。 超过部署上限的策略更新会返回 HTTP 400 与 `DEPLOYMENT_QUOTA_LIMIT_EXCEEDED`。

## 日常运维

```bash
./selfhost/jimotable.sh status
./selfhost/jimotable.sh logs
./selfhost/jimotable.sh logs api
./selfhost/jimotable.sh down
```

`status` 在 operator 距离过期少于 30 天时告警。轮换会签发新的一年期凭证，旧凭证保留 10 分钟：

```bash
./selfhost/jimotable.sh operator-rotate
./selfhost/jimotable.sh verify
```

`verify` 在凭证剩余不足 7 天时失败，便于接入监控或定时巡检。

## 备份与恢复

```bash
backup_id=$(./selfhost/jimotable.sh backup)
./selfhost/jimotable.sh restore "$backup_id" --yes
```

备份前脚本会预检磁盘空间，停止 API/Worker 形成一致的停写点，然后保存 `pg_dump -Fc`、应用数据卷、`.env`、Compose、全部 secrets 和 operator 凭证。每个文件都写入 SHA-256 清单，全部成功后才原子发布备份目录；无论成功或失败，原先运行的服务都会恢复。普通备份只保留最近 7 份。

恢复具有破坏性，必须提供 `--yes`。脚本先校验全部哈希和备份中的 PostgreSQL 大版本；版本不同或旧备份未记录版本时拒绝恢复，需要使用对应旧版本工具或单独迁移。检查通过后再替换数据库、应用卷、环境配置和密钥，保留当前 Compose 文件和目标项目名，重新应用最小权限数据库角色并自动运行 `verify`。 建议定期把整个 `selfhost/backups/` 加密复制到另一台主机，并实际演练恢复。

## 升级与回滚

```bash
./selfhost/jimotable.sh upgrade 0.2.1
```

升级命令校验版本、创建不自动清理的 `upgrade-*` 迁移备份、拉取新镜像、运行 Liquibase、重建 API/Worker 并执行验收。不支持直接降级。如果升级失败，按命令提示把 `.env` 中版本改回原版本，然后恢复对应的升级前备份：

```bash
./selfhost/jimotable.sh restore upgrade-YYYYMMDDTHHMMSSZ --yes
```

## 逐项验收

每次安装、恢复或升级后执行：

```bash
docker compose --env-file .env -f docker-compose.free.yml config --quiet
./selfhost/jimotable.sh status
./selfhost/jimotable.sh verify
docker compose --env-file .env -f docker-compose.free.yml restart api worker
docker compose --env-file .env -f docker-compose.free.yml up -d --wait api worker
./selfhost/jimotable.sh verify
```

还应人工确认：浏览器通过 HTTPS 打开前端；PostgreSQL 与 Worker 未暴露宿主端口；创建第 2 个 Base 成功而第 3 个原子失败；每 Base 第 20 张表成功而第 21 张失败；附件和导入文件在重启后仍存在；日志中不存在 operator Token、bootstrap secret、JWT key 或数据库密码；一次备份、状态变更、恢复后数据回到备份时状态。

排障时优先查看 `./selfhost/jimotable.sh logs api` 和 `logs worker`。密钥缺失、数据库角色错误、迁移失败和镜像拉取失败都按 fail-closed 处理，不应通过删除卷或重建密钥来“修复”。


现有安装升级时，需要同步 `.env` 中的总记录额度和每 Base 表数。数据库中已保存的较低租户或用户策略仍然生效，升级不会自动提高自定义策略；应检查 `/v1/tenant/quota` 与 `/v1/tenant/hierarchy-quota` 的有效额度，并按需要显式调整。


## Free 版本约束（0.2.1）

每个 Free 安装实例仅支持 1 个业务租户（包括已停用但仍保留的租户）。下列额度是镜像内置最高额度，修改环境变量不能调高；管理员可在上限内分配或调低。

从旧版升级前请检查租户数量并备份。多租户数据库不能直接升级至此 Free 镜像；脚本会拒绝升级，API/Worker 启动时也会检查，不会自动删除租户。请保留旧版本并单独迁移。
