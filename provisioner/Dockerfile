FROM alpine:3.19
RUN apk add --no-cache curl jq bash gettext sqlite
COPY seed.sh /seed.sh
COPY provision.sh /provision.sh
RUN chmod +x /seed.sh /provision.sh
ENTRYPOINT ["/provision.sh"]
