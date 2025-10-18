# Base image Ubuntu latest
FROM ubuntu:latest

# Maintainer information
LABEL maintainer="Aaqib"
LABEL description="Custom Ubuntu image with networking tools and Nginx"

# Environment variable to avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Update package list and install networking utilities + Nginx
RUN apt-get update && apt-get install -y \
    iputils-ping \
    curl \
    wget \
    net-tools \
    dnsutils \
    iproute2 \
    traceroute \
    netcat-openbsd \
    telnet \
    vim \
    nano \
    nginx \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create custom HTML file
RUN echo '<h1>🚀 Hey this is Aaqib custom image 🚀</h1>' > /var/www/html/index.html

# Expose port 80
EXPOSE 80

# Start Nginx in foreground
CMD ["nginx", "-g", "daemon off;"]
