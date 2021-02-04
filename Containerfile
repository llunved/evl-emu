ARG OS_RELEASE=33
ARG OS_IMAGE=fedora:$OS_RELEASE

FROM $OS_IMAGE as build

ARG OS_RELEASE
ARG OS_IMAGE
ARG HTTP_PROXY=""
ARG USER="evl-emu"
ARG DEVBUILD=""

LABEL MAINTAINER riek@llunved.net

ENV LANG=c.utf-8
ENV USER=$USER
USER root

RUN mkdir -p /evl-emu
WORKDIR /evl-emu

ADD ./rpmreqs-rt.txt ./rpmreqs-build.txt ./rpmreqs-dev.txt /evl-emu/

ENV http_proxy=$HTTP_PROXY
RUN rpm -ivh  https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$OS_RELEASE.noarch.rpm \
    && rpm -ivh  https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$OS_RELEASE.noarch.rpm \
    && dnf -y upgrade \
    && dnf -y install $(cat rpmreqs-rt.txt) $(cat rpmreqs-build.txt) 


# Create the minimal target environment
RUN mkdir /sysimg \
    && dnf install --installroot /sysimg --releasever $OS_RELEASE --setopt install_weak_deps=false --nodocs -y coreutils-single glibc-minimal-langpack $(cat rpmreqs-rt.txt) \
    && if [ ! -z "$DEVBUILD" ] ; then dnf install  --installroot /sysimg --releasever $OS_RELEASE --setopt install_weak_deps=false --nodocs -y $(cat rpmreqs-dev.txt); fi \
    && rm -rf /sysimg/var/cache/* \
    && ls -alh /sysimg/var/cache

#FIXME this needs to be more elegant
RUN ln -s /sysimg/usr/share/zoneinfo/America/New_York /sysimg/etc/localtime

#Add the app user both in the build and rt contexts
RUN adduser -u 1010 -r -g root -G dialout -d /evl-emu -s /sbin/nologin -c "evl-emu user" $USER
RUN adduser -R /sysimg -u 1010 -r -g root -G dialout -d /evl-emu -s /sbin/nologin -c "evl-emu user" $USER

RUN chown -R $USER:0 /evl-emu
USER $USER


ADD . /evl-emu/

RUN /usr/bin/python3 -m virtualenv -v /evl-emu/
RUN /evl-emu/bin/python -m pip install --upgrade pip 
RUN /evl-emu/bin/python -m pip install pip-tools
RUN /evl-emu/bin/pip-compile requirements.in
RUN /evl-emu/bin/python -m pip install -r requirements.txt

# Add some dev / debug content
#RUN if [ ! -z "$DEVBUILD" ] ; then npm install -g nodemon; fi 
#FIXME
#RUN source /evl-emu/bin/activate && /evl-emu/bin/pip3 install /evl-emu
#RUN mv /evl-emu/config.yaml /evl-emu/config.yaml.example
#RUN rm -rf /evl-emu/.cache

USER root
RUN cp -pR /evl-emu/ /sysimg/evl-emu/

# Now create the runtime image
FROM scratch AS runtime

COPY --from=build /sysimg /

VOLUME /etc/evl-emu 
VOLUME /var/log/evl-emu 
VOLUME /var/lib/evl-emu

WORKDIR /evl-emu/

ARG USER="evl-emu"

ENV USER=$USER
ENV CHOWN=true 
ENV CHOWN_DIRS="/etc/evl-emu /var/log/evl-emu /var/lib/evl-emu" 
  
#FIXME - Do we need this?
RUN if [ ! -z "$DEVBUILD" ] ; then chown -R ${USER}:root /evl-emu ; fi

ADD ./scripts/entrypoint.sh \ 
    ./scripts/install.sh \ 
    ./scripts/upgrade.sh \
    ./scripts/uninstall.sh /sbin/ 
ADD ./scripts/start.sh /bin/ 
RUN chmod +x /sbin/entrypoint.sh \ 
    && chmod +x /sbin/install.sh \
    && chmod +x /sbin/upgrade.sh \
    && chmod +x /sbin/uninstall.sh \ 
    &&  chmod +x /bin/start.sh

EXPOSE 4025
ENTRYPOINT ["/sbin/entrypoint.sh"]
CMD ["/bin/start.sh"]

LABEL RUN="podman run --rm -t -i --name \$NAME --net=host --device /dev/it-100 --entrypoint /sbin/entrypoint.sh -v /var/lib/evl-emu:/var/lib/evl-emu -v /etc/evl-emu:/etc/evl-emu -v /var/log/evl-emu:/var/log/evl-emu \$IMAGE /bin/start.sh"
LABEL INSTALL="podman run --rm -t -i --privileged --rm --net=host --ipc=host --pid=host -v /:/host -v /run:/run -e HOST=/host -e IMAGE=\$IMAGE -e NAME=\$NAME -e LOGDIR=/var/log -e DATADIR=/var/lib -e CONFDIR=/etc --entrypoint /bin/sh  \$IMAGE /sbin/install.sh"
LABEL UPGRADE="podman run --rm -t -i --privileged --rm --net=host --ipc=host --pid=host -v /:/host -v /run:/run -e HOST=/host -e IMAGE=\$IMAGE -e NAME=\$NAME -e LOGDIR=/var/log -e DATADIR=/var/lib -e CONFDIR=/etc --entrypoint /bin/sh  \$IMAGE /sbin/upgrade.sh"
LABEL UNINSTALL="podman run --rm -t -i --privileged --rm --net=host --ipc=host --pid=host -v /:/host -v /run:/run -e HOST=/host -e IMAGE=\$IMAGE -e NAME=\$NAME -e LOGDIR=/var/log -e DATADIR=/var/lib -e CONFDIR=/etc --entrypoint /bin/sh  \$IMAGE /sbin/uninstall.sh"

