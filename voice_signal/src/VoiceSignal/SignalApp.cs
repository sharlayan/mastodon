using System.Threading.RateLimiting;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.Extensions.Caching.Memory;
using Npgsql;

namespace VoiceSignal;

public static class SignalApp
{
    public static WebApplication Build(SignalOptions options, IAllocationResolver? resolver = null, string? url = null)
    {
        var builder = WebApplication.CreateSlimBuilder();
        builder.WebHost.UseUrls(url ?? $"http://{options.BindAddress}:{options.Port}");
        builder.Logging.ClearProviders();
        builder.Logging.AddSimpleConsole(console => console.SingleLine = true);
        builder.Logging.AddFilter("Microsoft.AspNetCore", LogLevel.Warning);
        builder.Logging.AddFilter("System.Net.Http", LogLevel.Warning);

        builder.Services.AddSingleton(options);
        builder.Services.AddSingleton<RtcProxy>();
        builder.Services.AddMemoryCache(cache => cache.SizeLimit = 10_000);

        if (options.ExitOnStdinEof)
        {
            builder.Services.AddHostedService<ParentWatcher>();
        }

        if (resolver is null)
        {
            builder.Services.AddSingleton(_ => NpgsqlDataSource.Create(options.ConnectionString));
            builder.Services.AddSingleton<IAllocationResolver>(services => new DatabaseAllocationResolver(services.GetRequiredService<NpgsqlDataSource>(), services.GetRequiredService<IMemoryCache>()));
        }
        else
        {
            builder.Services.AddSingleton(resolver);
        }

        builder.Services.AddHttpClient(RtcProxy.HttpClientName)
            .ConfigurePrimaryHttpMessageHandler(() => new SocketsHttpHandler { AllowAutoRedirect = false, UseCookies = false, ConnectTimeout = TimeSpan.FromSeconds(5) })
            .ConfigureHttpClient(client => client.Timeout = TimeSpan.FromSeconds(15));

        builder.Services.Configure<ForwardedHeadersOptions>(forwarded =>
        {
            forwarded.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
            forwarded.ForwardLimit = null;
            foreach (var network in options.TrustedProxies)
            {
                forwarded.KnownIPNetworks.Add(network);
            }
        });

        var healthPath = $"{options.BasePath}/health";

        builder.Services.AddRateLimiter(limiter =>
        {
            limiter.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
            limiter.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(context =>
            {
                if (context.Request.Path == healthPath)
                {
                    return RateLimitPartition.GetNoLimiter(string.Empty);
                }

                var federation = RtcProxy.IsFederationPath(context.Request.Path);
                var permits = federation ? SignalOptions.FederationUpgradesPerMinute : options.UpgradesPerMinute;
                return RateLimitPartition.GetFixedWindowLimiter(
                    RtcProxy.AddressKey(context, federation),
                    _ => new FixedWindowRateLimiterOptions { PermitLimit = permits, Window = TimeSpan.FromMinutes(1), QueueLimit = 0 });
            });
        });

        var app = builder.Build();

        app.UseForwardedHeaders();
        app.Use((context, next) =>
        {
            context.Response.Headers.XContentTypeOptions = "nosniff";
            context.Response.Headers.ContentSecurityPolicy = "default-src 'none'; frame-ancestors 'none'; sandbox";
            return next(context);
        });
        app.UseRateLimiter();
        app.UseWebSockets(new WebSocketOptions { KeepAliveInterval = TimeSpan.FromSeconds(30) });

        app.MapGet(healthPath, () => Results.Text("ok"));
        app.Map($"{options.BasePath}/rtc", (HttpContext context, RtcProxy proxy) => proxy.HandleAsync(context));
        app.Map($"{options.BasePath}/rtc/{{**rest}}", (HttpContext context, RtcProxy proxy) => proxy.HandleAsync(context));
        app.Map($"{options.RemotePath}/{{session}}/rtc", (HttpContext context, RtcProxy proxy) => proxy.HandleRemoteAsync(context));
        app.Map($"{options.RemotePath}/{{session}}/rtc/{{**rest}}", (HttpContext context, RtcProxy proxy) => proxy.HandleRemoteAsync(context));
        app.Map($"{SignalOptions.FederationPath}/rtc", (HttpContext context, RtcProxy proxy) => proxy.HandleAsync(context));
        app.Map($"{SignalOptions.FederationPath}/rtc/{{**rest}}", (HttpContext context, RtcProxy proxy) => proxy.HandleAsync(context));

        return app;
    }
}
