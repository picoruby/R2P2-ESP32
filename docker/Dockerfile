ARG ESP_IDF_DOCKER_TAG=v5.5.4
FROM espressif/idf:${ESP_IDF_DOCKER_TAG}

# gcc/ruby ship with the base image; ruby-dev and libssl-dev are the only things missing.
RUN apt-get update && \
    apt-get install -y --no-install-recommends ruby-dev libssl-dev && \
    rm -rf /var/lib/apt/lists/*
