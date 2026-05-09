FROM node:22-slim AS build

WORKDIR /app

COPY ./package.json ./package-lock.json ./
RUN npm ci --silent

COPY . .
RUN npx vite build

FROM nginx:alpine

COPY --from=build /app/dist /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
