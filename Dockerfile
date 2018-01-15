FROM nginx:latest

RUN echo '<html lang="ja"><head><title>TEST PAGE</title></head><body><h1>TEST</h1></body></html>' > /usr/share/nginx/html/index.html