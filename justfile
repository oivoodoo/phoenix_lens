image := "oivoodoo/phoenix_lens"
version := `awk -F '"' '/@version /{print $2; exit}' mix.exs`

default:
    @just --list

# Build the standalone image tagged with mix.exs @version and latest
docker-build:
    docker build -t {{image}}:{{version}} -t {{image}}:latest .

# Push version and latest tags to Docker Hub
docker-push:
    docker push {{image}}:{{version}}
    docker push {{image}}:latest

# Build then push to Docker Hub
docker-publish: docker-build docker-push
