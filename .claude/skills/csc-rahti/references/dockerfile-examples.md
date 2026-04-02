# Dockerfile Examples for OpenShift/Rahti

## Contents
- [Arbitrary UID Mechanism](#arbitrary-uid-mechanism)
- [chmod Patterns Explained](#chmod-patterns-explained)
- [Python + Red Hat UBI Example](#python--red-hat-ubi-example)
- [Node.js/Bun Multi-Stage Example](#nodejsbun-multi-stage-example)
- [Alternative: Node.js with UBI](#alternative-nodejs-with-ubi)
- [Common Mistakes](#common-mistakes)
- [Writable Directories Checklist](#writable-directories-checklist)
- [Quick Reference](#quick-reference)

## Arbitrary UID Mechanism

OpenShift uses **arbitrary UID** security model for multi-tenant isolation:

- Container runs as **random UID** (e.g., 1000620000) assigned at runtime
- **GID is always 0** (root group)
- Container user is member of root group but NOT root user

**Implication:** Files must be writable by group 0, not just the owner.

```
# At build time you think:
USER 1001  # UID 1001

# At runtime OpenShift assigns:
UID=1000620000, GID=0  # Random UID, but always GID 0
```

## chmod Patterns Explained

| Pattern | Meaning | Use Case |
|---------|---------|----------|
| `g+rwX` | Group: add read, write, execute only if already executable/directory | **Recommended** - safe default |
| `g=u` | Group permissions = user permissions | When you want exact parity |
| `g+rwx` | Group: add read, write, execute unconditionally | Use sparingly - makes all files executable |

**Recommended pattern:**
```dockerfile
RUN chown -R 1001:0 /app && \
    chmod -R g+rwX /app
USER 1001
```

## Python + Red Hat UBI Example

FastAPI application using Red Hat Universal Base Image (UBI).

```dockerfile
FROM registry.access.redhat.com/ubi9/python-312:latest

# Set working directory (already writable in UBI images)
WORKDIR /opt/app-root/src

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY --chown=1001:0 . .

# Ensure group permissions for any generated files
RUN chmod -R g+rwX /opt/app-root/src

# UBI images already set USER 1001
# If you need to be explicit:
USER 1001

# FastAPI with Uvicorn
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

**Why UBI?**
- Pre-configured for OpenShift (correct permissions, non-root user)
- Supported by Red Hat, security updates
- `/opt/app-root/src` is the standard working directory

## Node.js/Bun Multi-Stage Example

Next.js standalone build with Bun runtime.

```dockerfile
# Build stage
FROM oven/bun:1 AS builder

WORKDIR /app

# Install dependencies
COPY package.json bun.lock* ./
RUN bun install --frozen-lockfile

# Copy source and build
COPY . .
RUN bun run build

# Production stage
FROM oven/bun:1-slim AS runner

WORKDIR /app

# Create non-root user and set permissions
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 --ingroup nodejs nextjs && \
    mkdir -p /app/.next/cache && \
    chown -R 1001:0 /app && \
    chmod -R g+rwX /app

# Copy standalone build
COPY --from=builder --chown=1001:0 /app/.next/standalone ./
COPY --from=builder --chown=1001:0 /app/.next/static ./.next/static
COPY --from=builder --chown=1001:0 /app/public ./public

USER 1001

EXPOSE 3000
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

CMD ["bun", "server.js"]
```

**Key points:**
- Multi-stage reduces final image size
- `--chown=1001:0` on COPY sets correct ownership immediately
- `.next/cache` directory needed for ISR/caching
- `output: 'standalone'` in `next.config.js` required

## Alternative: Node.js with UBI

```dockerfile
FROM registry.access.redhat.com/ubi9/nodejs-20:latest AS builder

WORKDIR /opt/app-root/src

COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build

FROM registry.access.redhat.com/ubi9/nodejs-20-minimal:latest

WORKDIR /opt/app-root/src

COPY --from=builder --chown=1001:0 /opt/app-root/src/.next/standalone ./
COPY --from=builder --chown=1001:0 /opt/app-root/src/.next/static ./.next/static
COPY --from=builder --chown=1001:0 /opt/app-root/src/public ./public

USER 1001

EXPOSE 3000
CMD ["node", "server.js"]
```

## Common Mistakes

### Wrong: Relying on user ownership only
```dockerfile
# BAD - only owner can write
RUN chown -R 1001 /app/data
USER 1001
```

### Correct: Include group 0
```dockerfile
# GOOD - group 0 can write
RUN chown -R 1001:0 /app/data && \
    chmod -R g+rwX /app/data
USER 1001
```

### Wrong: Creating files as root then switching user
```dockerfile
# BAD - files created as root before USER directive
RUN mkdir /app/cache && echo "init" > /app/cache/data
USER 1001
# Container can't write to /app/cache!
```

### Correct: Set permissions explicitly or create as user
```dockerfile
# GOOD - explicit permissions
RUN mkdir /app/cache && \
    chown -R 1001:0 /app/cache && \
    chmod -R g+rwX /app/cache
USER 1001
```

## Writable Directories Checklist

If your app writes to any of these, ensure group write permissions:
- Cache directories (`.next/cache`, `__pycache__`)
- Upload directories
- Log directories
- Temporary files
- SQLite database files
- Session storage

## Quick Reference

```dockerfile
# Standard permission pattern for any directory
RUN mkdir -p /app/writable-dir && \
    chown -R 1001:0 /app/writable-dir && \
    chmod -R g+rwX /app/writable-dir

# For entire app directory
COPY --chown=1001:0 . /app
RUN chmod -R g+rwX /app

# Always end with non-root user
USER 1001
```
