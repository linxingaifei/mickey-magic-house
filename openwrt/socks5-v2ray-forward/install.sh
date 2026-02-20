#!/bin/sh
set -eu

APP_DIR="${APP_DIR:-/etc/mickey-v2ray}"
WEB_DIR="${WEB_DIR:-/www/mickey-v2ray}"
CGI_SCRIPT="${CGI_SCRIPT:-/www/cgi-bin/mickey-v2ray-api}"
INIT_SCRIPT="/etc/init.d/mickey-v2ray-forward"
XRAY_CONFIG="${APP_DIR}/xray-config.json"
NODES_FILE="${APP_DIR}/nodes.json"
FORWARD_FILE="${APP_DIR}/forward-rules.json"
STATE_FILE="${APP_DIR}/state.json"
API_BASE="${API_BASE:-/cgi-bin/mickey-v2ray-api}"
RESTART_UHTTPD="${RESTART_UHTTPD:-1}"

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "[ERROR] 缺少命令: $1"
        exit 1
    }
}

install_packages() {
    echo "[1/5] 安装依赖包..."
    opkg update
    opkg install xray-core jq coreutils-base64 luci-compat rpcd-mod-file
}

prepare_dirs() {
    echo "[2/5] 初始化目录..."
    mkdir -p "$APP_DIR" "$WEB_DIR" "$(dirname "$CGI_SCRIPT")"

    [ -f "$NODES_FILE" ] || echo '{"nodes":[]}' > "$NODES_FILE"
    [ -f "$FORWARD_FILE" ] || echo '{"rules":[]}' > "$FORWARD_FILE"
    [ -f "$STATE_FILE" ] || cat > "$STATE_FILE" <<'JSON'
{"selectedNode":"","mode":"balanced"}
JSON
}

write_xray_helper() {
    cat > "${APP_DIR}/xray-render.sh" <<'SCRIPT'
#!/bin/sh
set -eu

APP_DIR="__APP_DIR__"
NODES_FILE="${APP_DIR}/nodes.json"
FORWARD_FILE="${APP_DIR}/forward-rules.json"
STATE_FILE="${APP_DIR}/state.json"
XRAY_CONFIG="${APP_DIR}/xray-config.json"

selected_node="$(jq -r '.selectedNode // ""' "$STATE_FILE")"

if [ -z "$selected_node" ]; then
    selected_node="$(jq -r '.nodes[0].id // ""' "$NODES_FILE")"
fi

if [ -z "$selected_node" ]; then
    cat > "$XRAY_CONFIG" <<'JSON'
{"log":{"loglevel":"warning"},"inbounds":[],"outbounds":[{"protocol":"freedom","tag":"direct"}]}
JSON
    exit 0
fi

node_json="$(jq -c --arg id "$selected_node" '.nodes[] | select(.id==$id)' "$NODES_FILE")"

if [ -z "$node_json" ]; then
    echo "[WARN] 已选节点不存在，回退首个节点"
    selected_node="$(jq -r '.nodes[0].id // ""' "$NODES_FILE")"
    node_json="$(jq -c --arg id "$selected_node" '.nodes[] | select(.id==$id)' "$NODES_FILE")"
fi

if [ -z "$node_json" ]; then
    echo '{"log":{"loglevel":"warning"},"inbounds":[],"outbounds":[{"protocol":"freedom","tag":"direct"}]}' > "$XRAY_CONFIG"
    exit 0
fi

node_host="$(echo "$node_json" | jq -r '.host')"
node_port="$(echo "$node_json" | jq -r '.port')"
node_user="$(echo "$node_json" | jq -r '.username // ""')"
node_pass="$(echo "$node_json" | jq -r '.password // ""')"

inbounds_json="$(jq -c '[.rules[] | {
  listen: .lan_ip,
  port: (.listen_port|tonumber),
  protocol: "dokodemo-door",
  settings: {
    address: .target_host,
    port: (.target_port|tonumber),
    network: "tcp,udp"
  },
  tag: ("in_" + .id)
}]' "$FORWARD_FILE")"

routing_rules="$(jq -c '[.rules[] | {
  type:"field",
  inboundTag:["in_" + .id],
  outboundTag:"proxy"
}]' "$FORWARD_FILE")"

cat > "$XRAY_CONFIG" <<JSON
{
  "log": {"loglevel": "warning"},
  "inbounds": ${inbounds_json},
  "outbounds": [
    {
      "protocol": "socks",
      "tag": "proxy",
      "settings": {
        "servers": [
          {
            "address": "${node_host}",
            "port": ${node_port},
            "users": [
              {
                "user": "${node_user}",
                "pass": "${node_pass}"
              }
            ]
          }
        ]
      }
    },
    {"protocol": "freedom", "tag": "direct"}
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": ${routing_rules}
  }
}
JSON
SCRIPT
    sed -i "s|__APP_DIR__|$APP_DIR|g" "${APP_DIR}/xray-render.sh"
    chmod +x "${APP_DIR}/xray-render.sh"
}

write_service() {
    cat > "$INIT_SCRIPT" <<'SCRIPT'
#!/bin/sh /etc/rc.common
START=99
STOP=15
USE_PROCD=1

APP_DIR="__APP_DIR__"
XRAY_BIN="/usr/bin/xray"
XRAY_CONFIG="${APP_DIR}/xray-config.json"

start_service() {
    [ -x "${APP_DIR}/xray-render.sh" ] && "${APP_DIR}/xray-render.sh"
    [ -x "$XRAY_BIN" ] || return 1

    procd_open_instance
    procd_set_param command "$XRAY_BIN" run -c "$XRAY_CONFIG"
    procd_set_param respawn
    procd_close_instance
}
SCRIPT
    sed -i "s|__APP_DIR__|$APP_DIR|g" "$INIT_SCRIPT"
    chmod +x "$INIT_SCRIPT"
}

write_api() {
    cat > "$CGI_SCRIPT" <<'SCRIPT'
#!/bin/sh
set -eu

APP_DIR="__APP_DIR__"
NODES_FILE="${APP_DIR}/nodes.json"
FORWARD_FILE="${APP_DIR}/forward-rules.json"
STATE_FILE="${APP_DIR}/state.json"
RENDER="${APP_DIR}/xray-render.sh"

read_body() {
    if [ "${CONTENT_LENGTH:-0}" -gt 0 ]; then
        dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null
    fi
}

json_response() {
    echo "Content-Type: application/json"
    echo
    echo "$1"
}

method="${REQUEST_METHOD:-GET}"
path="${PATH_INFO:-/}"

if [ "$method" = "GET" ] && [ "$path" = "/state" ]; then
    nodes="$(cat "$NODES_FILE")"
    rules="$(cat "$FORWARD_FILE")"
    state="$(cat "$STATE_FILE")"
    json_response "$(jq -n --argjson n "$nodes" --argjson r "$rules" --argjson s "$state" '{nodes:$n.nodes,rules:$r.rules,state:$s}')"
    exit 0
fi

body="$(read_body || true)"

case "$method:$path" in
  POST:/node/import)
    payload="$(echo "$body" | jq -c '.')"
    id="$(echo "$payload" | jq -r '.id')"
    tmp="$(mktemp)"
    jq --argjson node "$payload" '.nodes = ([.nodes[] | select(.id != $node.id)] + [$node])' "$NODES_FILE" > "$tmp"
    mv "$tmp" "$NODES_FILE"
    "$RENDER"
    /etc/init.d/mickey-v2ray-forward restart >/dev/null 2>&1 || true
    json_response '{"ok":true,"message":"节点已导入/更新"}'
    ;;
  POST:/node/delete)
    id="$(echo "$body" | jq -r '.id')"
    tmp="$(mktemp)"
    jq --arg id "$id" '.nodes |= map(select(.id != $id))' "$NODES_FILE" > "$tmp"
    mv "$tmp" "$NODES_FILE"
    "$RENDER"
    /etc/init.d/mickey-v2ray-forward restart >/dev/null 2>&1 || true
    json_response '{"ok":true,"message":"节点已删除"}'
    ;;
  POST:/node/select)
    id="$(echo "$body" | jq -r '.id')"
    tmp="$(mktemp)"
    jq --arg id "$id" '.selectedNode = $id' "$STATE_FILE" > "$tmp"
    mv "$tmp" "$STATE_FILE"
    "$RENDER"
    /etc/init.d/mickey-v2ray-forward restart >/dev/null 2>&1 || true
    json_response '{"ok":true,"message":"节点已切换"}'
    ;;
  POST:/mode/set)
    mode="$(echo "$body" | jq -r '.mode')"
    tmp="$(mktemp)"
    jq --arg mode "$mode" '.mode = $mode' "$STATE_FILE" > "$tmp"
    mv "$tmp" "$STATE_FILE"
    json_response '{"ok":true,"message":"节电模式已更新"}'
    ;;
  POST:/rule/upsert)
    payload="$(echo "$body" | jq -c '.')"
    tmp="$(mktemp)"
    jq --argjson rule "$payload" '.rules = ([.rules[] | select(.id != $rule.id)] + [$rule])' "$FORWARD_FILE" > "$tmp"
    mv "$tmp" "$FORWARD_FILE"
    "$RENDER"
    /etc/init.d/mickey-v2ray-forward restart >/dev/null 2>&1 || true
    json_response '{"ok":true,"message":"内网映射已保存"}'
    ;;
  POST:/rule/delete)
    id="$(echo "$body" | jq -r '.id')"
    tmp="$(mktemp)"
    jq --arg id "$id" '.rules |= map(select(.id != $id))' "$FORWARD_FILE" > "$tmp"
    mv "$tmp" "$FORWARD_FILE"
    "$RENDER"
    /etc/init.d/mickey-v2ray-forward restart >/dev/null 2>&1 || true
    json_response '{"ok":true,"message":"内网映射已删除"}'
    ;;
  *)
    json_response '{"ok":false,"message":"未知请求"}'
    ;;
esac
SCRIPT
    sed -i "s|__APP_DIR__|$APP_DIR|g" "$CGI_SCRIPT"
    chmod +x "$CGI_SCRIPT"
}

write_web() {
    cat > "$WEB_DIR/index.html" <<'HTML'
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Mickey V2Ray 一对一转发</title>
  <style>
    :root {
      --bg: #14051f;
      --card: #231235;
      --soft: #3f2758;
      --text: #f9eefe;
      --pink: #ff6bd6;
      --purple: #9f6dff;
    }
    body { margin:0; font-family: "Segoe UI",sans-serif; background:radial-gradient(circle at top right,#4b2469,var(--bg)); color:var(--text); }
    .wrap { max-width:1080px; margin:24px auto; padding:0 16px 32px; }
    .hero { background:linear-gradient(135deg,rgba(255,107,214,.15),rgba(159,109,255,.16)); border:1px solid #6a3d93; border-radius:16px; padding:16px 20px; }
    h1 { margin:0 0 8px; font-size:24px; }
    .grid { display:grid; gap:16px; grid-template-columns:repeat(auto-fit,minmax(280px,1fr)); margin-top:16px; }
    .card { background:var(--card); border:1px solid #5f3d86; border-radius:14px; padding:14px; }
    input, select { width:100%; box-sizing:border-box; margin:4px 0 10px; background:#1a1029; border:1px solid var(--soft); color:var(--text); border-radius:10px; padding:8px; }
    button { border:0; border-radius:10px; padding:8px 12px; color:white; cursor:pointer; background:linear-gradient(90deg,var(--pink),var(--purple)); }
    button.sub { background:#3b2951; }
    table { width:100%; border-collapse:collapse; font-size:13px; }
    th,td { border-bottom:1px solid #4a2f67; padding:8px 4px; text-align:left; }
    .row { display:flex; gap:8px; flex-wrap:wrap; }
    .tip { font-size:12px; opacity:.8; }
  </style>
</head>
<body>
<div class="wrap">
  <div class="hero">
    <h1>💜 Mickey V2Ray 一键面板</h1>
    <div>OpenWrt / SOCKS5 / 内网地址一对一转发</div>
  </div>

  <div class="grid">
    <div class="card">
      <h3>节点管理（导入 / 删除 / 更新 / 选择）</h3>
      <input id="node_id" placeholder="节点ID，如 hk-01">
      <input id="node_host" placeholder="SOCKS5 地址">
      <input id="node_port" placeholder="端口，例如 1080">
      <input id="node_user" placeholder="用户名（可空）">
      <input id="node_pass" placeholder="密码（可空）">
      <div class="row">
        <button onclick="importNode()">一键导入/更新</button>
        <button class="sub" onclick="deleteNode()">删除节点</button>
      </div>
      <select id="node_select"></select>
      <button onclick="selectNode()">选择节点</button>
    </div>

    <div class="card">
      <h3>一对一内网转发</h3>
      <input id="rule_id" placeholder="规则ID，如 cam-01">
      <input id="rule_lan" placeholder="监听内网IP，例如 192.168.1.1">
      <input id="rule_listen_port" placeholder="监听端口">
      <input id="rule_target_host" placeholder="目标主机">
      <input id="rule_target_port" placeholder="目标端口">
      <div class="row">
        <button onclick="saveRule()">保存/更新映射</button>
        <button class="sub" onclick="deleteRule()">删除映射</button>
      </div>
      <p class="tip">每条规则都可固定出口节点，实现内网地址一对一代理转发。</p>
    </div>

    <div class="card">
      <h3>虎额节电（模式）</h3>
      <select id="mode_select">
        <option value="balanced">平衡</option>
        <option value="performance">性能优先</option>
        <option value="eco">节电优先</option>
      </select>
      <button onclick="setMode()">一键切换模式</button>
      <p class="tip">模式信息会记录在控制面板，可被计划任务读取做功耗策略。</p>
    </div>
  </div>

  <div class="card" style="margin-top:16px;">
    <h3>当前配置预览</h3>
    <pre id="preview" style="white-space:pre-wrap; background:#170d25; border-radius:10px; padding:10px;"></pre>
  </div>
</div>

<script>
const API='__API_BASE__';
const j=(u,m='GET',b)=>fetch(API+u,{method:m,headers:{'Content-Type':'application/json'},body:b?JSON.stringify(b):undefined}).then(r=>r.json());

async function refresh(){
  const data=await j('/state');
  const sel=document.getElementById('node_select');
  sel.innerHTML='';
  data.nodes.forEach(n=>{const o=document.createElement('option');o.value=n.id;o.textContent=`${n.id} (${n.host}:${n.port})`; if(data.state.selectedNode===n.id)o.selected=true; sel.appendChild(o);});
  document.getElementById('mode_select').value=data.state.mode||'balanced';
  document.getElementById('preview').textContent=JSON.stringify(data,null,2);
}
async function importNode(){await j('/node/import','POST',{id:v('node_id'),host:v('node_host'),port:Number(v('node_port')),username:v('node_user'),password:v('node_pass')});refresh();}
async function deleteNode(){await j('/node/delete','POST',{id:v('node_id')});refresh();}
async function selectNode(){await j('/node/select','POST',{id:document.getElementById('node_select').value});refresh();}
async function saveRule(){await j('/rule/upsert','POST',{id:v('rule_id'),lan_ip:v('rule_lan'),listen_port:Number(v('rule_listen_port')),target_host:v('rule_target_host'),target_port:Number(v('rule_target_port'))});refresh();}
async function deleteRule(){await j('/rule/delete','POST',{id:v('rule_id')});refresh();}
async function setMode(){await j('/mode/set','POST',{mode:document.getElementById('mode_select').value});refresh();}
function v(id){return document.getElementById(id).value.trim();}
refresh();
</script>
</body>
</html>
HTML
    sed -i "s|__API_BASE__|$API_BASE|g" "$WEB_DIR/index.html"
}

enable_services() {
    echo "[5/5] 启动服务..."
    if [ "$RESTART_UHTTPD" = "1" ]; then
        /etc/init.d/uhttpd enable || true
        /etc/init.d/uhttpd restart || true
    fi
    /etc/init.d/mickey-v2ray-forward enable
    /etc/init.d/mickey-v2ray-forward restart || true
}

main() {
    require_cmd opkg
    install_packages
    require_cmd jq
    prepare_dirs
    write_xray_helper
    write_service
    write_api
    write_web
    enable_services

    echo ""
    echo "✅ 安装完成"
    lan_ip="$(uci get network.lan.ipaddr 2>/dev/null || echo 192.168.1.1)"
    echo "Web 面板目录: ${WEB_DIR}"
    echo "API 入口: ${API_BASE}"
    echo "默认访问地址: http://${lan_ip}/$(basename "$WEB_DIR")/"
    echo "\n[可选] 数据/页面与软件分离部署示例："
    echo "APP_DIR=/mnt/docker-data/mickey-v2ray WEB_DIR=/mnt/docker-www/mickey-v2ray API_BASE=http://${lan_ip}:18080/cgi-bin/mickey-v2ray-api RESTART_UHTTPD=0 ./install.sh"
}

main "$@"
