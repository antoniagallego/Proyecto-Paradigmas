FROM haskell:9.4.8-slim

WORKDIR /app

# Cache de dependencias
COPY hermes.cabal cabal.project ./
RUN cabal update && cabal build --only-dependencies -j4

# Compilar
COPY src ./src
RUN cabal build -j4
RUN cp $(cabal list-bin hermes) /app/hermes-exe

EXPOSE 8001

CMD ["/app/hermes-exe"]
