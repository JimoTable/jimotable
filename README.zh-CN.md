# jimoTable Free SelfHost

本轮支持 Linux amd64（x86-64）。ARM64 暂未完成验收，不属于本轮支持范围。

[English](README.md) | [简体中文](README.zh-CN.md)

基于 PostgreSQL 的多维表格与 Agent API，提供网页数据管理、关联字段、附件和后台任务。

## 安装

本目录为 Free 公开发行内容，与公开仓库 https://github.com/jimotable/jimotable 内容一致。安装包可从 https://jimotable.jimo.studio/releases/ 下载，校验附带的 SHA256SUMS 后再解压进入安装目录；也可以直接克隆仓库执行下列步骤。在线沙箱：https://app.jimotable.jimo.studio。

Linux 主机需要 Docker Engine 24+、Docker Compose v2、curl、jq、OpenSSL；建议至少 2 vCPU、4 GiB 内存和 20 GiB 可用磁盘。运行：

```bash
./quickstart.sh
```

也可分步执行：

```bash
./selfhost/jimotable.sh init
./selfhost/jimotable.sh up
./selfhost/jimotable.sh bootstrap
./selfhost/jimotable.sh verify
```

默认访问 http://127.0.0.1:8080。自定义端口及公开地址请在首次启动前修改 `.env`。查看管理员凭证使用 `./selfhost/jimotable.sh operator-show --yes`，不要把凭证发送给他人。

公开发布镜像为 `ghcr.io/jimotable/jimotable:0.2.1`，可匿名拉取。候选验收由维护者提供指定镜像，不能用旧的本地缓存证明新版本可用。

## Free 默认配置

每个安装实例最多 **2 个 Base**，每 Base 最多 **20 张表**，每表最多 **30 个字段**；每租户所有表合计最多 **2,000,000 条记录**，单表最多 **100,000 条**；每租户附件总容量为 **1 GiB**。

- 数据库默认 `postgres:18.6-alpine`，单机 Docker Compose 部署。
- 附件和导入文件使用本地持久卷，默认不配置 S3/MinIO。
- AI 适配器默认 `mock`，外部 AI 投递关闭；真实模型调用需要单独配置与验证。附件、导入及异步 Schema 任务仍可用。
- API 只绑定宿主 `127.0.0.1`，公网访问需配置 HTTPS 反向代理。数据库与 Worker 不暴露宿主端口。
- 包含备份与恢复工具；不承诺多节点高可用、无停机备份或固定 RPO/RTO。

## Agent 技能

工作区技能见 [skills/jimotable-workspace/](skills/jimotable-workspace/)，Base 数据技能见 [skills/jimotable-base-api/](skills/jimotable-base-api/)。按所用 Agent 工具的本地技能机制加载相应目录，并配置独立凭证。

两个技能均已发布在本仓库 `skills/` 下，复制到所用 Agent 工具的本地技能目录即可。`npx skills add` 远程安装链路尚未核验，因此不提供。工作区 Agent 使用 `AGENT_USER` 凭证；Base Agent 使用发布后的 Base API 及其受限凭证。

## 模拟演示

```bash
./demo/simulate-agent.sh
```

该脚本只打印虚构的 CRM 流程，不发送 HTTP 请求、不调用模型、不写入数据库、不发送通知。运行后网页不会产生演示数据。

## 运维

```bash
./selfhost/jimotable.sh status
./selfhost/jimotable.sh logs
backup_id=$(./selfhost/jimotable.sh backup)
# 以下操作会覆盖当前实例数据，仅在确认恢复目标后执行：
./selfhost/jimotable.sh restore "$backup_id" --yes
```

备份会暂停 API/Worker。保管好 `.env`、`selfhost/secrets/`、`selfhost/operator.json` 及备份，定期复制到另一台主机。首次发布包中的 `INSTALL.zh-CN.md` 包含完整步骤。

## 许可

`LICENSE` 是自定义的 **Community Free License**，不是 OSI 认可的开源许可 —— 因此 GitHub 标注为 "Other"。要点：

- 可自托管并运行 Free 版本，包括内部业务评估。
- 不得逆向、反编译或修改专有核心二进制。
- 不得移除版权、商标或署名声明。
- Cloud 与企业功能不在本发行范围内，本文不作描述也不作承诺。

具有约束力的文本见 [LICENSE](LICENSE)。

## Free 版本约束（0.2.1）

每个 Free 安装实例仅支持 1 个业务租户（包括已停用但仍保留的租户）。下列额度是镜像内置最高额度，修改环境变量不能调高；管理员可在上限内分配或调低。

从旧版升级前请检查租户数量并备份。多租户数据库不能直接升级至此 Free 镜像；脚本会拒绝升级，API/Worker 启动时也会检查，不会自动删除租户。请保留旧版本并单独迁移。
