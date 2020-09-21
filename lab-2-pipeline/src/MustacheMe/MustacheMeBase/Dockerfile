FROM python:2.7-jessie

# Install C compiler, and python-dev which enables pip install of uwsgi
RUN apt-get -y update && \
    	apt-get -y -q install \
	gcc \
	python2.7-dev \
	nginx \
	libjpeg-dev \
	zlibc \
	zip \
	chkconfig \
	gettext-base

# Remove nginx default web page
RUN rm /etc/nginx/sites-enabled/default

# Create the working directory
RUN mkdir -p /var/www/forklift

# Install python packages
RUN cd /var/www/forklift && \
	virtualenv venv && \
	. venv/bin/activate && \
	pip install uwsgi numpy geopy flask pillow boto3

