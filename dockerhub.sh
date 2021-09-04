PLATFORMS="linux/amd64,linux/386,linux/arm64,linux/arm/v7,linux/arm/v6"
DATE=$(date '+%Y-%m-%dT%H:%M:%S')

if [ -z "$GITHUB_SHA" ]; then
echo "Guessing GITHUB_SHA"
GITHUB_SHA=$(git rev-parse HEAD)
fi

echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USER" --password-stdin

echo "Building and pushing to"
echo "- $DOCKER_REPO:latest"
echo "- $DOCKER_REPO:${GITHUB_SHA:0:7}"
# This script is only meant to run on main in github
docker buildx build --platform "$PLATFORMS" . \
    --target=dev \
    --tag "$DOCKER_REPO:latest" \
    --tag "$DOCKER_REPO:${GITHUB_SHA:0:7}" \
    --label "org.opencontainers.image.revision=$GITHUB_SHA" \
    --label "org.opencontainers.image.created=$DATE" \
    --label "org.opencontainers.image.source=https://github.com/cendyne/little-queue" \
    --push
docker buildx build --platform "$PLATFORMS" . \
    --target=core \
    --tag $DOCKER_REPO:$TAGNAME \
    --tag "$DOCKER_REPO:latest" \
    --tag "$DOCKER_REPO:${GITHUB_SHA:0:7}" \
    --label "org.opencontainers.image.revision=$GITHUB_SHA" \
    --label "org.opencontainers.image.created=$DATE" \
    --label "org.opencontainers.image.source=https://github.com/cendyne/little-queue" \
    --push
