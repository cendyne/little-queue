FROM levischuck/janet-sdk as builder

COPY project.janet /little-queue/
WORKDIR /little-queue/
RUN jpm deps
COPY . /little-queue/
ENV JOY_ENVIRONMENT production
RUN jpm build

FROM alpine
# COPY --from=builder /app/ /app/
COPY --from=builder /little-queue/build/little-queue /usr/local/bin/
COPY db /opt/db
WORKDIR /opt/
CMD ["little-queue"]
