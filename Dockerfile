# 直接使用 nginx 提供已构建好的 Web 静态文件
# 构建产物由本地 flutter build web 生成，放在 build/web 目录
FROM nginx:alpine

# 复制构建产物到 nginx 目录
COPY build/web /usr/share/nginx/html

# 复制自定义 nginx 配置 (支持 SPA 路由)
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
