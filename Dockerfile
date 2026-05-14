FROM alibaba-cloud-linux-3-registry.cn-hangzhou.cr.aliyuncs.com/alinux3/alinux3 AS site-build
WORKDIR /app

ARG NODE_VERSION=22.14.0
ENV PATH="/opt/node/bin:${PATH}"

RUN yum install -y ca-certificates curl tar xz \
    && curl -fsSL "https://npmmirror.com/mirrors/node/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
    | tar -xJ -C /opt \
    && mv "/opt/node-v${NODE_VERSION}-linux-x64" /opt/node \
    && npm config set registry https://registry.npmmirror.com \
    && yum clean all

COPY package*.json ./
RUN npm ci --registry=https://registry.npmmirror.com

COPY astro.config.mjs tsconfig.json ./
COPY public ./public
COPY src ./src
RUN npm run build

FROM alibaba-cloud-linux-3-registry.cn-hangzhou.cr.aliyuncs.com/alinux3/alinux3

RUN yum install -y nginx \
    && yum clean all

COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=site-build /app/dist /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
