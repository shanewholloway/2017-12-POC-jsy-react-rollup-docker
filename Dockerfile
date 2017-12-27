FROM node:9.3.0 as deps_base
WORKDIR /usr/src/app
COPY approot/package.json approot/*package-lock.json approot/*yarn.lock /usr/src/app/


FROM deps_base as dependencies
RUN NODE_ENV=production npm install --prod


FROM deps_base as build
RUN NODE_ENV=development npm install
COPY approot/ /usr/src/app/
RUN npm -s run build


FROM debian:stretch-slim as final
WORKDIR /usr/src/app
CMD [ "/usr/local/bin/node", "./dist" ]
COPY --from=node:9.3.0 /usr/local/ /usr/local/
COPY --from=dependencies /usr/src/app/ /usr/src/app/
COPY --from=build /usr/src/app/dist/ /usr/src/app/dist/

# vim: filetype=Dockerfile
