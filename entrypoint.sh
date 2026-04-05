#!/usr/bin/env sh
set -e

# --- 1. 设置默认值 --- 
USER_NAME=${SSH_USER:-zv}
USER_PWD=${SSH_PWD:-105106}

if [ "$USER_NAME" = "root" ]; then
    TARGET_HOME="/root"
else
    TARGET_HOME="/home/$USER_NAME"
fi

# --- 2. 动态创建用户 --- 
if [ "$USER_NAME" != "root" ]; then
    if ! id -u "$USER_NAME" >/dev/null 2>&1; then
        useradd -m -s /bin/bash "$USER_NAME" || true
    fi
    [ -d "$TARGET_HOME" ] && chown -R "$USER_NAME":"$USER_NAME" "$TARGET_HOME"
fi

echo "root:$USER_PWD" | chpasswd
[ "$USER_NAME" != "root" ] && echo "$USER_NAME:$USER_PWD" | chpasswd
echo "$USER_NAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/init-users
ln -sf /usr/bin/supervisorctl /usr/local/bin/sctl

# --- 3. 自动化生成 init_env.sh (省略部分逻辑以保持简洁) --- 
# ... 此处保留原有的 GB 变量处理逻辑 ...

# --- 4. 处理持久化配置 --- 
BOOT_DIR="$TARGET_HOME/boot"
BOOT_CONF="$BOOT_DIR/supervisord.conf"
TEMPLATE="/usr/local/etc/supervisord.conf.template"

mkdir -p "$BOOT_DIR"

if [ ! -f "$BOOT_CONF" ] || [ "$FORCE_UPDATE" = "true" ]; then
    cp "$TEMPLATE" "$BOOT_CONF"
    sed -i "s/{SSH_USER}/$USER_NAME/g" "$BOOT_CONF"
    [ -d "$TARGET_HOME" ] && chown -R "$USER_NAME":"$USER_NAME" "$BOOT_DIR"
fi

# --- 5. 动态进程控制 (关键修改区) ---

# CF_TOKEN 判断 
if [ -z "$CF_TOKEN" ]; then
	sed -i '/\[program:cloudflared\]/,/stdout_logfile/s/^/;/' "$BOOT_CONF"
else
	sed -i '/\[program:cloudflared\]/,/stdout_logfile/s/^;//' "$BOOT_CONF"
fi

# E_http 保活脚本判断
if [ -z "$E_http" ]; then
    echo "⚠️ 未发现 E_http，正在禁用 Keepalive 脚本..."
    sed -i '/\[program:keepalive\]/,/stdout_logfile/s/^/;/' "$BOOT_CONF"
else
    echo "💓 发现 E_http ($E_http)，正在激活 Keepalive 脚本..."
    # 确保去掉可能存在的所有分号注释
    sed -i '/\[program:keepalive\]/,/stdout_logfile/s/^;//' "$BOOT_CONF"
fi

# ttyd 动态密码处理 
if [ -n "$TTYD" ]; then
	sed -i "s|/usr/local/bin/ttyd -W bash|/usr/local/bin/ttyd -c $TTYD -W bash|g" "$BOOT_CONF"
fi

echo "alias sctl='supervisorctl -c $BOOT_CONF'" >> /etc/bash.bashrc

# --- 6. 启动控制 --- 
if [ -n "$SSH_CMD" ]; then
    exec /bin/sh -c "$SSH_CMD"
else
    exec /usr/bin/supervisord -n -c "$BOOT_CONF"
fi
