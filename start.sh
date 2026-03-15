#!/bin/sh
set -e
# Replace RAILWAY_PORT placeholder with the actual PORT injected by Railway
sed -i "s/RAILWAY_PORT/${PORT}/g" /etc/nginx/conf.d/default.conf
exec nginx -g 'daemon off;'
