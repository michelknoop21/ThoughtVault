FROM nginx:1.28-alpine
COPY deploy/website/default.conf.template /etc/nginx/templates/default.conf.template
COPY docs/design/high-end-yinga/index.html docs/design/high-end-yinga/landing.css docs/design/high-end-yinga/landing.js /usr/share/nginx/html/
COPY docs/design/high-end-yinga/assets/thoughtvault-mark.png docs/design/high-end-yinga/assets/yinga-logo.svg docs/design/high-end-yinga/assets/macos-recording.png docs/design/high-end-yinga/assets/macos-processing.png docs/design/high-end-yinga/assets/favicon.png docs/design/high-end-yinga/assets/apple-touch-icon.png /usr/share/nginx/html/assets/
COPY deploy/website/public/ /usr/share/nginx/html/
COPY deploy/website/private/ /usr/share/nginx/private/
RUN chmod -R a+rX /usr/share/nginx/html /usr/share/nginx/private /etc/nginx/templates && rm -f /usr/share/nginx/html/50x.html
HEALTHCHECK --interval=30s --timeout=3s CMD wget -q -O /dev/null http://127.0.0.1/ || exit 1
