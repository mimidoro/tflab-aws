# Multi-arch: built for linux/arm64 (Graviton Spot nodes) by .github/workflows/build.yml
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY Api.csproj .
RUN dotnet restore
COPY . .
RUN dotnet publish -c Release -o /out --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION} \
    DOTNET_gcServer=0 \
    ASPNETCORE_URLS=http://0.0.0.0:8080
WORKDIR /app
# Amazon RDS CA bundle for TLS verification (SslMode=VerifyFull)
ADD --chmod=0644 https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem /etc/ssl/rds/global-bundle.pem
COPY --from=build /out .
USER $APP_UID
EXPOSE 8080
ENTRYPOINT ["dotnet", "Api.dll"]
