FROM alpine:latest

# Install necessary runtime dependencies
RUN apk add --no-cache bash git curl jq github-cli

# Set working directory
WORKDIR /app

# Copy application scripts into the container
COPY scripts /app/scripts

# Ensure scripts are executable
RUN chmod +x /app/scripts/*.sh

# Run the polling daemon by default
ENTRYPOINT ["/app/scripts/start-irontech.sh"]
