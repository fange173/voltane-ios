# 网页版黄金样例

`web-form-cases.json` 由网页版的真实表单在浏览器里跑出来：`generate-web-golden.js` 里的 `cases` 是操作脚本，`run` 逐条打开网页版 `record-form.js` 的表单、按脚本填写、读回各字段的值，并截获提交体；`util` 部分直接调用 `util.js` / `state.js` 的函数。

## 重新生成

1. 在 voltane 仓库启动 `voltane-dev`，浏览器登录 admin。
2. 打开 `http://localhost:8136/`，把 `generate-web-golden.js` 的内容在页面控制台执行（先定义 `window.__H`，再执行 `run`）。网页版的 CSP 不允许内联脚本，可以用一个本地小服务转发 8136、去掉 CSP 头，并以 `<script src>` 的方式提供这个文件。
3. 把返回对象 `JSON.stringify` 后保存为 `web-form-cases.json`（同一个小服务接收 POST 保存）。
4. `prefill.last` 需要补 `vehicle_id`；编辑已保存记录的算例里，`vehicle_id`、`version`、`type` 由测试补上。

最近一次生成：2026-10-27，网页版已经去掉实付/付款人，充电单价改为只读（金额 ÷ 电量），补录里程和所选时间之前的读数比较（prefill 带 `odo_points`）。生成时会忽略用户的油量单位偏好 `fuel_unit`。
