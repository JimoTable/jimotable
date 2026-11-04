# JimoTable vs. NocoDB

> **核心定位对比**：NocoDB 是将既有关系型数据库直接转换为 Airtable 风格表格的开源工具；而 JimoTable 是**专为 AI Agent 设计的业务运行时与人机协同后台**。

---

## 核心差异速览

| 对比维度 | NocoDB | JimoTable (Community Free) |
| :--- | :--- | :--- |
| **设计理念** | 面向人力的无代码数据库管理工具 | 面向 AI Agent 读写与人类审核的人机协同运行时 |
| **Agent API 契约** | 暴露底层物理列和复杂的 REST/GraphQL 规范 | 原生语义化 OpenAPI 3.0，极低 Token 消耗 |
| **并发 Schema 演化** | Agent 动态加列容易造成 DDL 锁冲突或死锁 | 异步原子建表建列机制，任务中心实时跟踪 |
| **多表实体抽屉** | 点击跳转新页面或弹出全屏模态框 | 丝滑右侧详情抽屉联动，保持上下文不丢失 |
| **审计与操作溯源** | 基础数据库日志 | 全链路精确到每次 Tool Call 的 Agent 审计跟踪 |
| **权限与隔离机制** | 传统 RBAC 权限体系 | Base-per-schema 物理隔离 + Postgres 原生 RLS |

---

## 为什么面向 Agent 交付时 JimoTable 更合适？

### 1. 降低 LLM 的 Token 开销与心智负担
NocoDB 的 API 偏向传统的 CRUD 接口，返回很多框架级的元数据，Agent 在解析时往往要消耗额外的上下文 Token。JimoTable 的 Base Agent API 输出针对当前业务裁剪的极简 OpenAPI，字段名称语义化映射，极大提高了 Agent 识别表结构并正确填充字段的成功率。

### 2. 人机协同的高密度抽屉联动
AI Agent 往往负责在后台默默干脏活累活（如采集、归类、打标、关联），而人类负责最终决策。当业务人员在网页端审核 Agent 生成的数据时，JimoTable 的高密度网格与右侧抽屉联动可以让业务员无需跳出当前视图，即可看清全部关联合同、跟进流水并一键审批。
