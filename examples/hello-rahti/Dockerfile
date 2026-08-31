FROM node:22-alpine

WORKDIR /app
COPY server.js ./

# OpenShift runs the container as a random UID that always belongs to group 0,
# so everything the app may need to write must be group-writable.
RUN chown -R 1001:0 /app && chmod -R g+rwX /app

USER 1001
EXPOSE 8080
ENV PORT=8080

# The readiness probe uses /health; keep it unauthenticated.
CMD ["node", "server.js"]
