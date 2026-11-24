# 直接使用 nginx 提供已构建好的 Web 静态文件
# 构建产物由本地 flutter build web 生成，放在 build/web 目录
# 基础镜像走华为云 SWR 的 Docker Hub 镜像源：本机直连 Docker Hub 只有 ~15KB/s，
# 换成 SWR 后拉取 nginx:alpine 约 4 秒。需要官方源时用
# docker compose build --build-arg NGINX_IMAGE=nginx:alpine
ARG NGINX_IMAGE=swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/library/nginx:alpine
FROM ${NGINX_IMAGE}

# 复制构建产物到 nginx 目录
COPY build/web /usr/share/nginx/html

# 复制自定义 nginx 配置 (支持 SPA 路由)
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
