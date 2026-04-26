FROM php:8.2-fpm

RUN apt-get update && apt-get install -y \
    git curl zip unzip libonig-dev libxml2-dev \
    libzip-dev

RUN docker-php-ext-install pdo pdo_mysql mbstring zip exif pcntl
RUN docker-php-ext-enable opcache

COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /var/www

COPY ./docker/php/performance.ini /usr/local/etc/php/conf.d/zz-performance.ini

CMD ["php-fpm"]