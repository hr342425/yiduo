# syntax=docker/dockerfile:1

FROM node:22-bookworm-slim AS site-build
WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY astro.config.mjs tsconfig.json ./
COPY public ./public
COPY src ./src
RUN npm run build

FROM nginx:1.27-alpine

COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=site-build /app/dist /usr/share/nginx/html

EXPOSE 80

