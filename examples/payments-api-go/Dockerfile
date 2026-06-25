# Build
FROM golang:1.23 AS build
WORKDIR /src
COPY . .
RUN go mod tidy && CGO_ENABLED=0 go build -o /payments-api .

# Run (tiny, no shell)
FROM gcr.io/distroless/static-debian12
COPY --from=build /payments-api /payments-api
EXPOSE 8000
ENTRYPOINT ["/payments-api"]
