# syntax=docker/dockerfile:1

FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY voice_signal/src/VoiceSignal/VoiceSignal.csproj voice_signal/src/VoiceSignal/
RUN dotnet restore voice_signal/src/VoiceSignal/VoiceSignal.csproj
COPY voice_signal/src/VoiceSignal/*.cs voice_signal/src/VoiceSignal/
RUN dotnet publish voice_signal/src/VoiceSignal/VoiceSignal.csproj --configuration Release --no-restore --output /app /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
ENV ASPNETCORE_HTTP_PORTS= \
    VOICE_SIGNAL_BIND=0.0.0.0 \
    VOICE_SIGNAL_PORT=4100 \
    DOTNET_CLI_TELEMETRY_OPTOUT=1
COPY --from=build /app .
USER $APP_UID
EXPOSE 4100
ENTRYPOINT ["dotnet", "VoiceSignal.dll"]
