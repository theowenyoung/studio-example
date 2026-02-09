# Simple Dockerfile for pre-built static sites
FROM nginx:alpine

# Copy nginx configuration
COPY docker/nodejs-ssg/nginx.conf /etc/nginx/nginx.conf

# Copy static files (passed via --build-context)
# Usage: docker build --build-context static=./path/to/static/files
COPY --from=static . /usr/share/nginx/html

WORKDIR /usr/share/nginx/html

EXPOSE 3000

CMD ["nginx", "-g", "daemon off;"]
