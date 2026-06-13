FROM alpine:3

RUN apk add --no-cache mongodb-tools curl

COPY backup.sh /backup.sh
RUN chmod +x /backup.sh

ENTRYPOINT ["/backup.sh"]
CMD ["cron"]
