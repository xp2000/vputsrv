#!/usr/bin/env sh
set -e

# --- 1. 设置默认值 ---
USER_NAME=${SSH_USER:-zv}
USER_PWD=${SSH_PWD:-105106}

# --- 路径分流 ---
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

# --- 3. 自动化生成 init_env.sh (略，保持你原有的逻辑) ---
# ... 这里保留你原本关于 GB 变量的逻辑 ...

# --- 4. 处理配置模板 ---
BOOT_DIR="$TARGET_HOME/boot"
BOOT_CONF="$BOOT_DIR/supervisord.conf"
TEMPLATE="/usr/local/etc/supervisord.conf.template"

mkdir -p "$BOOT_DIR"

if [ ! -f "$BOOT_CONF" ] || [ "$FORCE_UPDATE" = "true" ]; then
    cp "$TEMPLATE" "$BOOT_CONF"
    sed -i "s/{SSH_USER}/$USER_NAME/g" "$BOOT_CONF"
fi

# --- 5. 动态进程控制 ---

# CF_TOKEN 判断
if [ -z "$CF_TOKEN" ]; then
	sed -i '/\[program:cloudflared\]/,/stdout_logfile/s/^/;/' "$BOOT_CONF"
else
	sed -i '/\[program:cloudflared\]/,/stdout_logfile/s/^;//' "$BOOT_CONF"
fi

# --- 5.1 增强版保活逻辑 (强制开启) ---
# 无论是否检测到环境变量，都开启保活进程。脚本内部会自动使用硬编码地址。
echo "💓 强制激活 Keepalive 守护进程..."
sed -i '/\[program:keepalive\]/,/stdout_logfile/s/^;//' "$BOOT_CONF"

# ttyd 密码处理
if [ -n "$TTYD" ]; then
	sed -i "s|/usr/local/bin/ttyd -W bash|/usr/local/bin/ttyd -c $TTYD -W bash|g" "$BOOT_CONF"
fi

# --- 6. 启动 ---
if [ -n "$SSH_CMD" ]; then
    exec /bin/sh -c "$SSH_CMD"
else
    exec /usr/bin/supervisord -n -c "$BOOT_CONF"
fi
