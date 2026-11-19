using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Net;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Hi3Helper.Sophon.Structs;
using Hi3Helper.Sophon;
using System.Threading.Tasks.Dataflow;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text.Json;

namespace Core
{
    internal sealed class OfficialBuildCacheHandler : DelegatingHandler {
        public OfficialBuildCacheHandler(HttpMessageHandler inner) : base(inner) {}
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) {
            var cached = Environment.GetEnvironmentVariable("SOPHON_BUILD_JSON");
            if (!string.IsNullOrEmpty(cached) && request.RequestUri?.Host == "sg-public-api.hoyoverse.com" && request.RequestUri.AbsolutePath.EndsWith("/getBuild")) {
                return new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(await File.ReadAllTextAsync(cached, token), Encoding.UTF8, "application/json"), RequestMessage = request };
            }
            return await base.SendAsync(request, token);
        }
    }
    internal class Downloader
    {
        private static string _cancelMessage = string.Empty;
        private static bool _isRetry = true;

        public static async Task<int> StartDownload(string prevManifestUrl, string newManifestUrl, int threads, int maxHttpHandle, string outputDir, string matchingField)
        {

        InternalStartDownload:
            _isRetry = false;
            using (CancellationTokenSource tokenSource = new CancellationTokenSource())
            {
                _cancelMessage = "[\"C\"] Stop or [\"R\"] Restart";
                using (SocketsHttpHandler httpHandler = new SocketsHttpHandler
                {
                    MaxConnectionsPerServer = maxHttpHandle,
                    UseProxy = false,
                    ConnectTimeout = TimeSpan.FromSeconds(20),
                    ConnectCallback = async (context, cancellation) => {
                        var address = context.DnsEndPoint.Host == "autopatchhk.yuanshen.com"
                            ? Environment.GetEnvironmentVariable("SOPHON_CDN_IP") : null;
                        var socket = new Socket(SocketType.Stream, ProtocolType.Tcp);
                        try {
                            var directInterface = Environment.GetEnvironmentVariable("SOPHON_DIRECT_INTERFACE");
                            var directAddress = Environment.GetEnvironmentVariable("SOPHON_DIRECT_ADDRESS");
                            if (!string.IsNullOrEmpty(directInterface) && !string.IsNullOrEmpty(directAddress)) {
                                // Windows IP_UNICAST_IF = 31; interface index is network byte order.
                                socket.SetSocketOption(SocketOptionLevel.IP, (SocketOptionName)31, IPAddress.HostToNetworkOrder(int.Parse(directInterface)));
                                socket.Bind(new IPEndPoint(IPAddress.Parse(directAddress), 0));
                            }
                            await socket.ConnectAsync(new DnsEndPoint(address ?? context.DnsEndPoint.Host, context.DnsEndPoint.Port), cancellation);
                            return new NetworkStream(socket, ownsSocket: true);
                        } catch { socket.Dispose(); throw; }
                    }
                })
                using (HttpClient httpClient = new HttpClient(new OfficialBuildCacheHandler(httpHandler))
                {
                    DefaultRequestVersion = HttpVersion.Version11,
                    DefaultVersionPolicy = HttpVersionPolicy.RequestVersionOrLower,
                })
                {
                    if (!Directory.Exists(outputDir))
                    {
                        Directory.CreateDirectory(outputDir);
                    }

                    // fetch assets
                    if (!Program.silent) Console.WriteLine("Fetching assets...");

                    (List<SophonAsset> sophonAssets, long updateSize) = await Assets.GetAssetsFromManifests(
                        httpClient,
                        matchingField,
                        prevManifestUrl,
                        newManifestUrl,
                        tokenSource
                    );

                    long totalSizeDiff = sophonAssets.GetCalculatedDiffSize(true);
                    string totalSizeDiffUnit = Utils.FormatSize(totalSizeDiff);
                    string totalSizeUnit = Utils.FormatSize(updateSize);
                    var manifestSummary = new {
                        package = matchingField,
                        totalBytes = updateSize,
                        files = sophonAssets.Select(asset => new { name = asset.AssetName, size = asset.AssetSize, md5 = asset.AssetHash }).ToArray()
                    };
                    await File.WriteAllTextAsync(Path.Combine(outputDir, "download-manifest-" + matchingField + ".json"), System.Text.Json.JsonSerializer.Serialize(manifestSummary));
                    if (Program.planOnly) {
                        Console.WriteLine($"PLAN: {sophonAssets.Count} files, {updateSize} bytes ({totalSizeUnit})");
                        return 0;
                    }

                    if (!Program.silent)
                    {
                        Console.WriteLine($"* Found {sophonAssets.Count} assets");
                        if (newManifestUrl != "")
                        {
                            Console.WriteLine($"* Update data is {totalSizeDiffUnit}");
                            Console.WriteLine($"* Because the full assets will be downloaded, total download size is {totalSizeUnit}");
                        }
                        else
                        {
                            Console.WriteLine($"* Total download size is {totalSizeUnit}");
                        }

                        Console.Write("Continue? (y/n): ");
                        var input = Console.ReadLine()?.Trim().ToLower();
                        bool yes = input == "y" || input == "yes";

                        if (!yes)
                        {
                            Console.WriteLine("Aborting...");
                            return 0;
                        }
                    }

                    long currentRead = 0;
                    long completedFiles = 0;
                    long lastReport = -3000;
                    var progressLock = new object();
                    if (!Console.IsInputRedirected) _ = Task.Run(() => AppExitTrigger(tokenSource));

                    ParallelOptions parallelOptions = new ParallelOptions
                    {
                        CancellationToken = tokenSource.Token,
                        MaxDegreeOfParallelism = threads
                    };

                    Stopwatch stopwatch = Stopwatch.StartNew();
                    void ReportProgress(bool finished = false) {
                        lock (progressLock) {
                            if (!finished && stopwatch.ElapsedMilliseconds - lastReport < 2000) return;
                            lastReport = stopwatch.ElapsedMilliseconds;
                            var progress = new {
                                package = matchingField, state = finished ? "completed" : "downloading",
                                bytesWritten = Interlocked.Read(ref currentRead), totalBytes = updateSize,
                                completedFiles = Interlocked.Read(ref completedFiles), totalFiles = sophonAssets.Count,
                                elapsedSeconds = stopwatch.Elapsed.TotalSeconds, updatedAt = DateTimeOffset.Now
                            };
                            string progressPath = Path.Combine(outputDir, "download-progress-" + matchingField + ".json");
                            File.WriteAllText(progressPath + ".tmp", JsonSerializer.Serialize(progress));
                            File.Move(progressPath + ".tmp", progressPath, true);
                        }
                    }
                    ReportProgress();

                    try
                    {
                        // Keep partial files. Each existing chunk is MD5-checked by
                        // PerformWriteStreamThreadAsync before it can be reused.

                        _isRetry = false;

                        ActionBlock<Tuple<SophonAsset, HttpClient>> downloadTaskQueue = new(
                            async ctx =>
                            {
                                SophonAsset asset = ctx.Item1;
                                HttpClient client = ctx.Item2;
                                string outputPath = Path.GetFullPath(Path.Combine(outputDir, asset.AssetName));
                                if (!outputPath.StartsWith(Path.GetFullPath(outputDir) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
                                    throw new InvalidDataException("Asset path escapes output folder");
                                if (asset.AssetSize == 0) {
                                    Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
                                    await File.WriteAllBytesAsync(outputPath, Array.Empty<byte>());
                                    Interlocked.Increment(ref completedFiles);
                                    ReportProgress();
                                    return;
                                }
                                if (File.Exists(outputPath) && new FileInfo(outputPath).Length == asset.AssetSize) {
                                    using var existing = File.OpenRead(outputPath);
                                    string existingHash = Convert.ToHexString(await MD5.HashDataAsync(existing));
                                    if (existingHash.Equals(asset.AssetHash, StringComparison.OrdinalIgnoreCase)) {
                                        Interlocked.Add(ref currentRead, asset.AssetSize);
                                        Interlocked.Increment(ref completedFiles);
                                        ReportProgress();
                                        return;
                                    }
                                }

                                await asset.WriteUpdateAsync(
                                    client,
                                    outputDir,
                                    outputDir,
                                    outputDir,
                                    true,
                                    read =>
                                    {
                                        Interlocked.Add(ref currentRead, read);
                                        ReportProgress();
                                        string sizeUnit = Utils.FormatSize(currentRead);
                                        string speedUnit = Utils.FormatSize(currentRead / stopwatch.Elapsed.TotalSeconds);
                                        if (!Program.silent) Console.Write($"{_cancelMessage} | {sizeUnit}/{totalSizeUnit} ({totalSizeDiffUnit} diff) ({speedUnit}/s) \r");
                                    },
                                    null,
                                    null,
                                    tokenSource.Token
                                );

                                string outputTempPath = outputPath + "_tempUpdate";
                                using (var downloaded = File.OpenRead(outputTempPath)) {
                                    string actualHash = Convert.ToHexString(await MD5.HashDataAsync(downloaded));
                                    if (!actualHash.Equals(asset.AssetHash, StringComparison.OrdinalIgnoreCase))
                                        throw new InvalidDataException("MD5 mismatch: " + asset.AssetName);
                                }
                                System.IO.File.Move(outputTempPath, outputPath, true);
                                Interlocked.Increment(ref completedFiles);
                                ReportProgress();
                            },
                        new ExecutionDataflowBlockOptions
                        {
                                CancellationToken = tokenSource.Token,
                                MaxDegreeOfParallelism = threads,
                                MaxMessagesPerTask = threads,
                            });

                        foreach (SophonAsset asset in sophonAssets)
                        {
                            await downloadTaskQueue.SendAsync(new Tuple<SophonAsset, HttpClient>(asset, httpClient), tokenSource.Token);
                        }

                        downloadTaskQueue.Complete();
                        await downloadTaskQueue.Completion;
                        ReportProgress(true);
                    }
                    catch (OperationCanceledException)
                    {
                        if (!Program.silent)
                        {
                            Console.WriteLine(""); // failsafe
                            Console.WriteLine("Cancelled !");
                        }
                    }
                    finally
                    {
                        stopwatch.Stop();
                    }
                };
            }

            if (_isRetry)
                goto InternalStartDownload;

            return 0;
        }

        private static void AppExitTrigger(CancellationTokenSource tokenSource)
        {
            while (true)
            {
                ConsoleKeyInfo keyInfo = Console.ReadKey(true);
                switch (keyInfo.Key)
                {
                    case ConsoleKey.C:
                        _cancelMessage = "Canceling...";
                        tokenSource.Cancel();
                        return;
                    case ConsoleKey.R:
                        _isRetry = true;
                        tokenSource.Cancel();
                        return;
                }
            }
        }
    }
}
