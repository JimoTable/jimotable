# JimoTable vs. Supabase

> **核心定位对比**：Supabase 是优秀的开箱即用 BaaS（后端即服务）基础设施，主打 Auth、Storage、Edge Functions 和 Postgres 托管；而 JimoTable 是**自带业务人员高密度管理 UI 的 Agent 数据工作台**。

---

## 核心差异速览

| 对比维度 | Supabase | JimoTable (Community Free) |
| :--- | :--- | :--- |
| **开箱交付体验** | 开发者得到的是后端 API，仍需手写前端管理页面 | **1分钟直接生成供业务人员使用的完整协同后台** |
| **前端开发成本** | 需使用 Vue/React/Retool 耗费数天编写 CRUD 界面 | **零前端代码**，自带类 Excel 高密度网格与抽屉 |
| **面向使用人群** | 纯技术开发者、全栈工程师 | 技术开发者引入 ➔ 业务人员消费（Human-in-the-loop） |
| **底座数据库** | 原生 PostgreSQL | 原生 PostgreSQL 18 (Base-per-schema 架构) |
| **Agent 挂载方式** | 通过 Supabase JS SDK 或 Postgres 连接池 | 通过 Agent Skill (Cursor / Claude Code / Dify 插件) |

---

## 结合场景与选型建议

* **什么时候选 Supabase？**  
  当你正在研发一款面向 C 端终端用户的 SaaS 应用，需要完整的用户登录注册体系（Auth）、云函数（Edge Functions）以及移动端 SDK 时。
* **什么时候选 JimoTable？**  
  当你开发了一个 AI Agent（如爬虫分析智能体、客服工单助手、销售线索助理），核心目的是**快速交付给企业业务部门看数据、改数据、派单流转**，不想浪费两周时间手写 Vue 管理后台时，JimoTable 是最快、体验最佳的选择。
