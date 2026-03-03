FROM cirrusci/flutter:stable
RUN flutter config --enable-web
WORKDIR /app
COPY . .
RUN flutter pub get
RUN flutter build web
RUN npm install -g serve
CMD ["serve", "-s", "build/web", "-l", "8080"]