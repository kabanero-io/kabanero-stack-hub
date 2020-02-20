ARG NGINX_IMAGE=nginx:stable-alpine
FROM $NGINX_IMAGE

COPY scripts/nginx/nginx.conf  /etc/nginx/nginx.conf
COPY scripts/nginx/nginx-ssl.conf  /etc/nginx/nginx-ssl.conf
COPY scripts/nginx/startup.sh  /opt/startup.sh
COPY build/prefetch    /opt/www/public
COPY assets            /opt/www/public
COPY build/index-src   /opt/www/public

EXPOSE 8080
EXPOSE 8443

RUN touch /var/run/nginx.pid && \
  chown -R nginx:0 /var/run/nginx.pid /var/cache/nginx /opt/www/public /etc/nginx /run && \
  chmod -R g=u /opt/www/public /var/cache/nginx /etc/nginx /var/run/nginx.pid /run

USER nginx

ENTRYPOINT ["/opt/startup.sh"]
