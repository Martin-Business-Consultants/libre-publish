# Libre Publish in a container: the one binary (API, admin, SQLite, the
# default plugins, all built in) on a minimal image. Everything it keeps
# lives in /data: mount a volume there.
#
#   docker build -t librepublish .
#   docker run -p 8080:8080 -v librepublish-data:/data -e APP_URL=https://cms.example.com librepublish
#
# Settings are environment variables (README): APP_URL, SECRET_KEY,
# TRUST_PROXY=1 behind the host's proxy, PORT (set by most hosts), LOG_FORMAT.
# The first admin: `docker exec -it <container> librepublish user create --email … --name …`,
# or the setup screen at /cms/ on a fresh install. Health check: GET /up.

FROM golang:1.26.9-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG VERSION=dev
RUN CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X main.version=${VERSION}" -o /out/librepublish ./cmd/librepublish \
 && mkdir -p /out/data

# Static, with CA certificates (SMTP, webhooks, deploy hooks) and no shell;
# runs as an unprivileged user.
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/librepublish /usr/local/bin/librepublish
COPY --from=build --chown=nonroot:nonroot /out/data /data
ENV DATA_DIR=/data LOG_FORMAT=json
VOLUME /data
EXPOSE 8080
ENTRYPOINT ["librepublish"]
CMD ["serve"]
