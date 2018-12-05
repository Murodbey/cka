#!/bin/sh
 
SCRIPT_FILENAME=index.php \
REQUEST_URI=/ \
QUERY_STRING= \
REQUEST_METHOD=GET \
cgi-fcgi -bind -connect 192.168.1.4:9000
#cgi-fcgi -bind -connect 10.97.166.58:80
