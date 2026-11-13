namespace VoiceSignal;

public sealed class ParentWatcher(IHostApplicationLifetime lifetime, ILogger<ParentWatcher> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var closed = Task.Factory.StartNew(WaitForEndOfInput, CancellationToken.None, TaskCreationOptions.LongRunning, TaskScheduler.Default);
        var stopped = Task.Delay(Timeout.Infinite, stoppingToken);

        if (await Task.WhenAny(closed, stopped) == closed)
        {
            logger.LogInformation("The parent process closed standard input; shutting down");
            lifetime.StopApplication();
        }
    }

    private static void WaitForEndOfInput()
    {
        using var input = Console.OpenStandardInput();
        var buffer = new byte[256];
        while (input.Read(buffer, 0, buffer.Length) > 0)
        {
        }
    }
}
