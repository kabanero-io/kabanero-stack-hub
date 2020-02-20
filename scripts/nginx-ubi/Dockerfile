FROM registry.access.redhat.com/ubi8/ubi-minimal

COPY nginx-ubi/nginx.repo  /etc/yum.repos.d/nginx.repo

RUN microdnf install nginx findutils \
    && mkdir /var/cache/nginx \
    && chown -R nginx:0 /var/log/nginx/ /var/cache/nginx /usr/share/nginx \
    && chmod -R g=u /var/log/nginx/ /var/cache/nginx /usr/share/nginx \
    && mkdir /licenses \
    && cp /usr/share/doc/nginx*/* /licenses
