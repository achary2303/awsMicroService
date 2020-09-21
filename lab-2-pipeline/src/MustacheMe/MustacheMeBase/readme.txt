# Read me file

This directory contains the Dockerfile to create the Base image for all MustacheMe containers

The base images is responsible for downloading and installing all of the libraries and python modules
needed by all other dependent containers.

cd \<base dir>

docker build -t mustacheme:base .
