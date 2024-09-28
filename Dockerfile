FROM php:8.3.12-fpm-alpine3.20

ENV php_conf /usr/local/etc/php-fpm.conf
ENV fpm_conf /usr/local/etc/php-fpm.d/www.conf
ENV php_vars /usr/local/etc/php/conf.d/docker-vars.ini

RUN apk update && \
    apk upgrade && \
    apk add --no-cache \
        nginx \
        bash \
        openssh-client \
        wget \
        supervisor \
        curl \
        libcurl \
        dialog \
        autoconf \
        make \
        libzip-dev \
        bzip2-dev \
        tzdata \
        gcc

RUN apk add --no-cache --virtual .sys-deps \
        sqlite-dev \
        zlib-dev \
        musl-dev \
        linux-headers && \
        docker-php-ext-install pdo_sqlite zip && \
        docker-php-source delete && \
        apk del gcc musl-dev linux-headers make autoconf && \
        apk del .sys-deps

ADD conf/supervisord.conf /etc/supervisord.conf
RUN mkdir -p /var/log/supervisor

# Copy our nginx config
RUN rm -Rf /etc/nginx/nginx.conf
ADD conf/nginx.conf /etc/nginx/nginx.conf

# nginx site conf
RUN mkdir -p /etc/nginx/sites-available/ && \
    mkdir -p /etc/nginx/sites-enabled/ && \
    mkdir -p /etc/nginx/ssl/ && \
    rm -Rf /var/www/* && \
    mkdir /var/www/html/
ADD conf/nginx-site.conf /etc/nginx/sites-available/default.conf
RUN ln -s /etc/nginx/sites-available/default.conf /etc/nginx/sites-enabled/default.conf

# tweak php-fpm config
RUN echo "cgi.fix_pathinfo=0" > ${php_vars} &&\
    echo "upload_max_filesize = 100M"  >> ${php_vars} &&\
    echo "post_max_size = 100M"  >> ${php_vars} &&\
    echo "variables_order = \"EGPCS\""  >> ${php_vars} && \
    echo "memory_limit = 1024M"  >> ${php_vars} && \
    sed -i \
        -e "s/;catch_workers_output\s*=\s*yes/catch_workers_output = yes/g" \
        -e "s/pm.max_children = 5/pm.max_children = 4/g" \
        -e "s/pm.start_servers = 2/pm.start_servers = 3/g" \
        -e "s/pm.min_spare_servers = 1/pm.min_spare_servers = 2/g" \
        -e "s/pm.max_spare_servers = 3/pm.max_spare_servers = 4/g" \
        -e "s/;pm.max_requests = 500/pm.max_requests = 200/g" \
        -e "s/user = www-data/user = nginx/g" \
        -e "s/group = www-data/group = nginx/g" \
        -e "s/;listen.mode = 0660/listen.mode = 0666/g" \
        -e "s/;listen.owner = www-data/listen.owner = nginx/g" \
        -e "s/;listen.group = www-data/listen.group = nginx/g" \
        -e "s/listen = 127.0.0.1:9000/listen = \/var\/run\/php-fpm.sock/g" \
        -e "s/^;clear_env = no$/clear_env = no/" \
        ${fpm_conf}

RUN cp /usr/local/etc/php/php.ini-development /usr/local/etc/php/php.ini && \
	sed -i \
	    -e "s/;opcache/opcache/g" \
	    -e "s/;zend_extension=opcache/zend_extension=opcache/g" \
            /usr/local/etc/php/php.ini


# Add Scripts
ADD scripts/start.sh /start.sh
RUN chmod 755 /start.sh

# copy in code
ADD --chown=nginx:nginx src/ /var/www/html/
ADD --chown=nginx:nginx errors/ /var/www/errors

RUN  \
    # Display PHP error's
    echo "php_flag[display_errors] = on" >> /usr/local/etc/php-fpm.d/www.conf && \

    # Display Version Details or not
    sed -i "s/expose_php = On/expose_php = Off/g" /usr/local/etc/php-fpm.conf && \

    # Set the desired timezone
    echo "date.timezone=America/Caracas" > /usr/local/etc/php/conf.d/timezone.ini && \

    # Display errors in docker logs
    echo "log_errors = On" >> /usr/local/etc/php/conf.d/docker-vars.ini && \
    echo "error_log = /dev/stderr" >> /usr/local/etc/php/conf.d/docker-vars.ini

EXPOSE 8080

WORKDIR "/var/www/html"
CMD ["/start.sh"]
