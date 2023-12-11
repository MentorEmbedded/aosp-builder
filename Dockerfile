# An Ubuntu 22.04 image base suitable for building AOSP
#
# BUILD:
#  docker build \
#     --build-arg UID=$(id -u) \
#     --build-arg GID=$(id -g) \
#     -t ${USER}/ubuntu/aosp .
#
# RUN:
#  docker run --rm --privileged=true \
#    -e DISPLAY=$DISPLAY \
#    --mount type=bind,src=/dev,target=/dev \
#    --mount type=bind,src=$PWD,target=/build/aosp13 \
#    --mount type=bind,src=$HOME/.ssh,target=/home/ubuntu/.ssh \
#    --mount type=bind,src=$HOME/.gnupg,target=/home/ubuntu/.gnupg \
#    --mount type=bind,src=/tmp/.X11-unix,target=/tmp/.X11.unix \
#    --dns 8.8.8.8 --dns 8.8.4.4 -it -t ${USER}/ubuntu/aosp
#
##################################################################################
# Settings that should persist for all build scopes.

# Set UID for new generated files, you should set this to your own UID but on
# most Linux systems the primary user is UID 1000, so this seems like a
# reasonable default.
ARG USERNAME="ubuntu"
ARG UID=1000
ARG GID=1000
ARG PASSWD="ubuntu"

# This can be changed at container build time but shouldn't really be changed at
# run time, so we aren't making it an ENV.
ARG BUILD_VOLUME="/build"

##################################################################################
# Begin Common Ubuntu Builer Base
#
FROM ubuntu:22.04 as ubuntu-base

# Arguments to inherit from the global scope
ARG USERNAME
ARG UID
ARG GID
ARG PASSWD
ARG BUILD_VOLUME

# It is also possible to adjust these values when you run your container either
# from command line arguments to the docker-run command or by setting them in
# your docker-compose YAML file.

RUN apt update                                        \
    && apt-get install -y -f --no-install-recommends  \
       bison                                          \
       build-essential                                \
       ca-certificates                                \
       curl                                           \
       flex                                           \
       fontconfig                                     \
       git-core                                       \
       gnupg                                          \
       lib32z1-dev                                    \
       libc6-dev-i386                                 \
       libgl1-mesa-dev                                \
       libncurses5                                    \
       libx11-dev                                     \
       libxml2-utils                                  \
       python3                                        \
       python-is-python3                              \
       ssh-client                                     \
       sudo                                           \
       unzip                                          \
       wget                                           \
       x11proto-core-dev                              \
       xsltproc                                       \
       zip                                            \
       zlib1g-dev                                     \
    && rm -rf /var/lib/apt/lists/*

# locale support requires more than just a basic install, so we'll handle it
# separately.
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y locales
RUN sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    dpkg-reconfigure --frontend=noninteractive locales && \
    update-locale LANG=en_US.UTF-8

# Update our root certificates
RUN mkdir -p /usr/share/ca-certificates/cacert.org/ && \
    wget -P /usr/share/ca-certificates/cacert.org/     \
            http://www.cacert.org/certs/root.crt       \
            http://www.cacert.org/certs/class3.crt &&  \
    /usr/sbin/update-ca-certificates

# Add repo
RUN curl http://storage.googleapis.com/git-repo-downloads/repo > /usr/bin/repo
RUN chmod a+x /usr/bin/repo

# And the github CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg              \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg          \
    && echo "deb [signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list > /dev/null
RUN apt update && apt install gh

# Replace 'dash' with 'bash' as '/bin/sh'
RUN echo dash    dash/sh boolean false | debconf-set-selections -v && \
    dpkg-reconfigure --frontend=noninteractive dash

# Set up the user and group accounts
RUN groupadd -g ${GID} -f ${USERNAME} && \
    useradd ${USERNAME} -m -G sudo -u ${UID} -g ${GID} -o -p $(openssl passwd -1 ${PASSWD})

# Provide a mount point for a .ssh volume, allowing easy ssh access in and out
# of the container and supporting ssh-based access to git repositories.
RUN mkdir -p /home/${USERNAME}/.ssh/

# Ensure our user has sudo access without requiring a password.
RUN mkdir -p /etc/sudoers.d/ && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/${USERNAME}

# Set the correct permissions on both the user home directory and the build
# volume.
RUN chown -R ${USERNAME}:${USERNAME} /home/${USERNAME} && \
    mkdir -p ${BUILD_VOLUME} && \
    chown -R ${USERNAME}:${USERNAME} ${BUILD_VOLUME}

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8
ENV LC_ALL en_US.UTF-8

# The following commands should be run as your build user.
USER ${USERNAME}:${USERNAME}

# Host volume
VOLUME ${BUILD_VOLUME}

# Define working directory.
WORKDIR ${BUILD_VOLUME}

# Define default command.
USER ${USERNAME}:${USERNAME}
CMD ["/bin/bash", "-l"]

# --------------------------------------------------------------------------------
# Begin AOSP build container
FROM ubuntu-base as ubuntu-aosp-13

# Arguments to inherit from the global scope
ARG USERNAME
ARG UID
ARG GID
ARG PASSWD
ARG BUILD_VOLUME

RUN mkdir -p ${BUILD_VOLUME}/aosp13

# Define working directory.
WORKDIR ${BUILD_VOLUME}
COPY banner /home/${USERNAME}/.banner
RUN echo ". ~/.banner" >> /home/${USERNAME}/.profile && \
    sed -i "s,BUILD_VOLUME,${BUILD_VOLUME},g" /home/${USERNAME}/.profile

# Define default command.
USER ${USERNAME}:${USERNAME}
CMD ["/bin/bash", "-l"]

# --------------------------------------------------------------------------------
# Begin AOSP full source and build container
#
# This is NOT RECOMMENDED as it will likely fail as your docker volumes fill up.
# Only build and use this container if you have reconfigured your docker daemon
# to allow a minimum of 150GB for a volume.
#
FROM ubuntu-base as ubuntu-aosp-13-full

# Arguments to inherit from the global scope
ARG USERNAME
ARG UID
ARG GID
ARG PASSWD
ARG BUILD_VOLUME

ARG BRANCH="android-13.0.0_r82"

RUN mkdir -p ${BUILD_VOLUME}/aosp13
RUN cd ${BUILD_VOLUME}/aosp13 && \
    repo init -u https://android.googlesource.com/platform/manifest -b ${BRANCH}
RUN cd ${BUILD_VOLUME}/aosp13 && \
    repo sync -c -j$(nproc)

# Define working directory.
WORKDIR ${BUILD_VOLUME}

# Define default command.
USER ${USERNAME}:${USERNAME}
CMD ["/bin/bash", "-l"]
